#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLEANUP_SCRIPT="${ROOT}/schedules/safe-dev-storage-cleanup/scripts/cleanup-worktrees.sh"
DOCKER_SCRIPT="${ROOT}/schedules/safe-dev-storage-cleanup/scripts/cleanup-docker.sh"
TEST_ROOT="$(mktemp -d)"
REMOTE="${TEST_ROOT}/remote.git"
MAIN="${TEST_ROOT}/main"
WORKTREES="${TEST_ROOT}/worktrees"
FAKE_BIN="${TEST_ROOT}/bin"

cleanup() {
	rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[[ -x "${CLEANUP_SCRIPT}" ]] || fail "missing executable cleanup-worktrees.sh"
[[ -x "${DOCKER_SCRIPT}" ]] || fail "missing executable cleanup-docker.sh"

mkdir -p -- "${WORKTREES}" "${FAKE_BIN}"
git init -q --bare "${REMOTE}"
git clone -q "${REMOTE}" "${MAIN}"
git -C "${MAIN}" config user.name test
git -C "${MAIN}" config user.email test@example.com
git -C "${MAIN}" checkout -qb main
printf '%s\n' '.local-only' '.worktrees/' >"${MAIN}/.gitignore"
printf '%s\n' 'base' >"${MAIN}/tracked.txt"
git -C "${MAIN}" add .gitignore tracked.txt
git -C "${MAIN}" commit -qm base
git -C "${MAIN}" push -qu origin main
git -C "${REMOTE}" symbolic-ref HEAD refs/heads/main
git -C "${MAIN}" remote set-head origin -a >/dev/null

cat >"${FAKE_BIN}/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"repo view"* ]]; then
	printf '%s\n' 'example/repo'
	exit 0
fi

branch=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--head)
		branch="$2"
		shift 2
		;;
	*) shift ;;
	esac
done

sha="$(git rev-parse "${branch}")"
if [[ "${branch}" == sha-mismatch ]]; then
	sha="0000000000000000000000000000000000000000"
fi

jq -n \
	--arg branch "${branch}" \
	--arg sha "${sha}" \
	'[{
		number: 1,
		mergedAt: "2020-01-01T00:00:00Z",
		headRefName: $branch,
		headRefOid: $sha,
		headRepository: {nameWithOwner: "example/repo"},
		headRepositoryOwner: {login: "example"},
		baseRefName: "main",
		url: "https://github.com/example/repo/pull/1"
	}]'
FAKE_GH

cat >"${FAKE_BIN}/lsof" <<'FAKE_LSOF'
#!/usr/bin/env bash
set -euo pipefail

path="${!#}"
if [[ "$(basename "${path}")" == "race-window" ]]; then
	: "${LSOF_RACE_DIR:?}"
	mkdir -p -- "${LSOF_RACE_DIR}"
	counter="${LSOF_RACE_DIR}/race-window.count"
	count=0
	[[ ! -f "${counter}" ]] || count="$(<"${counter}")"
	count=$((count + 1))
	printf '%s\n' "${count}" >"${counter}"
	if [[ "${count}" -ge 2 ]]; then
		printf '%s\n' 'created during final validation' >"${path}/.local-only"
	fi
fi
if [[ "$(basename "${path}")" == "recency-window" ]]; then
	: "${LSOF_RACE_DIR:?}"
	mkdir -p -- "${LSOF_RACE_DIR}"
	counter="${LSOF_RACE_DIR}/recency-window.count"
	count=0
	[[ ! -f "${counter}" ]] || count="$(<"${counter}")"
	count=$((count + 1))
	printf '%s\n' "${count}" >"${counter}"
	if [[ "${count}" -ge 2 ]]; then
		touch "${path}/tracked.txt"
	fi
fi
exit 1
FAKE_LSOF

cat >"${FAKE_BIN}/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -euo pipefail

: "${DOCKER_TEST_LOG:?}"
printf '%s\n' "$*" >>"${DOCKER_TEST_LOG}"

case "$*" in
info) printf '%s\n' 'Docker test engine' ;;
"system df" | "system df -v") printf '%s\n' 'TYPE TOTAL ACTIVE SIZE RECLAIMABLE' ;;
"ps -a --format {{.ID}} {{.Image}} {{.Status}}") printf '%s\n' 'container fixture' ;;
"builder prune --filter until=168h --force")
	[[ "${DOCKER_TEST_DELAY:-0}" != "1" ]] || sleep 1
	printf '%s\n' 'Total reclaimed space: 10MB'
	;;
