#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SERVICE="nginx"
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

wait_for_service_stable() {
    local env_name="${1:?}"
    local region="${2:?}"
    local attempt
    local state
    local primary_rollout
    local primary_running
    local primary_desired
    local active_count
    local summary
    local last_summary=""

    for attempt in {1..150}; do
        state="$(aws --profile "${env_name}" --region "${region}" ecs describe-services \
            --cluster bunshin --services "bunshin-${SERVICE}" \
            --query 'services[0].deployments' --output json)"
        primary_rollout="$(jq -r 'map(select(.status == "PRIMARY"))[0].rolloutState // "UNKNOWN"' <<<"${state}")"
        primary_running="$(jq -r 'map(select(.status == "PRIMARY"))[0].runningCount // 0' <<<"${state}")"
        primary_desired="$(jq -r 'map(select(.status == "PRIMARY"))[0].desiredCount // 0' <<<"${state}")"
        active_count="$(jq -r '[.[] | select(.status == "ACTIVE")] | length' <<<"${state}")"

        summary="${primary_running}/${primary_desired} running, rollout ${primary_rollout}, ${active_count} draining"
        if [[ "${summary}" != "${last_summary}" ]]; then
            echo "[${region}] ${SERVICE}: ${summary}"
            last_summary="${summary}"
        fi

        if [[ "${primary_rollout}" == "COMPLETED" && "${active_count}" -eq 0 \
              && "${primary_running}" -eq "${primary_desired}" ]]; then
            return
        fi
        if [[ "${primary_rollout}" == "FAILED" ]]; then
            echo "Error: [${region}] ${SERVICE} rollout failed" >&2
            exit 1
        fi
        sleep 10
    done
    echo "Error: [${region}] ${SERVICE} did not stabilize within timeout" >&2
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

    echo "[${region}] registering ${SERVICE} task definition"
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
    echo "[${region}] updating ${SERVICE} service to ${new_task_def_arn##*/}"
    aws --profile "${env_name}" --region "${region}" ecs update-service \
        --cluster bunshin \
        --service "bunshin-${SERVICE}" \
        --task-definition "${new_task_def_arn}" \
        >/dev/null
    wait_for_service_stable "${env_name}" "${region}"
    echo "[${region}] ${SERVICE} stable"
}

main() {
    local env_name="${1:?Usage: scripts/aws/deploy/nginx.sh <env> <aws_account_id>}"
    local aws_account_id="${2:?Usage: scripts/aws/deploy/nginx.sh <env> <aws_account_id>}"
    local image_tag
    local short_image_tag
    local registry="${aws_account_id}.dkr.ecr.${ECR_REGION}.amazonaws.com"
    local digest
    local region
    local pids=()
    local pid
    local exit_code=0

    image_tag="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
    short_image_tag="$(git -C "${ROOT_DIR}" rev-parse --short=7 HEAD)"

    echo "Deploying ${SERVICE} to ${env_name}"
    echo "[${SERVICE}] building image"
    docker buildx build \
        --platform linux/arm64 \
        --build-arg NGINX_RESOLVER=169.254.169.253 \
        --build-arg BROKER_HOST=broker.internal \
        -t "${registry}/bunshin/${SERVICE}:${image_tag}" \
        -t "${registry}/bunshin/${SERVICE}:${short_image_tag}" \
        -t "${registry}/bunshin/${SERVICE}:latest" \
        --push \
        "${ROOT_DIR}/${SERVICE}"
    digest="$(aws --profile "${env_name}" --region "${ECR_REGION}" ecr describe-images \
        --repository-name "bunshin/${SERVICE}" \
        --image-ids "imageTag=${image_tag}" \
        --query 'imageDetails[0].imageDigest' \
        --output text)"
    echo "[${SERVICE}] pushed digest ${digest}"
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
