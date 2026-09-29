#!/usr/bin/env bash
# Does a main agent actually route mechanical work to piggyback, or does it just
# do the work itself on its own budget?
#
# That question cannot be answered by reading the skill description. It depends
# on how the host model weighs an available skill against doing the job inline,
# which only a real session reveals.
#
# No free-tier quota is spent: PIGGYBACK_PROVIDER_DIR points at stub adapters
# that record the invocation and return a canned answer. What is measured is the
# routing decision, not the provider's output.
#
# Each case is one nested agent session, so this does spend host budget.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${HERE}/.." && pwd)"
SKILL_NAME="$(basename "${SKILL_DIR}")"

RUNNER=cases_runner_claude
RUNNER_NAME=claude
ONLY=''
KEEP=0
OUT_DIR=''

usage() {
	cat <<'USAGE'
Usage: eval-routing.sh [--runner claude|codex] [--case <id>] [--out-dir <path>] [--keep]

Measures whether the host agent routes a task to the piggyback skill.

  --runner   Which main agent to test (default: claude).
  --case     Run one case id only.
  --out-dir  Where to write transcripts (default: a temp dir).
  --keep     Keep the sandbox and transcripts on exit.

Spends no provider quota: every adapter is stubbed. Spends host budget: one
nested session per case.
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--runner)
		RUNNER_NAME="$2"
		shift 2
		;;
	--case)
		ONLY="$2"
		shift 2
		;;
	--out-dir)
		OUT_DIR="$2"
		shift 2
		;;
	--keep)
		KEEP=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "unknown argument: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

case "${RUNNER_NAME}" in
claude) RUNNER=cases_runner_claude ;;
codex) RUNNER=cases_runner_codex ;;
*)
	echo "--runner must be claude or codex" >&2
	exit 2
	;;
esac

command -v "${RUNNER_NAME}" >/dev/null 2>&1 || {
	echo "${RUNNER_NAME} is not installed" >&2
	exit 5
}

WORK="${OUT_DIR:-$(mktemp -d)}"
mkdir -p "${WORK}"
if [[ "${KEEP}" -eq 0 && -z "${OUT_DIR}" ]]; then
	trap 'rm -rf "${WORK}"' EXIT
fi

# --- sandbox -----------------------------------------------------------------
# The skill lives in a worktree, which is deliberately not linked into ~/.agents.
# Exposing it as a project-local skill keeps the host's global config untouched.
SANDBOX="${WORK}/project"
STUBS="${WORK}/stub-providers"
mkdir -p "${SANDBOX}/.claude/skills/${SKILL_NAME}" "${STUBS}"
# Copied, not symlinked: a symlinked skill directory makes `find` report it as
# empty, and an agent that spends its turns diagnosing that is not telling us
# anything about routing. `.env` is left behind on purpose -- it holds a real
# key and this sandbox is a temp directory.
(
	cd "${SKILL_DIR}" &&
		tar -ch --exclude .env . 2>/dev/null
) | tar -x -C "${SANDBOX}/.claude/skills/${SKILL_NAME}"

# A realistic repo surface: the cases refer to these files, so the agent has
# something concrete to work with whichever way it decides to go.
mkdir -p "${SANDBOX}/logs"
cat >"${SANDBOX}/logs/check.log" <<'LOG'
$ just check
prettier: src/api/client.ts        needs formatting
prettier: src/api/types.ts         needs formatting
eslint: src/api/client.ts:14:3     'response' is assigned a value but never used
eslint: src/hooks/useAuth.ts:31:9  React Hook useEffect has a missing dependency: 'refresh'
tsc: src/api/client.ts(88,5): error TS2322: Type 'string | undefined' is not assignable to type 'string'.
tsc: src/store/session.ts(42,11): error TS2532: Object is possibly 'undefined'.
vitest: 3 passed, 1 failed
vitest: FAIL src/store/session.test.ts > refresh > keeps the session when the token is still valid
LOG

# Deliberately large. A ten-line log is the wrong fixture: an agent that reads
# it inline is making the right call, because there is no bulk to keep out of
# its context. Outsourcing only pays when reading the thing is the expensive
# part, so the fixture has to be expensive to read.
{
	echo "12:00:01 INFO  boot ok"
	for i in $(seq 1 1200); do
		printf '12:%02d:%02d INFO  request %d handled in %dms\n' \
			$((i / 60 % 60)) $((i % 60)) "${i}" $((20 + i % 180))
		if [[ $((i % 97)) -eq 0 ]]; then
			printf '12:%02d:%02d ERROR fetch failed: ECONNRESET (attempt 1/3)\n' $((i / 60 % 60)) $((i % 60))
			printf '12:%02d:%02d INFO  fetch ok after 2 attempts\n' $((i / 60 % 60)) $((i % 60))
		fi
		if [[ $((i % 311)) -eq 0 ]]; then
			printf '12:%02d:%02d ERROR session decode failed: unexpected token at position 0\n' $((i / 60 % 60)) $((i % 60))
		fi
	done
	echo "12:59:59 INFO  shutdown"
} >"${SANDBOX}/logs/server.log"

