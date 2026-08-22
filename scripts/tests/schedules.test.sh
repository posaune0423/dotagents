#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[[ -f "${ROOT}/schedules/README.md" ]] || fail "missing schedules/README.md"
[[ -f "${ROOT}/schedules/schema.json" ]] || fail "missing schedules/schema.json"
[[ -f "${ROOT}/schedules/mac-storage-audit/schedule.json" ]] || fail "missing mac-storage-audit manifest"
[[ -s "${ROOT}/schedules/mac-storage-audit/SKILL.md" ]] || fail "missing mac-storage-audit skill"
[[ ! -e "${ROOT}/schedules/mac-storage-audit/PROMPT.md" ]] || fail "legacy mac-storage-audit PROMPT.md remains"
[[ -f "${ROOT}/schedules/safe-dev-storage-cleanup/schedule.json" ]] ||
	fail "missing safe-dev-storage-cleanup manifest"
[[ -s "${ROOT}/schedules/safe-dev-storage-cleanup/SKILL.md" ]] ||
	fail "missing safe-dev-storage-cleanup skill"
[[ ! -e "${ROOT}/schedules/safe-dev-storage-cleanup/PROMPT.md" ]] ||
	fail "legacy safe-dev-storage-cleanup PROMPT.md remains"
rg -Fq 'fd -HI --one-file-system' "${ROOT}/schedules/mac-storage-audit/SKILL.md" ||
	fail "storage audit must not cross onto mounted external filesystems"
rg -Fq 'pkgs.fd' "${ROOT}/flake.nix" || fail "Nix toolchain must provide fd for schedule validation"
rg -Fq 'pkgs.jq' "${ROOT}/flake.nix" || fail "Nix toolchain must provide jq for schedule validation"
rg -Fq 'pkgs.ripgrep' "${ROOT}/flake.nix" || fail "Nix toolchain must provide rg for schedule tests"
rg -Fq 'run: nix develop -c just check' "${ROOT}/.github/workflows/bun.yml" ||
	fail "CI must run the destructive-boundary schedule tests through just check"

bash "${ROOT}/scripts/validate-schedules.sh" --root "${ROOT}/schedules"

TEST_ROOT="$(mktemp -d)"
cleanup() {
	rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

mkdir -p -- "${TEST_ROOT}/wrong-folder"
cp -- "${ROOT}/schedules/schema.json" "${TEST_ROOT}/schema.json"
cp -- "${ROOT}/schedules/mac-storage-audit/schedule.json" "${TEST_ROOT}/wrong-folder/schedule.json"
cp -- "${ROOT}/schedules/mac-storage-audit/SKILL.md" "${TEST_ROOT}/wrong-folder/SKILL.md"

if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject a directory whose name differs from the schedule id"
fi

rm -rf -- "${TEST_ROOT}/wrong-folder"
mkdir -p -- "${TEST_ROOT}/mac-storage-audit"
jq '.unexpected = true' \
	"${ROOT}/schedules/mac-storage-audit/schedule.json" >"${TEST_ROOT}/mac-storage-audit/schedule.json"
cp -- "${ROOT}/schedules/mac-storage-audit/SKILL.md" "${TEST_ROOT}/mac-storage-audit/SKILL.md"

if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject manifest properties outside the shared schema"
fi

jq 'del(.unexpected) | .schedule.rrule = "FREQ="' \
	"${TEST_ROOT}/mac-storage-audit/schedule.json" >"${TEST_ROOT}/invalid.json"
mv -- "${TEST_ROOT}/invalid.json" "${TEST_ROOT}/mac-storage-audit/schedule.json"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject an incomplete RRULE"
fi

jq '.schedule.rrule = "FREQ=DAILY;BYHOUR=99;BYMINUTE=75"' \
	"${ROOT}/schedules/mac-storage-audit/schedule.json" >"${TEST_ROOT}/mac-storage-audit/schedule.json"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject out-of-range RRULE values"
fi

jq '.schedule.rrule = "FREQ=DAILY;UNKNOWN=1"' \
	"${ROOT}/schedules/mac-storage-audit/schedule.json" >"${TEST_ROOT}/mac-storage-audit/schedule.json"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject unsupported RRULE properties"
fi

jq '.schedule.rrule = "FREQ=DAILY" | .schedule.timezone = "not/a-real-zone"' \
	"${TEST_ROOT}/mac-storage-audit/schedule.json" >"${TEST_ROOT}/invalid.json"
mv -- "${TEST_ROOT}/invalid.json" "${TEST_ROOT}/mac-storage-audit/schedule.json"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject an unknown timezone"
fi

jq '.schedule.timezone = "Etc/../../../../../../../etc/passwd"' \
	"${ROOT}/schedules/mac-storage-audit/schedule.json" >"${TEST_ROOT}/mac-storage-audit/schedule.json"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject timezone path traversal"
fi

cp -- "${ROOT}/schedules/mac-storage-audit/schedule.json" "${TEST_ROOT}/mac-storage-audit/schedule.json"
sed 's/^name: mac-storage-audit$/name: wrong-schedule-name/' \
	"${ROOT}/schedules/mac-storage-audit/SKILL.md" >"${TEST_ROOT}/mac-storage-audit/SKILL.md"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject a SKILL.md name that differs from the schedule id"
fi

rm -f -- "${TEST_ROOT}/mac-storage-audit/SKILL.md"
ln -s -- "${ROOT}/schedules/mac-storage-audit/SKILL.md" "${TEST_ROOT}/mac-storage-audit/SKILL.md"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject a symlinked skill"
fi

rm -f -- "${TEST_ROOT}/mac-storage-audit/SKILL.md"
cp -- "${ROOT}/schedules/mac-storage-audit/SKILL.md" "${TEST_ROOT}/mac-storage-audit/SKILL.md"
mkdir -p -- "${TEST_ROOT}/linked-task"
ln -s -- "${ROOT}/schedules/mac-storage-audit/schedule.json" "${TEST_ROOT}/linked-task/schedule.json"
cp -- "${ROOT}/schedules/mac-storage-audit/SKILL.md" "${TEST_ROOT}/linked-task/SKILL.md"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject a symlinked manifest"
fi

rm -rf -- "${TEST_ROOT}/linked-task"
jq '.targets = ["claude-code-cloud"]' \
	"${ROOT}/schedules/mac-storage-audit/schedule.json" >"${TEST_ROOT}/mac-storage-audit/schedule.json"
if bash "${ROOT}/scripts/validate-schedules.sh" --root "${TEST_ROOT}" >/dev/null 2>&1; then
	fail "validator must reject a cloud target for a local-only schedule"
fi

echo "PASS: shared schedule definitions"
