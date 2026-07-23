# checkov:skip=CKV_DOCKER_2:health check is not needed for config test stage
FROM openresty/openresty:1.31.1.1-alpine@sha256:5f621903212ed7194a6bd31de7a76c1cfbe92e7b7a6fdb0f2b38626e97bd38c4 AS config-test
RUN apk add --no-cache ca-certificates gettext
COPY errors.conf /etc/nginx/errors.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY nginx.conf /etc/nginx/nginx.conf.template
ARG NGINX_RESOLVER=127.0.0.11
ARG BROKER_HOST=broker
ARG CLOUD
RUN envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf \
    && STACK_NAME=config-test INTERNAL_DOMAIN=config-test.invalid BUNSHIN_STACKS=config-test RUNNER_API_PORT=3000 RUNNER_APP_PORT=5000 CLOUD=$CLOUD openresty -t \
    && for t in /usr/local/openresty/nginx/lua/*_test.lua; do /usr/local/openresty/luajit/bin/luajit "$t" || exit 1; done \
    && rm -f /tmp/nginx.pid
# USER is added to satisfy trivy DS-0002; openresty -t requires root so this must come after RUN
USER nobody

# checkov:skip=CKV_DOCKER_2:health check is managed by ECS task definition / Kubernetes probes
FROM openresty/openresty:1.31.1.1-alpine@sha256:5f621903212ed7194a6bd31de7a76c1cfbe92e7b7a6fdb0f2b38626e97bd38c4
RUN apk add --no-cache ca-certificates gettext \
    && adduser -D -H -s /sbin/nologin nginx \
    && chown -R nginx:nginx /usr/local/openresty/nginx /run
COPY --chown=nginx:nginx errors.conf /etc/nginx/errors.conf
COPY --chown=nginx:nginx lua/ /usr/local/openresty/nginx/lua/
COPY --chown=nginx:nginx nginx.conf /etc/nginx/nginx.conf.template
RUN rm -f /usr/local/openresty/nginx/lua/*_test.lua
USER nginx
CMD ["/bin/sh", "-c", "envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf && exec openresty -g 'daemon off;'"]
