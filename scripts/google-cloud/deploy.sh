#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICES=(broker nginx runner)
REGIONS=(asia-northeast1 asia-northeast2)
REGION_DIRS=(asne1 asne2)
REPOSITORY="bunshin"
NAMESPACE="bunshin"
MEMBERSHIPS=(bunshin-asne1 bunshin-asne2)
MANIFESTS_DIR="${ROOT_DIR}/deploy/google-cloud"

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

resolve_project() {
    local project
    project="$(gcloud config get-value project 2>/dev/null)"
    [[ -n "${project}" && "${project}" != "(unset)" ]] \
        || die "gcloud project is not set (run 'gcloud config set project <id>')"
    echo "${project}"
}

resolve_deployer_email() {
    local email
    email="$(gcloud config get-value account 2>/dev/null)"
    [[ -n "${email}" && "${email}" != "(unset)" ]] \
        || die "gcloud account is not set (run 'gcloud auth login')"
    echo "${email}"
}

read_tfstate_output() {
    local key="${1:?}"
    terraform -chdir="${ROOT_DIR}/terraform/google-cloud" output -raw "${key}"
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

apply_manifests() {
    local context="${1:?}"
    local defined_envs='$BROKER_GSA_EMAIL,$BROKER_KSA_NAME,$BROKER_REPLICAS,$BUNSHIN_STACKS,$DEPLOYER_EMAIL,$FIRESTORE_DATABASE,$GOOGLE_CLOUD_PROJECT,$IMAGE_TAG,$INTERNAL_DOMAIN,$INTERNAL_LB_NAME,$NGINX_NEG_NAME,$NGINX_REPLICAS,$NGINX_RESOLVER,$REGION,$REPOSITORY,$RUNNER_REPLICAS'
    local f

    kubectl --context="${context}" apply -f "${MANIFESTS_DIR}/base/namespace.yaml"

    for f in "${MANIFESTS_DIR}/base/"*.yaml; do
        [[ "${f}" == */namespace.yaml ]] && continue
        envsubst "${defined_envs}" < "${f}" | kubectl --context="${context}" apply -f -
    done
}

wait_rollout() {
    local context="${1:?}"
    local service="${2:?}"

    echo "[${context##*_}] waiting for ${service} rollout"
    kubectl --context="${context}" \
        -n "${NAMESPACE}" \
        rollout status "deployment/${service}" \
        --timeout=5m
}

main() {
    local env_name="${1:?Usage: scripts/google-cloud/deploy.sh <env> [service...]}"
    shift
    local project
    local image_tag
    local deployer_email
    local domain_name
    local broker_gsa_email
    local -a target_services=()
    local service
    local i
    local region_dir
    local membership
    local context
    local nginx_resolver

    if [[ $# -eq 0 ]]; then
        target_services=("${SERVICES[@]}")
    else
        for service in "$@"; do
            contains_service "${service}" || die "service must be one of: ${SERVICES[*]} (got '${service}')"
            target_services+=("${service}")
        done
    fi

    project="$(resolve_project)"
    deployer_email="$(resolve_deployer_email)"
    image_tag="$(git -C "${ROOT_DIR}" rev-parse HEAD)"

    domain_name="$(read_tfstate_output domain_name)"
    broker_gsa_email="$(read_tfstate_output broker_gsa_email)"

    echo "Deploying to google-cloud env=${env_name} project=${project} image_tag=${image_tag}"

    configure_docker_auth
    for service in "${target_services[@]}"; do
        build_and_push "${service}" "${project}" "${image_tag}"
    done

    export IMAGE_TAG="${image_tag}"
    export INTERNAL_DOMAIN="${domain_name}"
    export GOOGLE_CLOUD_PROJECT="${project}"
    export BROKER_GSA_EMAIL="${broker_gsa_email}"
    export DEPLOYER_EMAIL="${deployer_email}"
    export REPOSITORY

    # BUNSHIN_STACKS は region 非依存の共通値なのでループの外で 1 回 source する
    set -a
    # shellcheck disable=SC1091
    source "${MANIFESTS_DIR}/stacks.env"
    set +a

    for i in "${!REGION_DIRS[@]}"; do
        region_dir="${REGION_DIRS[$i]}"
        membership="${MEMBERSHIPS[$i]}"
        context="connectgateway_${project}_global_${membership}"

        nginx_resolver="$(read_tfstate_output "nginx_resolver_${region_dir}")"
        export NGINX_RESOLVER="${nginx_resolver}"

        set -a
        # shellcheck disable=SC1090
        source "${MANIFESTS_DIR}/regions/${region_dir}/region.env"
        set +a

        echo "[${membership}] fetching Connect Gateway credentials"
        gcloud container fleet memberships get-credentials "${membership}" \
            --project="${project}" >/dev/null

        apply_manifests "${context}"

        for service in "${target_services[@]}"; do
            wait_rollout "${context}" "${service}"
        done
    done
}

main "$@"
