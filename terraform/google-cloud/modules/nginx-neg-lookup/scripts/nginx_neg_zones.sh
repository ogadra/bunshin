#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
# shellcheck source=../../../../../scripts/google-cloud/lib/connect_gateway.sh
source "${repo_root}/scripts/google-cloud/lib/connect_gateway.sh"

query="$(cat)"
project=$(jq -r '.project' <<<"${query}")
membership=$(jq -r '.membership' <<<"${query}")
namespace=$(jq -r '.namespace' <<<"${query}")
service=$(jq -r '.service' <<<"${query}")
neg_name=$(jq -r '.neg_name' <<<"${query}")

emit_empty() {
    jq -n '{zones: ""}'
    exit 0
}

if ! connect_gateway_fetch_credentials "${project}" "${membership}" 2>/dev/null; then
    echo "nginx_neg_zones: fleet membership ${membership} unreachable; emitting empty zone list" >&2
    emit_empty
fi

context="$(connect_gateway_context "${project}" "${membership}")"

for _ in $(seq 1 60); do
    annotation=$(kubectl --context="${context}" -n "${namespace}" get svc "${service}" \
        -o jsonpath='{.metadata.annotations.cloud\.google\.com/neg-status}' 2>/dev/null || true)
    if [[ -n "${annotation}" ]]; then
        registered=$(jq -r --arg neg "${neg_name}" \
            '.network_endpoint_groups | to_entries[] | select(.value == $neg) | .value' \
            <<<"${annotation}")
        if [[ -n "${registered}" ]]; then
            zones=$(jq -r '.zones | join(",")' <<<"${annotation}")
            if [[ -n "${zones}" ]]; then
                jq -n --arg zones "${zones}" '{zones: $zones}'
                exit 0
            fi
        fi
    fi
    sleep 5
done

echo "nginx_neg_zones: ${neg_name} not found in ${context}/${namespace}/${service} neg-status within 300s; emitting empty zone list" >&2
emit_empty
