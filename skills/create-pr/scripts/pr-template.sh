#!/usr/bin/env bash
# Locates the repository's pull request template and prints it, so the PR body
# can follow it. `gh pr create --body-file` bypasses GitHub's template
# handling, so the skill has to read the template itself.
#
# Exit codes: 0 found, 1 none, 2 several candidates (pass --name to pick one).
set -euo pipefail

usage() {
	cat <<'USAGE'
Usage: pr-template.sh [--path] [--name <file.md>]

Prints the PR template content (or its absolute path with --path).
Searches, in order: .github/, repository root, docs/ for
PULL_REQUEST_TEMPLATE.md (case-insensitive), then .github/PULL_REQUEST_TEMPLATE/*.md.
When that directory holds several templates, --name selects one.
USAGE
}

print_path=0
name=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--path)
		print_path=1
		shift
		;;
	--name)
		[[ $# -ge 2 && -n "${2:-}" ]] || {
			echo "Missing value for --name" >&2
			usage >&2
			exit 1
		}
		name="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown arg: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# First single-file match wins; directories are searched in GitHub's own order.
find_single() {
	local dir hit
	for dir in "${root}/.github" "${root}" "${root}/docs"; do
		[[ -d "${dir}" ]] || continue
		hit="$(find "${dir}" -maxdepth 1 -type f -iname 'pull_request_template.md' 2>/dev/null | sort | sed -n 1p)"
		if [[ -n "${hit}" ]]; then
			printf '%s\n' "${hit}"
			return 0
		fi
	done
	return 0
}

template=""
template="$(find_single)"

if [[ -z "${template}" ]]; then
	tpl_dir="$(find "${root}/.github" -maxdepth 1 -type d -iname 'pull_request_template' 2>/dev/null | sed -n 1p || true)"
	if [[ -n "${tpl_dir}" ]]; then
		if [[ -n "${name}" ]]; then
			# Basename only, so --name cannot read files outside the template dir.
			[[ "${name}" != */* && "${name}" == *.md ]] || {
				echo "--name must be a Markdown filename inside ${tpl_dir}" >&2
				exit 1
			}
			[[ -f "${tpl_dir}/${name}" ]] || {
				echo "No template named ${name} in ${tpl_dir}" >&2
				exit 1
			}
			template="${tpl_dir}/${name}"
		else
			candidates=()
			while IFS= read -r f; do
				[[ -n "${f}" ]] && candidates+=("${f}")
			done < <(find "${tpl_dir}" -maxdepth 1 -type f -iname '*.md' 2>/dev/null | sort)
			if [[ ${#candidates[@]} -eq 1 ]]; then
				template="${candidates[0]}"
			elif [[ ${#candidates[@]} -gt 1 ]]; then
				echo "Several PR templates; pick one with --name <file>:" >&2
				printf '  %s\n' "${candidates[@]##*/}" >&2
				exit 2
			fi
		fi
	fi
fi

[[ -n "${template}" ]] || exit 1

if [[ "${print_path}" == "1" ]]; then
	printf '%s\n' "${template}"
else
	cat "${template}"
fi