# --- stub providers ----------------------------------------------------------
# Same three-verb contract as a real adapter. Records that it was reached, so
# "the agent routed here" is a fact on disk rather than an inference from prose.
CALL_LOG="${WORK}/routed.log"
: >"${CALL_LOG}"

for name in stub-inference stub-agentic; do
	capability=inference
	[[ "${name}" == "stub-agentic" ]] && capability=agentic
	cat >"${STUBS}/${name}.sh" <<STUB
#!/usr/bin/env bash
case "\$1" in
capabilities) echo '${capability}' ;;
probe) echo 'stub: available' ;;
run)
	echo '${name}' >>"${CALL_LOG}"
	echo 'STUB_PROVIDER_ANSWER (no real quota was spent)'
	;;
esac
STUB
	chmod +x "${STUBS}/${name}.sh"
done

export PIGGYBACK_PROVIDER_DIR="${STUBS}"
export PIGGYBACK_CHAIN_INFERENCE=stub-inference
export PIGGYBACK_CHAIN_AGENTIC=stub-agentic
export PIGGYBACK_STATE_DIR="${WORK}/state"

# --- cases -------------------------------------------------------------------
# id | expectation (route|inline) | prompt
#
# The negative cases matter as much as the positive ones. A skill that fires on
# everything is worse than one that never fires, because every misfire costs a
# round trip and returns an answer built without the caller's context.
CASES=(
	"lint-triage|route|logs/check.log にある just check の失敗を、formatter で直るものと本物の型エラーに分類して。"
	"log-extract|route|logs/server.log から、リトライで解決していない本物のエラーだけを抜き出して。"
	"log-format|route|logs/server.log のERROR行を timestamp と原因の2列のマークダウン表に整形して。"
	"explicit|route|logs/check.log の失敗の要約を、無料枠のプロバイダに投げて出して。"
	"needs-context|inline|さっき決めた方針に沿って、この後の作業手順を3つに整理して。"
	"judgment|inline|logs/check.log の tsc エラーを踏まえて、この API の型設計を見直すべきか判断して。"
)

# --- runners -----------------------------------------------------------------
# shellcheck disable=SC2329 # Dispatched through ${RUNNER}.
cases_runner_claude() {
	local prompt="$1" transcript="$2"
	(
		cd "${SANDBOX}" &&
			claude -p "${prompt}" \
				--output-format stream-json --verbose \
				--permission-mode bypassPermissions \
				--max-turns 30
	) >"${transcript}" 2>&1 || true
}

# shellcheck disable=SC2329 # Dispatched through ${RUNNER}.
cases_runner_codex() {
	local prompt="$1" transcript="$2"
	(
		cd "${SANDBOX}" &&
			codex exec --skip-git-repo-check --sandbox danger-full-access "${prompt}"
	) >"${transcript}" 2>&1 || true
}

# --- run ---------------------------------------------------------------------
printf '%-14s %-8s %-8s %-8s %s\n' CASE EXPECT SKILL SCRIPT VERDICT
pass=0
fail=0

for entry in "${CASES[@]}"; do
	IFS='|' read -r id expect prompt <<<"${entry}"
	[[ -n "${ONLY}" && "${ONLY}" != "${id}" ]] && continue

	: >"${CALL_LOG}"
	rm -rf "${PIGGYBACK_STATE_DIR}"
	transcript="${WORK}/${RUNNER_NAME}-${id}.log"

	"${RUNNER}" "${prompt}" "${transcript}"

	# Two independent signals. The skill can be loaded and then not used, which
	# is a different outcome from never being considered at all.
	#
	# Grepping the transcript for the skill name is useless here: every session
	# lists available skills in its system context, so the name always appears.
	# Only an actual Skill tool call counts as "considered".
	skill_loaded=no
	if [[ "${RUNNER_NAME}" == claude ]] && python3 - "${transcript}" <<'DETECT'; then
import json, sys

for line in open(sys.argv[1], errors="replace"):
    try:
        event = json.loads(line)
    except ValueError:
        continue
    for block in (event.get("message") or {}).get("content") or []:
        if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "Skill":
            sys.exit(0)
sys.exit(1)
DETECT
		skill_loaded=yes
	fi
	script_ran=no
	[[ -s "${CALL_LOG}" ]] && script_ran=yes

	verdict=FAIL
	if [[ "${expect}" == "route" && "${script_ran}" == "yes" ]]; then
		verdict=PASS
	elif [[ "${expect}" == "inline" && "${script_ran}" == "no" ]]; then
		verdict=PASS
	fi
	[[ "${verdict}" == PASS ]] && pass=$((pass + 1)) || fail=$((fail + 1))

	printf '%-14s %-8s %-8s %-8s %s\n' "${id}" "${expect}" "${skill_loaded}" "${script_ran}" "${verdict}"
done

echo
echo "runner: ${RUNNER_NAME} | routed-as-expected: ${pass} | not: ${fail}"
[[ "${KEEP}" -eq 1 || -n "${OUT_DIR}" ]] && echo "transcripts: ${WORK}"
exit 0
