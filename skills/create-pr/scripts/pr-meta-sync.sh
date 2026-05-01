#!/usr/bin/env bash
# Adds assignees and labels to the current (or given) PR using pr-defaults.env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../pr-defaults.env"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/infer-github-default-label.sh"

usage() {
  cat <<'USAGE'
Usage: pr-meta-sync.sh [--pr <number>] [--repo owner/repo]

Reads skills/create-pr/pr-defaults.env and runs gh pr edit --add-assignee / --add-label.
Uses the PR for the current branch when --pr is omitted.
USAGE
}

if [[ -f "$DEFAULTS_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$DEFAULTS_FILE"
  set +a
fi

pr=""
repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      pr="$2"
      shift 2
      ;;
    --repo)
      repo="$2"
      shift 2
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

if [[ -z "$pr" ]]; then
  pr="$(gh pr view --json number --jq .number 2>/dev/null || true)"
fi
[[ -n "${pr:-}" ]] || {
  echo "pr-meta-sync.sh: could not determine PR number" >&2
  exit 1
}

repo_args=()
[[ -n "${repo:-}" ]] && repo_args=(--repo "$repo")

if [[ -z "${CREATE_PR_ASSIGNEES+x}" ]]; then
  assignees_raw='@me'
else
  assignees_raw="$CREATE_PR_ASSIGNEES"
fi

edit_args=()
if [[ -n "$assignees_raw" ]]; then
  IFS=',' read -ra parts <<< "$assignees_raw"
  for p in "${parts[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    [[ -z "$p" ]] && continue
    edit_args+=(--add-assignee "$p")
  done
fi

if [[ "${CREATE_PR_NO_LABEL:-}" != "1" ]]; then
  labels_raw=""
  if [[ -n "${CREATE_PR_LABELS:-}" ]]; then
    labels_raw="$CREATE_PR_LABELS"
  else
    labels_raw="$(infer_github_default_label_from_git)"
  fi
  if [[ -n "$labels_raw" ]]; then
    IFS=',' read -ra labs <<< "$labels_raw"
    for l in "${labs[@]}"; do
      l="${l#"${l%%[![:space:]]*}"}"
      l="${l%"${l##*[![:space:]]}"}"
      [[ -z "$l" ]] && continue
      edit_args+=(--add-label "$l")
    done
  fi
fi

if [[ ${#edit_args[@]} -eq 0 ]]; then
  exit 0
fi

gh pr edit "$pr" "${repo_args[@]}" "${edit_args[@]}"
