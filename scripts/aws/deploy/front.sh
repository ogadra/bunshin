#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

main() {
    local env_name="${1:?Usage: scripts/aws/deploy/front.sh <env> <aws_account_id>}"
    local aws_account_id="${2:?Usage: scripts/aws/deploy/front.sh <env> <aws_account_id>}"
    local bucket_name="bunshin-static-${aws_account_id}-ap-northeast-1-an"
    local domain
    domain="$(terraform -chdir="${ROOT_DIR}/terraform/aws" output -raw domain_name)"

    echo "Deploying front to ${env_name}"
    VITE_PERL_ORIGIN_TEMPLATE="https://{hex}.{stack}.${domain}/" \
        pnpm --dir "${ROOT_DIR}/front" build

    aws --profile "${env_name}" --region ap-northeast-1 s3 sync \
        "${ROOT_DIR}/front/dist/" \
        "s3://${bucket_name}/" \
        --delete
}

main "$@"