"image prune --filter until=168h --force") printf '%s\n' 'Total reclaimed space: 20MB' ;;
*)
	echo "unexpected docker command: $*" >&2
	exit 2
	;;
esac
FAKE_DOCKER
chmod +x "${FAKE_BIN}/gh" "${FAKE_BIN}/lsof" "${FAKE_BIN}/docker"

create_merged_worktree() {
	local branch="$1"
	local path="${2:-${WORKTREES}/${branch}}"

	git -C "${MAIN}" worktree add -qb "${branch}" "${path}" main
	printf '%s\n' "${branch}" >"${path}/tracked.txt"
	git -C "${path}" add tracked.txt
	git -C "${path}" commit -qm "${branch}"
	git -C "${MAIN}" merge -q --no-ff "${branch}" -m "merge ${branch}"
	git -C "${MAIN}" push -qu origin main
	touch -t 202001010000 "${path}/.gitignore" "${path}/tracked.txt"
	printf '%s\n' "${path}"
}

run_cleanup() {
	local state_dir="$1"
	LSOF_RACE_DIR="${TEST_ROOT}/lsof-race" PATH="${FAKE_BIN}:${PATH}" "${CLEANUP_SCRIPT}" \
		--repo "${MAIN}" \
		--state-dir "${state_dir}" \
		--execute
}

ignored_path="$(create_merged_worktree ignored-files)"
printf '%s\n' 'must survive' >"${ignored_path}/.local-only"
run_cleanup "${TEST_ROOT}/state-ignored" >/dev/null
[[ -d "${ignored_path}" && -f "${ignored_path}/.local-only" ]] || fail "ignored files must protect a worktree"

dirty_path="$(create_merged_worktree dirty-files)"
printf '%s\n' 'dirty' >>"${dirty_path}/tracked.txt"
run_cleanup "${TEST_ROOT}/state-dirty" >/dev/null
[[ -d "${dirty_path}" ]] || fail "dirty worktrees must be preserved"

mismatch_path="$(create_merged_worktree sha-mismatch)"
run_cleanup "${TEST_ROOT}/state-mismatch" >/dev/null
[[ -d "${mismatch_path}" ]] || fail "PR head SHA mismatches must preserve the worktree"

nested_path="$(create_merged_worktree nested-unsafe "${MAIN}/.worktrees/nested-unsafe")"
run_cleanup "${TEST_ROOT}/state-nested" >/dev/null
[[ -d "${nested_path}" ]] || fail "a worktree nested inside the main checkout must be preserved"

race_path="$(create_merged_worktree race-window)"
run_cleanup "${TEST_ROOT}/state-race" >/dev/null
[[ -d "${race_path}" && -f "${race_path}/.local-only" ]] ||
	fail "an ignored file created during final validation must protect the worktree"

recency_path="$(create_merged_worktree recency-window)"
run_cleanup "${TEST_ROOT}/state-recency" >/dev/null
[[ -d "${recency_path}" ]] || fail "a recently touched worktree must survive final validation"

safe_path="$(create_merged_worktree safe-merged)"
run_cleanup "${TEST_ROOT}/state-safe" >/dev/null
[[ ! -e "${safe_path}" ]] || fail "a fully verified merged worktree should be removed"
git -C "${MAIN}" show-ref --verify --quiet refs/heads/safe-merged || fail "cleanup must not delete the branch"

locked_path="$(create_merged_worktree lock-conflict)"
lock_dir="${TEST_ROOT}/state-lock/.run-lock"
mkdir -p -- "${lock_dir}"
process_start="$(ps -p $$ -o lstart= | sed 's/^[[:space:]]*//')"
jq -n \
	--argjson pid "$$" \
	--arg process_start "${process_start}" \
	--argjson started_at "$(date +%s)" \
	'{pid: $pid, processStart: $process_start, startedAt: $started_at}' >"${lock_dir}/owner.json"
run_cleanup "${TEST_ROOT}/state-lock" >/dev/null
[[ -d "${locked_path}" ]] || fail "an active lock must prevent cleanup"

docker_log="${TEST_ROOT}/docker-execute.log"
DOCKER_TEST_LOG="${docker_log}" PATH="${FAKE_BIN}:${PATH}" "${DOCKER_SCRIPT}" \
	--state-dir "${TEST_ROOT}/state-docker" \
	--execute >/dev/null
rg -Fqx 'builder prune --filter until=168h --force' "${docker_log}" || fail "expected bounded builder prune"
rg -Fqx 'image prune --filter until=168h --force' "${docker_log}" || fail "expected bounded image prune"
if rg -q 'system prune|volume prune|container prune|network prune|(builder|image) prune.*( -a( |$)|--all)' "${docker_log}"; then
	fail "Docker cleanup expanded beyond dangling cache and images"
