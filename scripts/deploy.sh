#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=(broker nginx runner front)
REGIONS=(ap-northeast-1 ap-northeast-3)

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

tfvar_string() {
    local key="${1:?}"
    local tfvars_file="${2:?}"
    local value

    value="$(
        awk -v key="${key}" '
            $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
                sub(/^[^=]*=[[:space:]]*/, "", $0)
                sub(/[[:space:]]*#.*$/, "", $0)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
                if ($0 ~ /^".*"$/) {
                    sub(/^"/, "", $0)
                    sub(/"$/, "", $0)
                }
                print
                exit
            }
        ' "${tfvars_file}"
    )"

    if [[ -z "${value}" ]]; then
        die "${tfvars_file#${ROOT_DIR}/} must define ${key}"
    fi

    printf '%s\n' "${value}"
}

run_service() {
    local service="${1:?}"
    local env_name="${2:?}"
    local aws_account_id="${3:?}"
    local domain_name="${4:?}"

    "${ROOT_DIR}/scripts/deploy/${service}.sh" "${env_name}" "${aws_account_id}" "${domain_name}"
}

login_ecr() {
    local env_name="${1:?}"
    local aws_account_id="${2:?}"
    local region
    local registry

    for region in "${REGIONS[@]}"; do
        registry="${aws_account_id}.dkr.ecr.${region}.amazonaws.com"
        aws --profile "${env_name}" --region "${region}" ecr get-login-password \
            | docker login --username AWS --password-stdin "${registry}"
    done
}

main() {
    local env_name="${1:?Usage: scripts/deploy.sh <env> [service]}"
    local service="${2:-}"
    local tfvars_file="${ROOT_DIR}/terraform/environments/${env_name}.tfvars"
    local domain_name
    local aws_account_id
    local pid
    local pids=()
    local status=0

    if [[ -n "${service}" ]] && ! contains_service "${service}"; then
        die "service must be one of: ${SERVICES[*]}"
    fi

    if [[ ! -f "${tfvars_file}" ]]; then
        die "terraform/environments/${env_name}.tfvars does not exist"
    fi

    domain_name="$(tfvar_string domain_name "${tfvars_file}")"
    aws_account_id="$(aws --profile "${env_name}" sts get-caller-identity --query Account --output text)"

    if [[ -z "${aws_account_id}" || "${aws_account_id}" == "None" ]]; then
        die "failed to resolve AWS account id for profile ${env_name}"
    fi

    if [[ -n "${service}" ]]; then
        if uses_ecs "${service}"; then
            login_ecr "${env_name}" "${aws_account_id}"
        fi
        run_service "${service}" "${env_name}" "${aws_account_id}" "${domain_name}"
        return
    fi

    login_ecr "${env_name}" "${aws_account_id}"

    for service in "${SERVICES[@]}"; do
        run_service "${service}" "${env_name}" "${aws_account_id}" "${domain_name}" &
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
