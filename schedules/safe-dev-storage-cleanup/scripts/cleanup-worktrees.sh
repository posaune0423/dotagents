#!/usr/bin/env bash
set -euo pipefail
umask 077

STATE_DIR="/Users/asumayamada/.local/state/dotagents/safe-dev-storage-cleanup"
readonly MIN_AGE_HOURS=72
MODE="dry-run"
STALE_LOCK_SECONDS=$((6 * 60 * 60))
REPOS=()
REPOS_COUNT=0
LOCK_OWNED=false
EVENTS_FILE=""

usage() {
	cat <<'EOF'
cleanup-worktrees.sh [--execute] [--repo <main-checkout>] [--state-dir <path>]

Safely removes linked Git worktrees only after verifying clean/ignored state,
remote reachability, exact merged-PR SHA and repository identity, inactivity,
and a minimum post-merge/file-age grace period. Defaults to dry-run.
EOF
}

fail() {
	echo "ERROR: $*" >&2
	exit 1
}

record_event() {
	local result="$1"
	local repo="$2"
	local path="$3"
	local reason="$4"
	printf '%s\t%s\t%s\t%s\n' "${result}" "${repo}" "${path}" "${reason}" >>"${EVENTS_FILE}"
}

release_lock() {
	local lock_dir="${STATE_DIR}/.run-lock"
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

cleanup_temporary_files() {
	if [[ -n "${EVENTS_FILE}" && -f "${EVENTS_FILE}" ]]; then
		unlink "${EVENTS_FILE}" 2>/dev/null || true
	fi
}

on_exit() {
	release_lock
	cleanup_temporary_files
}

trap on_exit EXIT
trap 'exit 130' INT TERM

while [[ $# -gt 0 ]]; do
	case "$1" in
	--execute)
		MODE="execute"
		shift
		;;
	--repo)
		[[ -n "${2:-}" ]] || fail "--repo requires a path"
		REPOS+=("$2")
		REPOS_COUNT=$((REPOS_COUNT + 1))
		shift 2
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

for command_name in fd gh git jq lsof ps rg; do
	command -v "${command_name}" >/dev/null 2>&1 || fail "required command is unavailable: ${command_name}"
done

mkdir -p -- "${STATE_DIR}"

acquire_lock() {
	local lock_dir="${STATE_DIR}/.run-lock"
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
				echo "SKIP: cleanup lock owner metadata is invalid" >&2
				exit 0
			}

			ps_err="$(mktemp "${STATE_DIR}/lock-ps.XXXXXX")"
			set +e
			current_start="$(ps -p "${pid}" -o lstart= 2>"${ps_err}" | sed 's/^[[:space:]]*//')"
			ps_rc=$?
			set -e
			if [[ "${ps_rc}" -eq 0 && -n "${current_start}" && "${current_start}" == "${saved_start}" ]]; then
				unlink "${ps_err}" 2>/dev/null || true
				echo "SKIP: another cleanup process owns the lock" >&2
				exit 0
			fi
			if [[ "${ps_rc}" -ne 1 || -s "${ps_err}" || -n "${current_start}" ]]; then
				unlink "${ps_err}" 2>/dev/null || true
				echo "SKIP: cleanup lock owner process could not be verified" >&2
				exit 0
			fi
			unlink "${ps_err}" 2>/dev/null || true
		else
			lock_mtime="$(stat -f %m "${lock_dir}" 2>/dev/null || true)"
			if [[ ! "${lock_mtime}" =~ ^[0-9]+$ ]]; then
				lock_mtime="$(stat -c %Y "${lock_dir}" 2>/dev/null || true)"
			fi
			[[ "${lock_mtime}" =~ ^[0-9]+$ ]] || {
				echo "SKIP: ownerless cleanup lock age is unknown" >&2
				exit 0
			}
			started_at="${lock_mtime}"
		fi

		now="$(date +%s)"
		if ((now - started_at < STALE_LOCK_SECONDS)); then
			echo "SKIP: cleanup lock is not old enough to recover safely" >&2
			exit 0
		fi

		tomb="${lock_dir}.stale.$$.$RANDOM"
		mv -- "${lock_dir}" "${tomb}" 2>/dev/null || {
			echo "SKIP: another process claimed stale-lock recovery" >&2
			exit 0
		}
		if ! mkdir "${lock_dir}" 2>/dev/null; then
			for metadata in "${tomb}"/owner*.json; do
				[[ ! -f "${metadata}" ]] || unlink "${metadata}" 2>/dev/null || true
			done
			rmdir "${tomb}" 2>/dev/null || true
			echo "SKIP: another process acquired the cleanup lock" >&2
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

acquire_lock
EVENTS_FILE="$(mktemp "${STATE_DIR}/worktree-events.XXXXXX")"

if [[ "${REPOS_COUNT}" -eq 0 ]]; then
	command -v ghq >/dev/null 2>&1 || fail "ghq is required when --repo is omitted"
	ghq_output="$(ghq list -p)" || fail "ghq list -p failed"
	while IFS= read -r repo_path; do
		if [[ -n "${repo_path}" ]]; then
			REPOS+=("${repo_path}")
			REPOS_COUNT=$((REPOS_COUNT + 1))
		fi
	done <<<"${ghq_output}"
fi

check_candidate() {
	local main="$1"
	local remote_default="$2"
	local default_branch="$3"
	local repo_slug="$4"
	local path="$5"
	local listed_head="$6"
	local branch_ref="$7"
	local locked="$8"
	local canonical_path branch actual_head status ignored_file upstream ahead_count
	local pr_json pr_count pr_sha pr_branch pr_repo pr_base merged_epoch now recent_path
	local lsof_out lsof_err lsof_rc size_kb final_head final_status final_ignored

	[[ "${path}" != "${main}" ]] || return 0
	[[ "${locked}" == "false" ]] || {
		record_event "skipped" "${main}" "${path}" "worktree is locked"
		return
	}
	[[ "${branch_ref}" == refs/heads/* ]] || {
		record_event "skipped" "${main}" "${path}" "detached or unknown branch"
		return
	}
	[[ "${path}" == /* && "${path}" != "/" && "${path}" != "/Users/asumayamada" ]] || {
		record_event "skipped" "${main}" "${path}" "unsafe worktree path"
		return
	}
	canonical_path="$(cd "${path}" 2>/dev/null && pwd -P)" || {
		record_event "skipped" "${main}" "${path}" "worktree path is unavailable"
		return
	}
	[[ "${canonical_path}" == "${path}" ]] || {
		record_event "skipped" "${main}" "${path}" "worktree path is not canonical"
		return
	}
	case "${main}/" in
	"${path}/"*)
		record_event "skipped" "${main}" "${path}" "worktree path is an ancestor of main checkout"
		return
		;;
	esac
	case "${path}/" in
	"${main}/"*)
		record_event "skipped" "${main}" "${path}" "worktree path is nested inside main checkout"
		return
		;;
	esac

	branch="${branch_ref#refs/heads/}"
	actual_head="$(git -C "${path}" rev-parse HEAD 2>/dev/null)" || {
		record_event "skipped" "${main}" "${path}" "cannot resolve worktree HEAD"
		return
	}
	[[ "${actual_head}" == "${listed_head}" ]] || {
		record_event "skipped" "${main}" "${path}" "worktree HEAD changed during evaluation"
		return
	}

	status="$(git -C "${path}" status --porcelain --untracked-files=all --ignore-submodules=none 2>/dev/null)" || {
		record_event "skipped" "${main}" "${path}" "git status failed"
		return
	}
	[[ -z "${status}" ]] || {
		record_event "skipped" "${main}" "${path}" "dirty or untracked files"
		return
	}

	ignored_file="$(mktemp "${STATE_DIR}/ignored.XXXXXX")"
	if ! git -C "${path}" ls-files --others --ignored --exclude-standard -z >"${ignored_file}" 2>/dev/null; then
		unlink "${ignored_file}" 2>/dev/null || true
		record_event "skipped" "${main}" "${path}" "ignored-file inspection failed"
		return
	fi
	if [[ -s "${ignored_file}" ]]; then
		unlink "${ignored_file}" 2>/dev/null || true
		record_event "skipped" "${main}" "${path}" "ignored files are present"
		return
	fi
	unlink "${ignored_file}" 2>/dev/null || true

	git -C "${main}" merge-base --is-ancestor "${actual_head}" "${remote_default}" >/dev/null 2>&1 || {
		record_event "skipped" "${main}" "${path}" "HEAD is not reachable from remote default branch"
		return
	}

	upstream="$(git -C "${path}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
	if [[ -n "${upstream}" ]]; then
		ahead_count="$(git -C "${path}" rev-list --count "${upstream}..HEAD" 2>/dev/null)" || {
			record_event "skipped" "${main}" "${path}" "cannot compare branch with upstream"
			return
		}
		[[ "${ahead_count}" == "0" ]] || {
			record_event "skipped" "${main}" "${path}" "branch has commits not present in upstream"
			return
		}
	fi

	pr_json="$(cd "${main}" && gh pr list -R "${repo_slug}" --head "${branch}" --state merged --limit 100 \
		--json number,mergedAt,headRefName,headRefOid,headRepository,headRepositoryOwner,baseRefName,url 2>/dev/null)" || {
		record_event "skipped" "${main}" "${path}" "GitHub merged-PR lookup failed"
		return
	}
	pr_count="$(jq 'length' <<<"${pr_json}")"
	[[ "${pr_count}" == "1" ]] || {
		record_event "skipped" "${main}" "${path}" "merged PR is not uniquely identified"
		return
	}
	pr_sha="$(jq -r '.[0].headRefOid // empty' <<<"${pr_json}")"
	pr_branch="$(jq -r '.[0].headRefName // empty' <<<"${pr_json}")"
	pr_repo="$(jq -r '.[0].headRepository.nameWithOwner // empty' <<<"${pr_json}")"
	pr_base="$(jq -r '.[0].baseRefName // empty' <<<"${pr_json}")"
	[[ "${pr_sha}" == "${actual_head}" && "${pr_branch}" == "${branch}" && "${pr_repo}" == "${repo_slug}" &&
		"${pr_base}" == "${default_branch}" ]] || {
		record_event "skipped" "${main}" "${path}" "PR identity, branch, base, or head SHA does not match"
		return
	}
	merged_epoch="$(jq -r '.[0].mergedAt | fromdateiso8601' <<<"${pr_json}" 2>/dev/null)" || {
		record_event "skipped" "${main}" "${path}" "PR merge time is invalid"
		return
	}
	now="$(date +%s)"
	((now - merged_epoch >= MIN_AGE_HOURS * 60 * 60)) || {
		record_event "skipped" "${main}" "${path}" "PR merge is inside the grace period"
		return
	}

	if ((MIN_AGE_HOURS > 0)); then
		recent_path="$(fd -HI --changed-within "${MIN_AGE_HOURS}h" --exclude .git --max-results 1 . "${path}" 2>/dev/null)" || {
			record_event "skipped" "${main}" "${path}" "recent-file inspection failed"
			return
		}
		[[ -z "${recent_path}" ]] || {
			record_event "skipped" "${main}" "${path}" "worktree changed inside the grace period"
			return
		}
	fi

	lsof_out="$(mktemp "${STATE_DIR}/lsof-out.XXXXXX")"
	lsof_err="$(mktemp "${STATE_DIR}/lsof-err.XXXXXX")"
	set +e
	lsof +D "${path}" >"${lsof_out}" 2>"${lsof_err}"
	lsof_rc=$?
	set -e
	if [[ -s "${lsof_out}" ]]; then
		unlink "${lsof_out}" 2>/dev/null || true
		unlink "${lsof_err}" 2>/dev/null || true
		record_event "skipped" "${main}" "${path}" "worktree has open file handles"
		return
	fi
	if [[ -s "${lsof_err}" || ("${lsof_rc}" -ne 0 && "${lsof_rc}" -ne 1) ]]; then
		unlink "${lsof_out}" 2>/dev/null || true
		unlink "${lsof_err}" 2>/dev/null || true
		record_event "skipped" "${main}" "${path}" "open-file inspection was inconclusive"
		return
	fi
	unlink "${lsof_out}" 2>/dev/null || true
	unlink "${lsof_err}" 2>/dev/null || true

	size_kb="$(du -sk "${path}" 2>/dev/null | awk '{print $1}')" || size_kb="unknown"
	if [[ "${MODE}" == "dry-run" ]]; then
		record_event "eligible" "${main}" "${path}" "verified merged PR; size_kb=${size_kb}"
		return
	fi

	# Re-run mutable safety checks immediately before removal to narrow the TOCTOU window.
	lsof_out="$(mktemp "${STATE_DIR}/final-lsof-out.XXXXXX")"
	lsof_err="$(mktemp "${STATE_DIR}/final-lsof-err.XXXXXX")"
	set +e
	lsof +D "${path}" >"${lsof_out}" 2>"${lsof_err}"
	lsof_rc=$?
	set -e
	if [[ -s "${lsof_out}" || -s "${lsof_err}" || ("${lsof_rc}" -ne 0 && "${lsof_rc}" -ne 1) ]]; then
		unlink "${lsof_out}" 2>/dev/null || true
		unlink "${lsof_err}" 2>/dev/null || true
		record_event "skipped" "${main}" "${path}" "final open-file inspection failed or found activity"
		return
	fi
	unlink "${lsof_out}" 2>/dev/null || true
	unlink "${lsof_err}" 2>/dev/null || true
	if ((MIN_AGE_HOURS > 0)); then
		recent_path="$(fd -HI --changed-within "${MIN_AGE_HOURS}h" --exclude .git --max-results 1 . "${path}" 2>/dev/null)" || {
			record_event "skipped" "${main}" "${path}" "final recent-file inspection failed"
			return
		}
		[[ -z "${recent_path}" ]] || {
			record_event "skipped" "${main}" "${path}" "worktree was used after validation"
			return
		}
	fi

	final_head="$(git -C "${path}" rev-parse HEAD 2>/dev/null)" || {
		record_event "skipped" "${main}" "${path}" "final HEAD inspection failed"
		return
	}
	[[ "${final_head}" == "${actual_head}" ]] || {
		record_event "skipped" "${main}" "${path}" "HEAD changed after validation"
		return
	}
	final_status="$(git -C "${path}" status --porcelain --untracked-files=all --ignore-submodules=none 2>/dev/null)" || {
		record_event "skipped" "${main}" "${path}" "final git status failed"
		return
	}
	[[ -z "${final_status}" ]] || {
		record_event "skipped" "${main}" "${path}" "worktree changed after validation"
		return
	}
	final_ignored="$(mktemp "${STATE_DIR}/final-ignored.XXXXXX")"
	if ! git -C "${path}" ls-files --others --ignored --exclude-standard -z >"${final_ignored}" 2>/dev/null; then
		unlink "${final_ignored}" 2>/dev/null || true
		record_event "skipped" "${main}" "${path}" "final ignored-file inspection failed"
		return
	fi
	if [[ -s "${final_ignored}" ]]; then
		unlink "${final_ignored}" 2>/dev/null || true
		record_event "skipped" "${main}" "${path}" "ignored files appeared after validation"
		return
	fi
	unlink "${final_ignored}" 2>/dev/null || true

	if ! git -C "${main}" worktree remove -- "${path}"; then
		record_event "skipped" "${main}" "${path}" "git worktree remove refused; no fallback attempted"
		return
	fi
	if [[ -e "${path}" ]] || git -C "${main}" worktree list --porcelain | rg -Fqx "worktree ${path}"; then
		record_event "error" "${main}" "${path}" "post-removal verification failed"
		return
	fi
	record_event "removed" "${main}" "${path}" "verified merged PR; size_kb=${size_kb}"
}

process_repo() {
	local repo="$1"
	local main remote_default default_branch repo_slug
	local path="" listed_head="" branch_ref="" locked="false" line

	main="$(cd "${repo}" 2>/dev/null && pwd -P)" || {
		record_event "skipped" "${repo}" "" "main checkout is unavailable"
		return
	}
	[[ "$(git -C "${main}" rev-parse --show-toplevel 2>/dev/null)" == "${main}" ]] || {
		record_event "skipped" "${main}" "" "path is not a main checkout root"
		return
	}
	[[ -d "${main}/.git" ]] || {
		record_event "skipped" "${main}" "" "path is a linked worktree, not a main checkout"
		return
	}
	git -C "${main}" fetch --prune origin >/dev/null 2>&1 || {
		record_event "skipped" "${main}" "" "git fetch --prune origin failed"
		return
	}
	remote_default="$(git -C "${main}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || {
		record_event "skipped" "${main}" "" "origin/HEAD is unresolved"
		return
	}
	default_branch="${remote_default#origin/}"
	repo_slug="$(cd "${main}" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || {
		record_event "skipped" "${main}" "" "GitHub repository identity is unresolved"
		return
	}
	[[ "${repo_slug}" == */* ]] || {
		record_event "skipped" "${main}" "" "GitHub repository identity is invalid"
		return
	}

	while IFS= read -r line; do
		if [[ -z "${line}" ]]; then
			if [[ -n "${path}" ]]; then
				check_candidate "${main}" "${remote_default}" "${default_branch}" "${repo_slug}" \
					"${path}" "${listed_head}" "${branch_ref}" "${locked}"
			fi
			path=""
			listed_head=""
			branch_ref=""
			locked="false"
			continue
		fi
		case "${line}" in
		worktree\ *) path="${line#worktree }" ;;
		HEAD\ *) listed_head="${line#HEAD }" ;;
		branch\ *) branch_ref="${line#branch }" ;;
		locked*) locked="true" ;;
		esac
	done < <(
		git -C "${main}" worktree list --porcelain
		printf '\n'
	)
}

if [[ "${REPOS_COUNT}" -gt 0 ]]; then
	for repo in "${REPOS[@]}"; do
		process_repo "${repo}"
	done
fi

events_json="$(jq -Rn '[inputs | split("\t") | {result: .[0], repository: .[1], path: .[2], reason: .[3]}]' <"${EVENTS_FILE}")"
report_tmp="${STATE_DIR}/worktrees-latest.$$.json"
jq -n \
	--arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--arg mode "${MODE}" \
	--argjson min_age_hours "${MIN_AGE_HOURS}" \
	--argjson events "${events_json}" \
	'{generatedAt: $generated_at, mode: $mode, minAgeHours: $min_age_hours, events: $events}' >"${report_tmp}"
mv -- "${report_tmp}" "${STATE_DIR}/worktrees-latest.json"

jq -r '.events[] | "\(.result): \(.path) — \(.reason)"' "${STATE_DIR}/worktrees-latest.json"
