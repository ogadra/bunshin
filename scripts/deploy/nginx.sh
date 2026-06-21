#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="nginx"
PLATFORM="linux/arm64"
REGIONS=(ap-northeast-1 ap-northeast-3)

main() {
    local env_name="${1:?Usage: scripts/deploy/nginx.sh <env> <aws_account_id> <domain_name>}"
    local aws_account_id="${2:?Usage: scripts/deploy/nginx.sh <env> <aws_account_id> <domain_name>}"
    local domain_name="${3:?Usage: scripts/deploy/nginx.sh <env> <aws_account_id> <domain_name>}"
    local image_tag
    local short_image_tag
    local registry
    local region
    local tags=()

    image_tag="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
    short_image_tag="$(git -C "${ROOT_DIR}" rev-parse --short=7 HEAD)"

    for region in "${REGIONS[@]}"; do
        registry="${aws_account_id}.dkr.ecr.${region}.amazonaws.com"
        tags+=(
            -t "${registry}/bunshin/${SERVICE}:${image_tag}"
            -t "${registry}/bunshin/${SERVICE}:${short_image_tag}"
            -t "${registry}/bunshin/${SERVICE}:latest"
        )
    done

    echo "Deploying ${SERVICE} to ${env_name} (${domain_name})"
    docker buildx build \
        --platform "${PLATFORM}" \
        --build-arg NGINX_RESOLVER=169.254.169.253 \
        --build-arg BROKER_HOST=broker.internal \
        "${tags[@]}" \
        --push \
        "${ROOT_DIR}/${SERVICE}"

    for region in "${REGIONS[@]}"; do
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
