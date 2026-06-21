#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=(broker nginx runner front)
ECR_REGION="ap-northeast-1"

die() {
    echo "Error: $*" >&2
    exit 1
}

contains_service() {
    local candidate="${1:?}"
    local service

    for service in "${SERVICES[@]}"; do
        if [[ "${service}" == "${candidate}" ]]; then
            return 0
        fi
    done

    return 1
}

uses_ecs() {
    local service="${1:?}"

    [[ "${service}" == "broker" || "${service}" == "nginx" || "${service}" == "runner" ]]
}

run_service() {
    local service="${1:?}"
    local env_name="${2:?}"
    local aws_account_id="${3:?}"

    "${ROOT_DIR}/scripts/deploy/${service}.sh" "${env_name}" "${aws_account_id}"
}

login_ecr() {
    local env_name="${1:?}"
    local aws_account_id="${2:?}"
    local registry="${aws_account_id}.dkr.ecr.${ECR_REGION}.amazonaws.com"

    aws --profile "${env_name}" --region "${ECR_REGION}" ecr get-login-password \
        | docker login --username AWS --password-stdin "${registry}"
}

main() {
    local env_name="${1:?Usage: scripts/deploy.sh <env> [service]}"
    local service="${2:-}"
    local aws_account_id
    local pid
    local pids=()
    local status=0

    if [[ -n "${service}" ]] && ! contains_service "${service}"; then
        die "service must be one of: ${SERVICES[*]}"
    fi

    aws_account_id="$(aws --profile "${env_name}" sts get-caller-identity --query Account --output text)"

    if [[ -z "${aws_account_id}" || "${aws_account_id}" == "None" ]]; then
        die "failed to resolve AWS account id for profile ${env_name}"
    fi

    if [[ -n "${service}" ]]; then
        if uses_ecs "${service}"; then
            login_ecr "${env_name}" "${aws_account_id}"
        fi
        run_service "${service}" "${env_name}" "${aws_account_id}"
        return
    fi

    login_ecr "${env_name}" "${aws_account_id}"

    for service in "${SERVICES[@]}"; do
        run_service "${service}" "${env_name}" "${aws_account_id}" &
        pids+=("$!")
    done

    for pid in "${pids[@]}"; do
        if ! wait "${pid}"; then
            status=1
        fi
    done

    return "${status}"
}

main "$@"