fi

docker_dry_log="${TEST_ROOT}/docker-dry-run.log"
DOCKER_TEST_LOG="${docker_dry_log}" PATH="${FAKE_BIN}:${PATH}" "${DOCKER_SCRIPT}" \
	--state-dir "${TEST_ROOT}/state-docker-dry" >/dev/null
if rg -q 'builder prune|image prune' "${docker_dry_log}"; then
	fail "Docker dry-run must not prune"
fi

ACTIVE_BIN="${TEST_ROOT}/active-bin"
mkdir -p -- "${ACTIVE_BIN}"
cat >"${ACTIVE_BIN}/ps" <<'FAKE_PS'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-p" ]]; then
	exec /bin/ps "$@"
fi

cat <<'PROCESSES'
100 docker compose build api
101 docker-compose build api
102 docker --context desktop-linux build .
103 docker buildx bake
104 devcontainer build --workspace-folder .
PROCESSES
FAKE_PS
chmod +x "${ACTIVE_BIN}/ps"

docker_active_log="${TEST_ROOT}/docker-active.log"
DOCKER_TEST_LOG="${docker_active_log}" PATH="${ACTIVE_BIN}:${FAKE_BIN}:${PATH}" "${DOCKER_SCRIPT}" \
	--state-dir "${TEST_ROOT}/state-docker-active" \
	--execute >/dev/null
if rg -q 'builder prune|image prune' "${docker_active_log}"; then
	fail "active Docker build forms must prevent prune"
fi

RACE_PS_BIN="${TEST_ROOT}/race-ps-bin"
RACE_PS_STATE="${TEST_ROOT}/race-ps-state"
mkdir -p -- "${RACE_PS_BIN}" "${RACE_PS_STATE}"
cat >"${RACE_PS_BIN}/ps" <<'RACE_PS'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-p" ]]; then
	exec /bin/ps "$@"
fi

: "${DOCKER_PS_RACE_DIR:?}"
counter="${DOCKER_PS_RACE_DIR}/count"
count=0
[[ ! -f "${counter}" ]] || count="$(<"${counter}")"
count=$((count + 1))
printf '%s\n' "${count}" >"${counter}"
if [[ "${count}" -ge 2 ]]; then
	printf '%s\n' '200 docker compose build api'
fi
RACE_PS
chmod +x "${RACE_PS_BIN}/ps"

docker_late_build_log="${TEST_ROOT}/docker-late-build.log"
DOCKER_TEST_LOG="${docker_late_build_log}" DOCKER_PS_RACE_DIR="${RACE_PS_STATE}" \
	PATH="${RACE_PS_BIN}:${FAKE_BIN}:${PATH}" "${DOCKER_SCRIPT}" \
	--state-dir "${TEST_ROOT}/state-docker-late-build" \
	--execute >/dev/null
if rg -q 'builder prune|image prune' "${docker_late_build_log}"; then
	fail "a Docker build starting after inventory must prevent prune"
fi

PATH="/usr/bin:/bin:/usr/sbin:/sbin" "${DOCKER_SCRIPT}" --help >/dev/null ||
	fail "Docker cleanup help must work with macOS Bash 3.2 and empty arrays"

docker_race_state="${TEST_ROOT}/state-docker-lock-race"
docker_race_lock="${docker_race_state}/.docker-run-lock"
docker_race_log="${TEST_ROOT}/docker-lock-race.log"
mkdir -p -- "${docker_race_lock}"
touch -t 202001010000 "${docker_race_lock}"
DOCKER_TEST_LOG="${docker_race_log}" DOCKER_TEST_DELAY=1 PATH="${FAKE_BIN}:${PATH}" "${DOCKER_SCRIPT}" \
	--state-dir "${docker_race_state}" --execute >"${TEST_ROOT}/docker-race-1.out" 2>&1 &
race_pid_1=$!
DOCKER_TEST_LOG="${docker_race_log}" DOCKER_TEST_DELAY=1 PATH="${FAKE_BIN}:${PATH}" "${DOCKER_SCRIPT}" \
	--state-dir "${docker_race_state}" --execute >"${TEST_ROOT}/docker-race-2.out" 2>&1 &
race_pid_2=$!
wait "${race_pid_1}"
wait "${race_pid_2}"
prune_count="$(rg -c '^builder prune --filter until=168h --force$' "${docker_race_log}")"
[[ "${prune_count}" == "1" ]] || fail "parallel stale-lock recovery must allow only one cleanup"

echo "PASS: safe developer storage cleanup"
