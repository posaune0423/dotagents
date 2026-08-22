#!/usr/bin/env bash
set -euo pipefail
umask 077

STATE_DIR="/Users/asumayamada/.local/state/dotagents/safe-dev-storage-cleanup"
readonly RETENTION_HOURS=168
readonly STALE_LOCK_SECONDS=$((6 * 60 * 60))
MODE="dry-run"
LOCK_OWNED=false
before_file=""
containers_file=""
builder_file=""
image_file=""
after_file=""

usage() {
	cat <<'EOF'
cleanup-docker.sh [--execute] [--state-dir <path>]

Safely removes only dangling Docker build cache and dangling images older than
seven days. Containers, volumes, networks, tagged images, and all-unused cache
are outside this script's scope. Defaults to dry-run.
EOF
}

fail() {
	echo "ERROR: $*" >&2
	exit 1
}

release_lock() {
	local lock_dir="${STATE_DIR}/.docker-run-lock"
	local owner_file="${lock_dir}/owner.json"
	local owner_tmp="${lock_dir}/owner.$$.json"
	local owner_pid=""

	if [[ "${LOCK_OWNED}" != "true" ]]; then
		return
	fi
	if [[ -f "${owner_file}" ]]; then
		owner_pid="$(jq -r '.pid // empty' "${owner_file}" 2>/dev/null || true)"
		[[ "${owner_pid}" == "$$" ]] || return
	fi
	unlink "${owner_tmp}" 2>/dev/null || true
	unlink "${owner_file}" 2>/dev/null || true
	rmdir "${lock_dir}" 2>/dev/null || true
	LOCK_OWNED=false
}

on_exit() {
	local file
	release_lock
	for file in "${before_file}" "${containers_file}" "${builder_file}" "${image_file}" "${after_file}"; do
		[[ -z "${file}" || ! -f "${file}" ]] || unlink "${file}" 2>/dev/null || true
	done
}

trap on_exit EXIT
trap 'exit 130' INT TERM

while [[ $# -gt 0 ]]; do
	case "$1" in
	--execute)
		MODE="execute"
		shift
		;;
	--state-dir)
		[[ -n "${2:-}" ]] || fail "--state-dir requires a path"
		STATE_DIR="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage
		fail "unknown argument: $1"
		;;
	esac
done

for command_name in docker jq ps; do
	command -v "${command_name}" >/dev/null 2>&1 || fail "required command is unavailable: ${command_name}"
done

mkdir -p -- "${STATE_DIR}"

