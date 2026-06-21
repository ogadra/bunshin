#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

main() {
    local env_name="${1:?Usage: scripts/deploy/front.sh <env> <aws_profile> <aws_account_id> <domain_name>}"
    local aws_profile_name="${2:?Usage: scripts/deploy/front.sh <env> <aws_profile> <aws_account_id> <domain_name>}"
    local aws_account_id="${3:?Usage: scripts/deploy/front.sh <env> <aws_profile> <aws_account_id> <domain_name>}"
    local domain_name="${4:?Usage: scripts/deploy/front.sh <env> <aws_profile> <aws_account_id> <domain_name>}"
    local bucket_name="bunshin-static-${aws_account_id}-ap-northeast-1-an"
    local distribution_id

    echo "Deploying front to ${env_name} (${domain_name})"
    pnpm --dir "${ROOT_DIR}/front" build

    aws --profile "${aws_profile_name}" --region ap-northeast-1 s3 sync \
        "${ROOT_DIR}/front/dist/" \
        "s3://${bucket_name}/" \
        --delete

    distribution_id="$(
        aws --profile "${aws_profile_name}" --region us-east-1 cloudfront list-distributions \
            --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '${domain_name}')].Id | [0]" \
            --output text
    )"

    if [[ -z "${distribution_id}" || "${distribution_id}" == "None" ]]; then
        echo "Error: CloudFront distribution for alias ${domain_name} was not found" >&2
        exit 1
    fi

    aws --profile "${aws_profile_name}" --region us-east-1 cloudfront create-invalidation \
        --distribution-id "${distribution_id}" \
        --paths '/*' \
        >/dev/null
}

main "$@"
