#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICES=(broker nginx runner)
REGIONS=(asia-northeast1 asia-northeast2)
REGION_DIRS=(asne1 asne2)
REPOSITORY="bunshin"
NAMESPACE="bunshin"
MEMBERSHIPS=(bunshin-asne1 bunshin-asne2)
MANIFESTS_DIR="${ROOT_DIR}/deploy/gcp"

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

# envsubst で ${VAR} を展開して kubectl apply に流す。REGION 変数の値を
# 各 pass で切り替え、base/ の region 非依存 yaml と regions/<REGION_DIR>/ の
# region 依存 yaml を同一の env で処理する
apply_manifests() {
    local region_dir="${1:?}"
    local context="${2:?}"
    local f

    for f in "${MANIFESTS_DIR}/base/"*.yaml "${MANIFESTS_DIR}/regions/${region_dir}/"*.yaml; do
        envsubst < "${f}" | kubectl --context="${context}" apply -f -
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
    local region
    local region_dir
    local membership
    local context

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

    for i in "${!REGIONS[@]}"; do
        region="${REGIONS[$i]}"
        region_dir="${REGION_DIRS[$i]}"
        membership="${MEMBERSHIPS[$i]}"
        context="connectgateway_${project}_global_${membership}"

        # regions/<region_dir>/region.env の STACK_NAME 等を env に注入し、
        # base + regions/<region_dir> の manifest を envsubst で展開して apply する
        set -a
        # shellcheck disable=SC1090
        source "${MANIFESTS_DIR}/regions/${region_dir}/region.env"
        set +a
        export IMAGE_REGISTRY="${region}-docker.pkg.dev/${project}/${REPOSITORY}"

        echo "[${membership}] fetching Connect Gateway credentials"
        gcloud container fleet memberships get-credentials "${membership}" \
            --project="${project}" >/dev/null

        apply_manifests "${region_dir}" "${context}"

        for service in "${target_services[@]}"; do
            wait_rollout "${context}" "${service}"
        done
    done
}

main "$@"