acquire_lock() {
	local lock_dir="${STATE_DIR}/.docker-run-lock"
	local owner_file="${lock_dir}/owner.json"
	local now pid started_at saved_start current_start process_start owner_tmp
	local ps_err ps_rc lock_mtime tomb metadata

	if mkdir "${lock_dir}" 2>/dev/null; then
		LOCK_OWNED=true
	else
		if [[ -f "${owner_file}" ]]; then
			pid="$(jq -r '.pid // empty' "${owner_file}" 2>/dev/null)"
			started_at="$(jq -r '.startedAt // empty' "${owner_file}" 2>/dev/null)"
			saved_start="$(jq -r '.processStart // empty' "${owner_file}" 2>/dev/null)"
			[[ "${pid}" =~ ^[0-9]+$ && "${started_at}" =~ ^[0-9]+$ && -n "${saved_start}" ]] || {
				echo "SKIP: Docker cleanup lock owner metadata is invalid" >&2
				exit 0
			}
			ps_err="$(mktemp "${STATE_DIR}/docker-lock-ps.XXXXXX")"
			set +e
			current_start="$(ps -p "${pid}" -o lstart= 2>"${ps_err}" | sed 's/^[[:space:]]*//')"
			ps_rc=$?
			set -e
			if [[ "${ps_rc}" -eq 0 && -n "${current_start}" && "${current_start}" == "${saved_start}" ]]; then
				unlink "${ps_err}" 2>/dev/null || true
				echo "SKIP: another Docker cleanup process owns the lock" >&2
				exit 0
			fi
			if [[ "${ps_rc}" -ne 1 || -s "${ps_err}" || -n "${current_start}" ]]; then
				unlink "${ps_err}" 2>/dev/null || true
				echo "SKIP: Docker cleanup lock owner process could not be verified" >&2
				exit 0
			fi
			unlink "${ps_err}" 2>/dev/null || true
		else
			lock_mtime="$(stat -f %m "${lock_dir}" 2>/dev/null || true)"
			if [[ ! "${lock_mtime}" =~ ^[0-9]+$ ]]; then
				lock_mtime="$(stat -c %Y "${lock_dir}" 2>/dev/null || true)"
			fi
			[[ "${lock_mtime}" =~ ^[0-9]+$ ]] || {
				echo "SKIP: ownerless Docker cleanup lock age is unknown" >&2
				exit 0
			}
			started_at="${lock_mtime}"
		fi
		now="$(date +%s)"
		if ((now - started_at < STALE_LOCK_SECONDS)); then
			echo "SKIP: Docker cleanup lock is not old enough to recover safely" >&2
			exit 0
		fi
		tomb="${lock_dir}.stale.$$.$RANDOM"
		mv -- "${lock_dir}" "${tomb}" 2>/dev/null || {
			echo "SKIP: another process claimed stale Docker-lock recovery" >&2
			exit 0
		}
		if ! mkdir "${lock_dir}" 2>/dev/null; then
			for metadata in "${tomb}"/owner*.json; do
				[[ ! -f "${metadata}" ]] || unlink "${metadata}" 2>/dev/null || true
			done
			rmdir "${tomb}" 2>/dev/null || true
			echo "SKIP: another process acquired the Docker cleanup lock" >&2
			exit 0
		fi
		LOCK_OWNED=true
		for metadata in "${tomb}"/owner*.json; do
			[[ ! -f "${metadata}" ]] || unlink "${metadata}" 2>/dev/null || true
		done
		rmdir "${tomb}" 2>/dev/null || true
	fi

	process_start="$(ps -p $$ -o lstart= | sed 's/^[[:space:]]*//')"
	owner_tmp="${lock_dir}/owner.$$.json"
	jq -n \
		--argjson pid "$$" \
		--arg process_start "${process_start}" \
		--argjson started_at "$(date +%s)" \
		--arg mode "${MODE}" \
		'{pid: $pid, processStart: $process_start, startedAt: $started_at, mode: $mode}' >"${owner_tmp}"
	mv -- "${owner_tmp}" "${owner_file}"
}

write_report() {
	local status="$1"
	local reason="$2"
	local before_file="$3"
	local containers_file="$4"
	local builder_file="$5"
	local image_file="$6"
	local after_file="$7"
	local report_tmp="${STATE_DIR}/docker-latest.$$.json"

	jq -n \
		--arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--arg mode "${MODE}" \
		--arg status "${status}" \
		--arg reason "${reason}" \
		--arg before "$(<"${before_file}")" \
		--arg containers "$(<"${containers_file}")" \
		--arg builder "$(<"${builder_file}")" \
		--arg image "$(<"${image_file}")" \
		--arg after "$(<"${after_file}")" \
		--argjson retention_hours "${RETENTION_HOURS}" \
		'{
			generatedAt: $generated_at,
			mode: $mode,
			status: $status,
			reason: $reason,
			retentionHours: $retention_hours,
			before: $before,
			containers: $containers,
			builderPrune: $builder,
			imagePrune: $image,
			after: $after
		}' >"${report_tmp}"
	mv -- "${report_tmp}" "${STATE_DIR}/docker-latest.json"
}

active_build_count() {
	local process_snapshot

	process_snapshot="$(ps -axo pid=,command=)" || return 2
	awk -v self="$$" '
		$1 != self && ($0 ~ /(^|[ \/])docker([[:space:]][^[:space:]]+)*[[:space:]]+(build|bake)([[:space:]]|$)/ || $0 ~ /(^|[ \/])docker-compose([[:space:]][^[:space:]]+)*[[:space:]]+build([[:space:]]|$)/ || $0 ~ /(^|[ \/])devcontainer([[:space:]][^[:space:]]+)*[[:space:]]+build([[:space:]]|$)/ || $0 ~ /(^|[ \/])buildctl([[:space:]]|$)/) { count++ }
		END { print count + 0 }
	' <<<"${process_snapshot}"
}

