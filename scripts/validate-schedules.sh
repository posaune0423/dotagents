#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/schedules"

usage() {
	echo "Usage: $0 [--root <schedules-directory>]" >&2
}

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

validate_rrule() {
	local rrule="$1"
	local part key value item
	local seen_keys=";"
	local parts=()
	local values=()

	IFS=';' read -r -a parts <<<"${rrule}"
	[[ "${parts[0]:-}" =~ ^FREQ=(MINUTELY|HOURLY|DAILY|WEEKLY|MONTHLY|YEARLY)$ ]] ||
		fail "unsupported RRULE frequency: ${rrule}"

	for part in "${parts[@]:1}"; do
		[[ "${part}" == *=* ]] || fail "malformed RRULE property: ${part}"
		key="${part%%=*}"
		value="${part#*=}"
		[[ -n "${value}" ]] || fail "empty RRULE property: ${key}"
		[[ "${seen_keys}" != *";${key};"* ]] || fail "duplicate RRULE property: ${key}"
		seen_keys+="${key};"

		IFS=',' read -r -a values <<<"${value}"
		case "${key}" in
		INTERVAL)
			[[ "${#values[@]}" -eq 1 && "${value}" =~ ^[1-9][0-9]*$ ]] ||
				fail "invalid RRULE INTERVAL: ${value}"
			;;
		BYHOUR | BYMINUTE | BYMONTHDAY | BYMONTH)
			for item in "${values[@]}"; do
				case "${key}" in
				BYHOUR) [[ "${item}" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] || fail "invalid RRULE BYHOUR: ${item}" ;;
				BYMINUTE) [[ "${item}" =~ ^([0-9]|[1-5][0-9])$ ]] || fail "invalid RRULE BYMINUTE: ${item}" ;;
				BYMONTHDAY) [[ "${item}" =~ ^([1-9]|[12][0-9]|3[01])$ ]] || fail "invalid RRULE BYMONTHDAY: ${item}" ;;
				BYMONTH) [[ "${item}" =~ ^([1-9]|1[0-2])$ ]] || fail "invalid RRULE BYMONTH: ${item}" ;;
				esac
			done
			;;
		BYDAY)
			for item in "${values[@]}"; do
				[[ "${item}" =~ ^(MO|TU|WE|TH|FR|SA|SU)$ ]] || fail "invalid RRULE BYDAY: ${item}"
			done
			;;
		*) fail "unsupported RRULE property: ${key}" ;;
		esac
	done
}

if [[ "${1:-}" == "--root" ]]; then
	[[ -n "${2:-}" && -z "${3:-}" ]] || {
		usage
		exit 2
	}
	ROOT="$2"
elif [[ "$#" -ne 0 ]]; then
	usage
	exit 2
fi

command -v fd >/dev/null 2>&1 || fail "fd is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"

[[ -d "${ROOT}" ]] || fail "schedule root does not exist: ${ROOT}"
[[ -f "${ROOT}/schema.json" ]] || fail "missing schema.json"
jq -e . "${ROOT}/schema.json" >/dev/null || fail "schema.json is not valid JSON"
symlink_path="$(fd -HI -t l -d 3 --max-results 1 . "${ROOT}")"
[[ -z "${symlink_path}" ]] || fail "schedule definitions must not contain symlinks: ${symlink_path}"

manifest_count=0
ids_file="$(mktemp)"
cleanup() {
	rm -f -- "${ids_file}"
}
trap cleanup EXIT

