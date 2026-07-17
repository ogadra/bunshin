# Terraform / container image ops for a specific vendor and env.
# vendor: aws | google-cloud
# env:    stg | prd

_validate-env env:
    @if [ "{{env}}" != "stg" ] && [ "{{env}}" != "prd" ]; then echo "Error: env must be 'stg' or 'prd', got '{{env}}'"; exit 1; fi

_validate-vendor vendor:
    @if [ "{{vendor}}" != "aws" ] && [ "{{vendor}}" != "google-cloud" ]; then echo "Error: vendor must be 'aws' or 'google-cloud', got '{{vendor}}'"; exit 1; fi

_validate-tf-backend-bucket:
    @if [ -z "${TF_BACKEND_BUCKET:-}" ]; then echo "Error: TF_BACKEND_BUCKET must be set (see .env.example)"; exit 1; fi

# Configure the terraform backend for the vendor / env (TF_BACKEND_BUCKET must be set; see .env.example).
init vendor env: (_validate-vendor vendor) (_validate-env env) _validate-tf-backend-bucket
    terraform -chdir=terraform/{{vendor}} init -reconfigure -backend-config="bucket=${TF_BACKEND_BUCKET}" -backend-config="key=bunshin/{{vendor}}/{{env}}.tfstate"

# Preview infrastructure changes.
plan vendor env: (_validate-vendor vendor) (_validate-env env)
    terraform -chdir=terraform/{{vendor}} plan -var-file=environments/{{env}}.tfvars

# Apply infrastructure changes.
apply vendor env: (_validate-vendor vendor) (_validate-env env)
    terraform -chdir=terraform/{{vendor}} apply -var-file=environments/{{env}}.tfvars

# Destroy infrastructure for the vendor / env.
destroy vendor env: (_validate-vendor vendor) (_validate-env env)
    terraform -chdir=terraform/{{vendor}} destroy -var-file=environments/{{env}}.tfvars

# Build, push, and roll out container images for the vendor / env.
deploy vendor env *service: (_validate-vendor vendor) (_validate-env env)
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{vendor}}" in
        aws) scripts/deploy.sh {{env}} {{service}} ;;
        google-cloud) echo "Error: 'deploy google-cloud' is not implemented yet" >&2; exit 1 ;;
    esac

# Run k6 load test against the given base URL.
loadtest base_url runner_count:
    k6 run -e BASE_URL={{base_url}} -e RUNNER_COUNT={{runner_count}} loadtest/loadtest.js 2>&1 | tee k6-output.log

# Detect session_id duplicates in the last k6 run (empty output = no duplicates).
loadtest-check-dup:
    grep 'SESSION_ID:' k6-output.log | sed 's/.*SESSION_ID://' | sort | uniq -d
