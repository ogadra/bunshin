#!/usr/bin/env bash
set -euo pipefail

ENV="${1:?env (stg|prd) required}"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

terraform -chdir="${ROOT_DIR}/terraform/aws" destroy -var-file="environments/${ENV}.tfvars"
