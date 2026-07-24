connect_gateway_context() {
    local project="${1:?project required}"
    local membership="${2:?membership required}"
    echo "connectgateway_${project}_global_${membership}"
}

connect_gateway_fetch_credentials() {
    local project="${1:?project required}"
    local membership="${2:?membership required}"
    gcloud container fleet memberships get-credentials "${membership}" \
        --project="${project}" >/dev/null
}
