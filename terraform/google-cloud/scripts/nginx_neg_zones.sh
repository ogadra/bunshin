#!/usr/bin/env bash
# terraform data "external" 用の helper。
# stdin から JSON 化されたクエリを受け、Service annotation
# cloud.google.com/neg-status に期待 NEG が現れるまで kubectl でポーリングし、
# その NEG が生成された zone を CSV 化して JSON で返す。
# Autopilot が Pod をどの zone に配置するかは capacity 依存で確定できないため、
# Terraform 側で zone 固定リストを持たず annotation を唯一の source of truth にする
set -euo pipefail

query="$(cat)"
project=$(jq -r '.project' <<<"${query}")
membership=$(jq -r '.membership' <<<"${query}")
namespace=$(jq -r '.namespace' <<<"${query}")
service=$(jq -r '.service' <<<"${query}")
neg_name=$(jq -r '.neg_name' <<<"${query}")

context="connectgateway_${project}_global_${membership}"

gcloud container fleet memberships get-credentials "${membership}" \
    --project="${project}" >/dev/null 2>&1

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

echo "nginx NEG ${neg_name} did not appear in ${context}/${namespace}/${service} neg-status within 300s" >&2
exit 1
