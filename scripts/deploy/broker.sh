#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="broker"
ECR_REGION="ap-northeast-1"
REPLICA_REGION="ap-northeast-3"
ECS_REGIONS=(ap-northeast-1 ap-northeast-3)

wait_for_replication() {
    local env_name="${1:?}"
    local tag
    local attempt

    shift

    for tag in "$@"; do
        echo "Waiting for ${SERVICE}:${tag} replication to ${REPLICA_REGION}"
        for attempt in {1..60}; do
            if aws --profile "${env_name}" --region "${REPLICA_REGION}" ecr describe-images \
                --repository-name "bunshin/${SERVICE}" \
                --image-ids "imageTag=${tag}" \
                >/dev/null 2>&1; then
                break
            fi
            if [[ "${attempt}" -eq 60 ]]; then
                echo "Error: ${SERVICE}:${tag} was not replicated to ${REPLICA_REGION}" >&2
                exit 1
            fi
            sleep 5
        done
    done
}

main() {
    local env_name="${1:?Usage: scripts/deploy/broker.sh <env> <aws_account_id> <domain_name>}"
    local aws_account_id="${2:?Usage: scripts/deploy/broker.sh <env> <aws_account_id> <domain_name>}"
    local domain_name="${3:?Usage: scripts/deploy/broker.sh <env> <aws_account_id> <domain_name>}"
    local image_tag
    local short_image_tag
    local registry="${aws_account_id}.dkr.ecr.${ECR_REGION}.amazonaws.com"
    local region

    image_tag="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
    short_image_tag="$(git -C "${ROOT_DIR}" rev-parse --short=7 HEAD)"

    echo "Deploying ${SERVICE} to ${env_name} (${domain_name})"
    docker buildx build \
        --platform linux/arm64 \
        -t "${registry}/bunshin/${SERVICE}:${image_tag}" \
        -t "${registry}/bunshin/${SERVICE}:${short_image_tag}" \
        -t "${registry}/bunshin/${SERVICE}:latest" \
        --push \
        "${ROOT_DIR}/${SERVICE}"
    wait_for_replication "${env_name}" "${image_tag}" "${short_image_tag}" latest

    for region in "${ECS_REGIONS[@]}"; do
        aws --profile "${env_name}" --region "${region}" ecs update-service \
            --cluster bunshin \
            --service "bunshin-${SERVICE}" \
            --force-new-deployment \
            >/dev/null
        aws --profile "${env_name}" --region "${region}" ecs wait services-stable \
            --cluster bunshin \
            --services "bunshin-${SERVICE}"
    done
}

main "$@"
