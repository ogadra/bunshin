#!/bin/sh
# -f でpathname展開を止める。
# FRAME_ANCESTORSを空白で分けるのに引用符を外すため、値の*がファイル名に化ける。
set -efu

# FRAME_ANCESTORSが未設定だとframe-ancestorsが空のsource listになる。
# 全埋め込み拒否として黙って起動してしまうため、ここで落とす。
: "${FRAME_ANCESTORS:?FRAME_ANCESTORS is required}"

# envsubstは値をそのままadd_headerの引用符の内側へ差し込む。
# 引用符やセミコロンが混じると、そこからdirectiveを足せてしまう。
for origin in ${FRAME_ANCESTORS}; do
    case "${origin}" in
        https://*) ;;
        *)
            echo "render-conf: FRAME_ANCESTORS must list https origins, got ${origin}" >&2
            exit 1
            ;;
    esac
    case "${origin#https://}" in
        "" | *[!.:0-9A-Za-z-]*)
            echo "render-conf: FRAME_ANCESTORS has an invalid host, got ${origin}" >&2
            exit 1
            ;;
    esac
done

envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf
envsubst '${FRAME_ANCESTORS}' < /etc/nginx/security-headers.conf.template > /usr/local/openresty/nginx/conf/security-headers.conf
