#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
verify-project-links.sh --target <project-root>

Checks that:
  - <project>/.agents exists
  - <project>/.cursor/.codex/.claude point to <project>/.agents/{skills,commands,rules}
  - At least one SKILL.md is visible under each tool's skills path
EOF
}

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  echo "ERROR: --target is required" >&2
  usage >&2
  exit 2
fi

TARGET="$(cd -- "${TARGET}" && pwd)"
AGENTS="${TARGET}/.agents"

[[ -d "${AGENTS}" ]] || { echo "Missing: ${AGENTS}" >&2; exit 1; }
[[ -d "${AGENTS}/skills" ]] || { echo "Missing: ${AGENTS}/skills" >&2; exit 1; }

check_tool() {
  local tool="$1"
  local base="${TARGET}/${tool}"

  [[ -e "${base}" ]] || { echo "Missing: ${base}" >&2; exit 1; }
  [[ -L "${base}/skills" ]] || { echo "Expected symlink: ${base}/skills" >&2; exit 1; }
  [[ -L "${base}/commands" ]] || { echo "Expected symlink: ${base}/commands" >&2; exit 1; }
  [[ -L "${base}/rules" ]] || { echo "Expected symlink: ${base}/rules" >&2; exit 1; }

  local resolved_skills
  resolved_skills="$(cd -- "${base}" && cd -- "$(readlink skills)" && pwd)"
  local resolved_commands
  resolved_commands="$(cd -- "${base}" && cd -- "$(readlink commands)" && pwd)"
  local resolved_rules
  resolved_rules="$(cd -- "${base}" && cd -- "$(readlink rules)" && pwd)"

  [[ "${resolved_skills}" == "${AGENTS}/skills" ]] || { echo "${tool}: skills does not resolve to .agents/skills" >&2; exit 1; }
  [[ "${resolved_commands}" == "${AGENTS}/commands" ]] || { echo "${tool}: commands does not resolve to .agents/commands" >&2; exit 1; }
  [[ "${resolved_rules}" == "${AGENTS}/rules" ]] || { echo "${tool}: rules does not resolve to .agents/rules" >&2; exit 1; }

  # Check at least one SKILL.md visible.
  local any_skill_md=""
  shopt -s nullglob
  for f in "${base}/skills"/*/SKILL.md; do
    any_skill_md="${f}"
    break
  done
  shopt -u nullglob
  [[ -n "${any_skill_md}" ]] || { echo "${tool}: no */SKILL.md found under ${base}/skills" >&2; exit 1; }

  echo "OK: ${tool} sees skills at ${base}/skills (e.g. ${any_skill_md})"
}

check_tool ".cursor"
check_tool ".codex"
check_tool ".claude"

echo "All checks passed."

