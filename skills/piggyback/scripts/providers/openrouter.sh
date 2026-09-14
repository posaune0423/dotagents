#!/usr/bin/env bash
# Provider adapter: OpenRouter free models. 20 req/min, 50 req/day (1,000/day after a one-time $10 top-up). The :free roster shifts monthly -- override with PIGGYBACK_OPENROUTER_MODEL.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HERE}/../lib/common.sh"

PROVIDER=openrouter
PIGGYBACK_BASE_URL="${PIGGYBACK_OPENROUTER_BASE_URL:-https://openrouter.ai/api/v1}"
PIGGYBACK_KEY_VAR="OPENROUTER_API_KEY"
PIGGYBACK_DEFAULT_MODEL="${PIGGYBACK_OPENROUTER_MODEL:-nvidia/nemotron-3.5-lightning:free}"

# shellcheck source=../lib/openai_provider.sh
source "${HERE}/../lib/openai_provider.sh"
piggyback_openai_provider_main "$@"
