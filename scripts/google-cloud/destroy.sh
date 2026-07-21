#!/usr/bin/env bash
set -euo pipefail

ENV="${1:?env (stg|prd) required}"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

rc=0
terraform -chdir="${ROOT_DIR}/terraform/google-cloud" destroy -var-file="environments/${ENV}.tfvars" || rc=$?
"${ROOT_DIR}/scripts/google-cloud/cleanup-nginx-neg.sh" || rc=$?
exit "${rc}"
