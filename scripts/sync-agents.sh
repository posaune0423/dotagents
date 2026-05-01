#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
sync-agents.sh --target <dir> [--delete]

Sync this repo's commands/rules/skills into <dir>/.agents.

Options:
  --target <dir>   Target project directory (required)
  --delete         Also delete files in target that don't exist in source
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

TARGET=""
DELETE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --delete)
      DELETE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
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
DEST="${TARGET}/.agents"

mkdir -p "${DEST}"/{commands,rules,skills}

RSYNC_DELETE=()
if [[ "${DELETE}" == "true" ]]; then
  RSYNC_DELETE=(--delete)
fi

sync_dir() {
  local src="$1"
  local dst="$2"
  if [[ ! -d "${src}" ]]; then
    echo "ERROR: missing source dir: ${src}" >&2
    exit 1
  fi
  rsync -a --checksum "${RSYNC_DELETE[@]}" -- "${src}/" "${dst}/"
}

sync_dir "${REPO_ROOT}/commands" "${DEST}/commands"
sync_dir "${REPO_ROOT}/rules" "${DEST}/rules"
sync_dir "${REPO_ROOT}/skills" "${DEST}/skills"

echo "Synced to ${DEST}"
