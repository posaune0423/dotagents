#!/usr/bin/env bash
# Provider adapter: Groq. Free tier: 30 req/min, ~1,000 req/day, 8K tokens/min.
# The roster changes; `probe` verifies the default against the live model list.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HERE}/../lib/common.sh"

PROVIDER=groq
PIGGYBACK_BASE_URL="${PIGGYBACK_GROQ_BASE_URL:-https://api.groq.com/openai/v1}"
PIGGYBACK_KEY_VAR="GROQ_API_KEY"
PIGGYBACK_DEFAULT_MODEL="${PIGGYBACK_GROQ_MODEL:-openai/gpt-oss-20b}"

# shellcheck source=../lib/openai_provider.sh
source "${HERE}/../lib/openai_provider.sh"
piggyback_openai_provider_main "$@"
