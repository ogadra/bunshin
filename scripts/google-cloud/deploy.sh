#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICES=(broker nginx runner)
REGIONS=(asia-northeast1 asia-northeast2)
REPOSITORY="bunshin"
NAMESPACE="bunshin"
MEMBERSHIPS=(bunshin-asne1 bunshin-asne2)

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

build_and_push() {
    local service="${1:?}"
    local project="${2:?}"
    local image_tag="${3:?}"
    local tags=()
    local region

    for region in "${REGIONS[@]}"; do
        tags+=(--tag "${region}-docker.pkg.dev/${project}/${REPOSITORY}/${service}:${image_tag}")
    done

    echo "[${service}] building linux/amd64,linux/arm64 and pushing to ${#REGIONS[@]} region(s)"
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        "${tags[@]}" \
        --push \
        "${ROOT_DIR}/${service}"
}

apply_terraform() {
    local env_name="${1:?}"
    local image_tag="${2:?}"

    echo "Applying terraform with image_tag=${image_tag}"
    terraform -chdir="${ROOT_DIR}/terraform/google-cloud" apply \
        -var-file="environments/${env_name}.tfvars" \
        -var "image_tag=${image_tag}" \
        -auto-approve
}

wait_rollout() {
    local project="${1:?}"
    local membership="${2:?}"
    local service="${3:?}"
    local context="connectgateway_${project}_global_${membership}"

    echo "[${membership}] waiting for ${service} rollout"
    kubectl --context="${context}" \
        -n "${NAMESPACE}" \
        rollout status "deployment/${service}" \
        --timeout=5m
}

main() {
    local env_name="${1:?Usage: scripts/google-cloud/deploy.sh <env> [service]}"
    local target_service="${2:-}"
    local project
    local image_tag
    local service
    local membership
    local targets

    if [[ -n "${target_service}" ]] && ! contains_service "${target_service}"; then
        die "service must be one of: ${SERVICES[*]}"
    fi

    project="$(gcloud config get-value project 2>/dev/null)"
    [[ -n "${project}" && "${project}" != "(unset)" ]] \
        || die "gcloud project is not set (run 'gcloud config set project <id>')"

    image_tag="$(git -C "${ROOT_DIR}" rev-parse HEAD)"

    echo "Deploying to google-cloud env=${env_name} project=${project} image_tag=${image_tag}"

    gcloud auth configure-docker \
        "asia-northeast1-docker.pkg.dev,asia-northeast2-docker.pkg.dev" \
        --quiet

    if [[ -n "${target_service}" ]]; then
        targets=("${target_service}")
    else
        targets=("${SERVICES[@]}")
    fi

    for service in "${targets[@]}"; do
        build_and_push "${service}" "${project}" "${image_tag}"
    done

    apply_terraform "${env_name}" "${image_tag}"

    for membership in "${MEMBERSHIPS[@]}"; do
        echo "[${membership}] fetching Connect Gateway credentials"
        gcloud container fleet memberships get-credentials "${membership}" \
            --project="${project}" >/dev/null
        for service in "${targets[@]}"; do
            wait_rollout "${project}" "${membership}" "${service}"
        done
    done
}

main "$@"
