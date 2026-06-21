#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="runner"
ECR_REGION="ap-northeast-1"
REPLICA_REGION="ap-northeast-3"
ECS_REGIONS=(ap-northeast-1 ap-northeast-3)

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
            return
        fi
        sleep 5
    done
    echo "Error: ${SERVICE}@${digest} was not replicated to ${REPLICA_REGION}" >&2
    exit 1
}

deploy_to_region() {
    local env_name="${1:?}"
    local region="${2:?}"
    local aws_account_id="${3:?}"
    local digest="${4:?}"
    local image="${aws_account_id}.dkr.ecr.${region}.amazonaws.com/bunshin/${SERVICE}@${digest}"
    local task_def_input
    local new_task_def_arn

    task_def_input="$(aws --profile "${env_name}" --region "${region}" ecs describe-task-definition \
        --task-definition "bunshin-${SERVICE}" \
        --query 'taskDefinition' \
        | jq --arg image "${image}" --arg service "${SERVICE}" '
            .containerDefinitions |= map(if .name == $service then .image = $image else . end)
            | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
        ')"
    new_task_def_arn="$(aws --profile "${env_name}" --region "${region}" ecs register-task-definition \
        --cli-input-json "${task_def_input}" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)"
    aws --profile "${env_name}" --region "${region}" ecs update-service \
        --cluster bunshin \
        --service "bunshin-${SERVICE}" \
        --task-definition "${new_task_def_arn}" \
        >/dev/null
    aws --profile "${env_name}" --region "${region}" ecs wait services-stable \
        --cluster bunshin \
        --services "bunshin-${SERVICE}"
}

main() {
    local env_name="${1:?Usage: scripts/deploy/runner.sh <env> <aws_account_id>}"
    local aws_account_id="${2:?Usage: scripts/deploy/runner.sh <env> <aws_account_id>}"
    local image_tag
    local short_image_tag
    local image
    local registry="${aws_account_id}.dkr.ecr.${ECR_REGION}.amazonaws.com"
    local digest
    local region
    local tags=()
    local pids=()
    local pid
    local exit_code=0

    image_tag="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
    short_image_tag="$(git -C "${ROOT_DIR}" rev-parse --short=7 HEAD)"
    tags=(
        "${registry}/bunshin/${SERVICE}:${image_tag}"
        "${registry}/bunshin/${SERVICE}:${short_image_tag}"
        "${registry}/bunshin/${SERVICE}:latest"
    )

    echo "Deploying ${SERVICE} to ${env_name}"
    docker build \
        -t "${tags[0]}" \
        -t "${tags[1]}" \
        -t "${tags[2]}" \
        "${ROOT_DIR}/${SERVICE}"

    for image in "${tags[@]}"; do
        docker push "${image}"
    done
    digest="$(aws --profile "${env_name}" --region "${ECR_REGION}" ecr describe-images \
        --repository-name "bunshin/${SERVICE}" \
        --image-ids "imageTag=${image_tag}" \
        --query 'imageDetails[0].imageDigest' \
        --output text)"
    wait_for_replication "${env_name}" "${digest}"

    for region in "${ECS_REGIONS[@]}"; do
        deploy_to_region "${env_name}" "${region}" "${aws_account_id}" "${digest}" &
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