acquire_lock

before_file="$(mktemp "${STATE_DIR}/docker-before.XXXXXX")"
containers_file="$(mktemp "${STATE_DIR}/docker-containers.XXXXXX")"
builder_file="$(mktemp "${STATE_DIR}/docker-builder.XXXXXX")"
image_file="$(mktemp "${STATE_DIR}/docker-image.XXXXXX")"
after_file="$(mktemp "${STATE_DIR}/docker-after.XXXXXX")"
if ! docker info >/dev/null 2>&1; then
	write_report "skipped" "Docker engine is unavailable" "${before_file}" "${containers_file}" \
		"${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: Docker engine is unavailable"
	exit 0
fi

if ! build_process_count="$(active_build_count)"; then
	write_report "skipped" "process inventory for active Docker builds failed" "${before_file}" "${containers_file}" \
		"${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: active Docker build detection failed"
	exit 0
fi
if [[ "${build_process_count}" -gt 0 ]]; then
	write_report "skipped" "active Docker build process detected; count=${build_process_count}" "${before_file}" "${containers_file}" \
		"${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: active Docker build process detected"
	exit 0
fi

docker system df -v >"${before_file}" 2>&1 || {
	write_report "skipped" "docker system df -v failed" "${before_file}" "${containers_file}" \
		"${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: Docker inventory failed"
	exit 0
}
docker ps -a --format '{{.ID}} {{.Image}} {{.Status}}' >"${containers_file}" 2>&1 || {
	write_report "skipped" "docker ps -a failed" "${before_file}" "${containers_file}" \
		"${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: Docker container inventory failed"
	exit 0
}

if [[ "${MODE}" == "dry-run" ]]; then
	write_report "dry-run" "prune commands were not executed" "${before_file}" "${containers_file}" \
		"${builder_file}" "${image_file}" "${after_file}"
	echo "DRY-RUN: Docker prune commands were not executed"
	exit 0
fi

if ! build_process_count="$(active_build_count)"; then
	write_report "skipped" "final process inventory before builder prune failed" "${before_file}" "${containers_file}" \
		"${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: final active-build detection failed before builder prune"
	exit 0
fi
if [[ "${build_process_count}" -gt 0 ]]; then
	write_report "skipped" "build started before builder prune; count=${build_process_count}" "${before_file}" \
		"${containers_file}" "${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: active Docker build detected before builder prune"
	exit 0
fi

docker builder prune --filter "until=${RETENTION_HOURS}h" --force >"${builder_file}" 2>&1 || {
	write_report "partial" "bounded builder prune failed; image prune was not attempted" "${before_file}" \
		"${containers_file}" "${builder_file}" "${image_file}" "${after_file}"
	echo "ERROR: bounded Docker builder prune failed" >&2
	exit 1
}

if ! build_process_count="$(active_build_count)"; then
	docker system df >"${after_file}" 2>&1 || true
	write_report "partial" "builder prune completed; process inventory before image prune failed" "${before_file}" \
		"${containers_file}" "${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: image prune skipped because final active-build detection failed"
	exit 0
fi
if [[ "${build_process_count}" -gt 0 ]]; then
	docker system df >"${after_file}" 2>&1 || true
	write_report "partial" "builder prune completed; build started before image prune; count=${build_process_count}" \
		"${before_file}" "${containers_file}" "${builder_file}" "${image_file}" "${after_file}"
	echo "SKIP: image prune skipped because an active Docker build started"
	exit 0
fi

docker image prune --filter "until=${RETENTION_HOURS}h" --force >"${image_file}" 2>&1 || {
	docker system df >"${after_file}" 2>&1 || true
	write_report "partial" "bounded image prune failed; no broader cleanup attempted" "${before_file}" \
		"${containers_file}" "${builder_file}" "${image_file}" "${after_file}"
	echo "ERROR: bounded Docker image prune failed" >&2
	exit 1
}

docker system df >"${after_file}" 2>&1 || true
write_report "completed" "only dangling cache and images older than seven days were targeted" "${before_file}" \
	"${containers_file}" "${builder_file}" "${image_file}" "${after_file}"
echo "PASS: bounded Docker cleanup completed"