while IFS= read -r manifest; do
	manifest_count=$((manifest_count + 1))
	directory="$(dirname "${manifest}")"
	directory_name="$(basename "${directory}")"
	[[ ! -L "${manifest}" ]] || fail "schedule manifest must not be a symlink: ${manifest}"

	jq -e '
		((keys | sort) == (["$schema", "version", "id", "name", "description", "skill", "schedule", "runtime", "targets"] | sort)) and
		(.["$schema"] == "../schema.json") and
		(.version == 1) and
		(.id | type == "string" and test("^[a-z0-9]+(?:-[a-z0-9]+)*$")) and
		(.name | type == "string" and length > 0) and
		(.description | type == "string" and length > 0) and
		(.skill == "SKILL.md") and
		(.schedule | (keys | sort) == ["rrule", "timezone"]) and
		(.schedule.rrule | type == "string" and test("^FREQ=(MINUTELY|HOURLY|DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[A-Z0-9,+-]+)*$")) and
		(.schedule.timezone | type == "string" and length > 0) and
		(.runtime | (keys | sort) == ["execution", "isolation", "platforms", "stateDirectory", "workingDirectory"]) and
		(.runtime.execution | IN("local", "cloud", "either")) and
		(.runtime.workingDirectory | IN("select-on-install", "not-required")) and
		(.runtime.stateDirectory | type == "string" and length > 0) and
		(.runtime.isolation | IN("shared", "worktree", "provider-managed")) and
		(.runtime.platforms | type == "array" and length > 0 and length == (unique | length) and all(IN("macos", "linux", "windows", "any"))) and
		(.targets | type == "array" and length > 0 and length == (unique | length) and all(IN("claude-desktop-local", "claude-code-cloud", "codex-local", "gemini-local"))) and
		(.runtime.execution != "local" or (.targets | all(endswith("-local")))) and
		(.runtime.execution != "cloud" or (.targets | all(endswith("-cloud"))))
	' "${manifest}" >/dev/null || fail "invalid schedule manifest: ${manifest}"

	id="$(jq -r '.id' "${manifest}")"
	rrule="$(jq -r '.schedule.rrule' "${manifest}")"
	timezone="$(jq -r '.schedule.timezone' "${manifest}")"
	[[ "${directory_name}" == "${id}" ]] || fail "directory ${directory_name} must match schedule id ${id}"
	validate_rrule "${rrule}"
	[[ "${timezone}" =~ ^[A-Za-z_+-][A-Za-z0-9_+.-]*(/[A-Za-z0-9_+-][A-Za-z0-9_+.-]*)+$ ]] ||
		fail "invalid IANA timezone: ${timezone}"
	zoneinfo_root="$(cd "${TZDIR:-/usr/share/zoneinfo}" && pwd -P)" || fail "zoneinfo directory is unavailable"
	timezone_parent="$(cd "${zoneinfo_root}/$(dirname "${timezone}")" && pwd -P)" ||
		fail "unknown IANA timezone: ${timezone}"
	case "${timezone_parent}/" in
	"${zoneinfo_root}/"*) ;;
	*) fail "IANA timezone escapes zoneinfo directory: ${timezone}" ;;
	esac
	[[ -f "${timezone_parent}/$(basename "${timezone}")" ]] || fail "unknown IANA timezone: ${timezone}"
	skill_file="${directory}/SKILL.md"
	[[ -s "${skill_file}" ]] || fail "missing or empty skill for ${id}"
	[[ ! -L "${skill_file}" ]] || fail "schedule skill must not be a symlink: ${id}"
	IFS= read -r skill_first_line <"${skill_file}" || fail "cannot read skill for ${id}"
	[[ "${skill_first_line}" == "---" ]] || fail "skill frontmatter must start on line 1: ${id}"
	frontmatter_end="$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "${skill_file}")"
	if [[ ! "${frontmatter_end}" =~ ^[0-9]+$ ]] || ((frontmatter_end < 3)); then
		fail "skill frontmatter is not closed: ${id}"
	fi
	skill_name="$(awk '
		NR == 1 { next }
		$0 == "---" { exit }
		/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); print; exit }
	' "${skill_file}")"
	skill_description="$(awk '
		NR == 1 { next }
		$0 == "---" { exit }
		/^description:[[:space:]]*/ { sub(/^description:[[:space:]]*/, ""); print; exit }
	' "${skill_file}")"
	[[ "${skill_name}" == "${id}" ]] || fail "skill name ${skill_name:-<missing>} must match schedule id ${id}"
	[[ -n "${skill_description}" ]] || fail "skill description is missing: ${id}"
	printf '%s\n' "${id}" >>"${ids_file}"
done < <(fd -HI -t f -d 2 '^schedule\.json$' "${ROOT}" | sort)

[[ "${manifest_count}" -gt 0 ]] || fail "no schedule definitions found"

duplicate_id="$(sort "${ids_file}" | uniq -d | head -n 1)"
[[ -z "${duplicate_id}" ]] || fail "duplicate schedule id: ${duplicate_id}"

echo "PASS: ${manifest_count} shared schedule definition(s)"
