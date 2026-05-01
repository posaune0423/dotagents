#!/usr/bin/env bash
# Maps the current (or given) branch to one of GitHub's stock default labels for new repos:
# bug, documentation, duplicate, enhancement, good first issue, help wanted, invalid,
# question, wontfix. Anything else falls back to enhancement.
#
# shellcheck shell=bash

infer_github_default_label_from_git() {
  local branch="${1:-}"
  if [[ -z "$branch" ]]; then
    branch="$(git branch --show-current 2>/dev/null || true)"
  fi
  if [[ -z "$branch" ]]; then
    printf '%s\n' 'enhancement'
    return 0
  fi

  local prefix="${branch%%/*}"
  prefix="$(printf '%s' "$prefix" | tr '[:upper:]' '[:lower:]')"

  case "$prefix" in
    fix | bugfix | hotfix | patch)
      printf '%s\n' 'bug'
      ;;
    docs | doc)
      printf '%s\n' 'documentation'
      ;;
    question)
      printf '%s\n' 'question'
      ;;
    duplicate)
      printf '%s\n' 'duplicate'
      ;;
    invalid)
      printf '%s\n' 'invalid'
      ;;
    wontfix)
      printf '%s\n' 'wontfix'
      ;;
    help-wanted | helpwanted)
      printf '%s\n' 'help wanted'
      ;;
    good-first-issue | goodfirstissue)
      printf '%s\n' 'good first issue'
      ;;
    feat | feature)
      printf '%s\n' 'enhancement'
      ;;
    *)
      printf '%s\n' 'enhancement'
      ;;
  esac
}
