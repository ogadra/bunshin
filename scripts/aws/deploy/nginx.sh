#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVICE="nginx"
PLATFORM="linux/arm64"
ECR_REGION="ap-northeast-1"
REPLICA_REGION="ap-northeast-3"
REGION_DIRS=(apne1 apne3)

wait_for_replication() {
    local env_name="${1:?}"
    local digest="${2:?}"
    local attempt

    echo "Waiting for ${SERVICE}@${digest} replication to ${REPLICA_REGION}"
    for attempt in {1..60}; do
        if aws --profile "${env_name}" --region "${REPLICA_REGION}" ecr describe-images \
            --repository-name "bunshin/${SERVICE}" \
            --image-ids "imageDigest=${digest}" \
            >/dev/null 2>&1; then
            echo "[${REPLICA_REGION}] ${SERVICE} digest visible after ${attempt} attempt(s)"
            return
        fi
        if (( attempt % 6 == 0 )); then
            echo "[${REPLICA_REGION}] ${SERVICE} still replicating (attempt ${attempt}/60)"
        fi
        sleep 5
    done
    echo "Error: ${SERVICE}@${digest} was not replicated to ${REPLICA_REGION}" >&2
    exit 1
}

deploy_to_region() {
    local region_dir="${1:?}"

    # shellcheck disable=SC1090,SC1091
    source "${ROOT_DIR}/deploy/aws/${region_dir}/region.env"

    echo "[${region_dir}] deploying ${SERVICE} via ecspresso"
    ecspresso deploy \
        --config "${ROOT_DIR}/deploy/aws/${region_dir}/${SERVICE}/ecspresso.yml" \
        --rollback-events=DEPLOYMENT_FAILURE
    echo "[${region_dir}] ${SERVICE} stable"
}

main() {
    local env_name="${1:?Usage: scripts/aws/deploy/nginx.sh <env> <aws_account_id>}"
    local aws_account_id="${2:?Usage: scripts/aws/deploy/nginx.sh <env> <aws_account_id>}"
    local image_tag
    local short_image_tag
    local registry="${aws_account_id}.dkr.ecr.${ECR_REGION}.amazonaws.com"
    local digest
    local region_dir
    local pids=()
    local pid
    local exit_code=0

    : "${TF_BACKEND_BUCKET:?TF_BACKEND_BUCKET must be set (tfstate bucket for ecspresso plugin)}"

    image_tag="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
    short_image_tag="$(git -C "${ROOT_DIR}" rev-parse --short=7 HEAD)"

    echo "Deploying ${SERVICE} to ${env_name}"
    echo "[${SERVICE}] building image"
    docker buildx build \
        --platform "${PLATFORM}" \
        -t "${registry}/bunshin/${SERVICE}:${image_tag}" \
        -t "${registry}/bunshin/${SERVICE}:${short_image_tag}" \
        --push \
        "${ROOT_DIR}/${SERVICE}"
    digest="$(aws --profile "${env_name}" --region "${ECR_REGION}" ecr describe-images \
        --repository-name "bunshin/${SERVICE}" \
        --image-ids "imageTag=${image_tag}" \
        --query 'imageDetails[0].imageDigest' \
        --output text)"
    echo "[${SERVICE}] pushed digest ${digest}"
    wait_for_replication "${env_name}" "${digest}"

    export AWS_PROFILE="${env_name}"
    export ENV="${env_name}"
    export IMAGE_TAG="${image_tag}"

    for region_dir in "${REGION_DIRS[@]}"; do
        deploy_to_region "${region_dir}" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        if ! wait "${pid}"; then
            exit_code=1
        fi
    done
    return "${exit_code}"
}

main "$@"
