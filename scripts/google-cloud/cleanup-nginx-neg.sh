#!/usr/bin/env bash
set -euo pipefail

REGIONS=(asia-northeast1 asia-northeast2)

PROJECT="${GOOGLE_CLOUD_PROJECT:-}"
if [ -z "${PROJECT}" ]; then
    PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
fi
if [ -z "${PROJECT}" ]; then
    echo "GOOGLE_CLOUD_PROJECT env or gcloud config project must be set" >&2
    exit 1
fi

cleanup_region() {
    local region="$1"
    local neg_name="bunshin-nginx-${region}"
    local zones=("${region}-a" "${region}-b" "${region}-c")

    for zone in "${zones[@]}"; do
        if gcloud compute network-endpoint-groups describe "${neg_name}" \
            --zone="${zone}" --project="${PROJECT}" >/dev/null 2>&1; then
            gcloud compute network-endpoint-groups delete "${neg_name}" \
                --zone="${zone}" --project="${PROJECT}" -q
            printf '[%s] deleted %s\n' "${region}" "${zone}"
        else
            printf '[%s] already deleted %s\n' "${region}" "${zone}"
        fi
    done
}

pids=()
for region in "${REGIONS[@]}"; do
    cleanup_region "${region}" &
    pids+=("$!")
done

status=0
for pid in "${pids[@]}"; do
    wait "${pid}" || status=$?
done
exit "${status}"
