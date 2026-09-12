#!/bin/sh
set -eu

# FRAME_ANCESTORSが未設定だとframe-ancestorsが空のsource listになる。
# 全埋め込み拒否として黙って起動してしまうため、ここで落とす。
: "${FRAME_ANCESTORS:?FRAME_ANCESTORS is required}"

envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf
envsubst '${FRAME_ANCESTORS}' < /etc/nginx/security-headers.conf.template > /usr/local/openresty/nginx/conf/security-headers.conf
