#!/usr/bin/env bash
# Integration tests for skills/create-pr/scripts/pr-template.sh: locating and
# printing the repository's pull request template.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/skills/create-pr/scripts/pr-template.sh"

pass=0
fail=0

fail_msg() {
	echo "FAIL: $*" >&2
	fail=$((fail + 1))
}

ok() {
	pass=$((pass + 1))
}

# Resolve symlinks (/var -> /private/var on macOS) so paths compare equal to
# what `git rev-parse --show-toplevel` reports.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${TMP}"' EXIT

# Fresh git repo per case so template locations never bleed between cases.
# mktemp keeps names unique even on case-insensitive filesystems.
new_repo() {
	local dir
	dir="$(mktemp -d "${TMP}/$1.XXXXXX")"
	git -C "${dir}" init -q
	printf '%s\n' "${dir}"
}

[[ -x "${SCRIPT}" ]] || {
	echo "FAIL: script is missing or not executable: ${SCRIPT}" >&2
	exit 1
}

# --- no template ------------------------------------------------------------
repo="$(new_repo none)"
if out="$(cd "${repo}" && bash "${SCRIPT}" 2>/dev/null)"; then
	fail_msg "expected non-zero exit when no template exists"
elif [[ -n "${out}" ]]; then
	fail_msg "expected empty stdout when no template exists (got: ${out})"
else
	ok
fi

# --- each single-file location GitHub recognizes ------------------------------
for rel in \
	".github/pull_request_template.md" \
	".github/PULL_REQUEST_TEMPLATE.md" \
	"PULL_REQUEST_TEMPLATE.md" \
	"docs/pull_request_template.md"; do
	repo="$(new_repo "single-$(echo "${rel}" | tr '/.' '__')")"
	mkdir -p "${repo}/$(dirname "${rel}")"
	printf '## Summary\n\n<!-- why -->\n' >"${repo}/${rel}"
	out="$(cd "${repo}" && bash "${SCRIPT}")" || {
		fail_msg "expected success for ${rel}"
		continue
	}
	if [[ "${out}" != $'## Summary\n\n<!-- why -->' ]]; then
		fail_msg "unexpected content for ${rel}: ${out}"
		continue
	fi
	path_out="$(cd "${repo}" && bash "${SCRIPT}" --path)"
	if [[ "${path_out}" != "${repo}/${rel}" ]]; then
		fail_msg "--path should print the absolute template path for ${rel} (got: ${path_out})"
		continue
	fi
	ok
done

# --- runs from a subdirectory of the repo -------------------------------------
repo="$(new_repo subdir)"
mkdir -p "${repo}/.github" "${repo}/src/deep"
printf 'tpl\n' >"${repo}/.github/pull_request_template.md"
out="$(cd "${repo}/src/deep" && bash "${SCRIPT}")" || out="<exit $?>"
if [[ "${out}" != "tpl" ]]; then
	fail_msg "expected template found from a subdirectory (got: ${out})"
else
	ok
fi

# --- multiple templates in .github/PULL_REQUEST_TEMPLATE/ ---------------------
repo="$(new_repo multi)"
mkdir -p "${repo}/.github/PULL_REQUEST_TEMPLATE"
printf 'feature body\n' >"${repo}/.github/PULL_REQUEST_TEMPLATE/feature.md"
printf 'bugfix body\n' >"${repo}/.github/PULL_REQUEST_TEMPLATE/bugfix.md"

# Without --name the script must not guess: exit 2 and list the candidates.
set +e
err="$(cd "${repo}" && bash "${SCRIPT}" 2>&1 >/dev/null)"
code=$?
set -e
if [[ ${code} -ne 2 ]]; then
	fail_msg "expected exit 2 with multiple templates (got ${code})"
elif [[ "${err}" != *"bugfix.md"* || "${err}" != *"feature.md"* ]]; then
	fail_msg "expected candidate list on stderr (got: ${err})"
else
	ok
fi

out="$(cd "${repo}" && bash "${SCRIPT}" --name feature.md)" || out="<exit $?>"
if [[ "${out}" != "feature body" ]]; then
	fail_msg "--name should select one template from the directory (got: ${out})"
else
	ok
fi

# --name is a basename only: traversal and non-Markdown names are rejected.
printf 'secret\n' >"${repo}/.github/secret.txt"
for bad in "../secret.txt" "../../PULL_REQUEST_TEMPLATE/feature.md" "feature.txt" "." ".."; do
	set +e
	out="$(cd "${repo}" && bash "${SCRIPT}" --name "${bad}" 2>/dev/null)"
	code=$?
	set -e
	if [[ ${code} -ne 1 || -n "${out}" ]]; then
		fail_msg "--name ${bad} must be rejected with exit 1 (exit ${code}, out: ${out})"
	else
		ok
	fi
done

# A single file inside the directory needs no --name.
repo="$(new_repo multi-one)"
mkdir -p "${repo}/.github/PULL_REQUEST_TEMPLATE"
printf 'only body\n' >"${repo}/.github/PULL_REQUEST_TEMPLATE/only.md"
out="$(cd "${repo}" && bash "${SCRIPT}")" || out="<exit $?>"
if [[ "${out}" != "only body" ]]; then
	fail_msg "single file in template directory should print without --name (got: ${out})"
else
	ok
fi

# --- .github file wins over root and docs when several exist -------------------
repo="$(new_repo precedence)"
mkdir -p "${repo}/.github" "${repo}/docs"
printf 'github\n' >"${repo}/.github/pull_request_template.md"
printf 'root\n' >"${repo}/PULL_REQUEST_TEMPLATE.md"
printf 'docs\n' >"${repo}/docs/pull_request_template.md"
out="$(cd "${repo}" && bash "${SCRIPT}")" || out="<exit $?>"
if [[ "${out}" != "github" ]]; then
	fail_msg "expected .github template to take precedence (got: ${out})"
else
	ok
fi

echo "pr-template tests: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
