#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICES=(broker nginx runner)
REGIONS=(asia-northeast1 asia-northeast2)
REPOSITORY="bunshin"
NAMESPACE="bunshin"
MEMBERSHIPS=(bunshin-asne1 bunshin-asne2)
MODULES=(asne1 asne2)

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

resolve_target_services() {
    local svc

    if [[ $# -eq 0 ]]; then
        printf '%s\n' "${SERVICES[@]}"
        return
    fi

    for svc in "$@"; do
        contains_service "${svc}" || die "service must be one of: ${SERVICES[*]} (got '${svc}')"
        echo "${svc}"
    done
}

resolve_project() {
    local project
    project="$(gcloud config get-value project 2>/dev/null)"
    [[ -n "${project}" && "${project}" != "(unset)" ]] \
        || die "gcloud project is not set (run 'gcloud config set project <id>')"
    echo "${project}"
}

configure_docker_auth() {
    gcloud auth configure-docker \
        "asia-northeast1-docker.pkg.dev,asia-northeast2-docker.pkg.dev" \
        --quiet
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

    echo "[${service}] building linux/amd64 and pushing to ${#REGIONS[@]} region(s)"
    docker buildx build \
        --platform linux/amd64 \
        "${tags[@]}" \
        --push \
        "${ROOT_DIR}/${service}"
}

build_and_push_all() {
    local project="${1:?}"
    local image_tag="${2:?}"
    shift 2
    local service

    for service in "$@"; do
        build_and_push "${service}" "${project}" "${image_tag}"
    done
}

apply_image_tag() {
    local env_name="${1:?}"
    local image_tag="${2:?}"
    shift 2
    local targets=()
    local module
    local service

    # `just deploy` が infra全体の drift を巻き込まないよう、image_tag が刺さる Deployment だけを target
    for module in "${MODULES[@]}"; do
        for service in "$@"; do
            targets+=(-target "module.${module}.kubernetes_deployment_v1.${service}")
        done
    done

    echo "Applying image_tag=${image_tag} to ${#targets[@]} Deployment target(s)"
    terraform -chdir="${ROOT_DIR}/terraform/google-cloud" apply \
        -var-file="environments/${env_name}.tfvars" \
        -var "image_tag=${image_tag}" \
        "${targets[@]}" \
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

wait_rollouts_all() {
    local project="${1:?}"
    shift
    local membership
    local service

    for membership in "${MEMBERSHIPS[@]}"; do
        echo "[${membership}] fetching Connect Gateway credentials"
        gcloud container fleet memberships get-credentials "${membership}" \
            --project="${project}" >/dev/null
        for service in "$@"; do
            wait_rollout "${project}" "${membership}" "${service}"
        done
    done
}

main() {
    local env_name="${1:?Usage: scripts/google-cloud/deploy.sh <env> [service...]}"
    shift
    local project
    local image_tag
    local -a targets
    local resolved_targets

    # `mapfile < <(...)` は process substitution 内の `die` を握り潰す。command substitution で
    # exit code を親に伝えないと、不正 service でも targets が空のまま infra 全体を apply してしまう
    resolved_targets="$(resolve_target_services "$@")"
    mapfile -t targets <<<"${resolved_targets}"
    project="$(resolve_project)"
    image_tag="$(git -C "${ROOT_DIR}" rev-parse HEAD)"

    echo "Deploying to google-cloud env=${env_name} project=${project} image_tag=${image_tag}"

    configure_docker_auth
    build_and_push_all "${project}" "${image_tag}" "${targets[@]}"
    apply_image_tag "${env_name}" "${image_tag}" "${targets[@]}"
    wait_rollouts_all "${project}" "${targets[@]}"
}

main "$@"
