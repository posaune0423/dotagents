#!/usr/bin/env bash
# Provider adapter: Mistral La Plateforme free Experiment tier. Rate limits are not published and have been reported as low as 1 req/min, so this sits near the end of the chain.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HERE}/../lib/common.sh"

PROVIDER=mistral
PIGGYBACK_BASE_URL="${PIGGYBACK_MISTRAL_BASE_URL:-https://api.mistral.ai/v1}"
PIGGYBACK_KEY_VAR="MISTRAL_API_KEY"
PIGGYBACK_DEFAULT_MODEL="${PIGGYBACK_MISTRAL_MODEL:-mistral-small-latest}"

# shellcheck source=../lib/openai_provider.sh
source "${HERE}/../lib/openai_provider.sh"
piggyback_openai_provider_main "$@"
