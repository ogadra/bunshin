# checkov:skip=CKV_DOCKER_2:health check is not needed for config test stage
FROM openresty/openresty:1.27.1.2-alpine@sha256:761047d688bb91fe4eb42c42a05c794c54f274ee769ad54802b2c06247e8c38c AS config-test
RUN apk add --no-cache ca-certificates gettext
COPY errors.conf /etc/nginx/errors.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY nginx.conf /etc/nginx/nginx.conf.template
ARG NGINX_RESOLVER=127.0.0.11
ARG BROKER_HOST=broker
RUN envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf \
    && STACK_NAME=config-test INTERNAL_DOMAIN=config-test.invalid BUNSHIN_STACKS=config-test openresty -t \
    && rm -f /tmp/nginx.pid
# USER is added to satisfy trivy DS-0002; openresty -t requires root so this must come after RUN
USER nobody

# checkov:skip=CKV_DOCKER_2:health check is managed by ECS task definition
FROM openresty/openresty:1.27.1.2-alpine@sha256:761047d688bb91fe4eb42c42a05c794c54f274ee769ad54802b2c06247e8c38c
RUN apk add --no-cache ca-certificates gettext \
    && adduser -D -H -s /sbin/nologin nginx \
    && chown -R nginx:nginx /usr/local/openresty/nginx /run
COPY --chown=nginx:nginx errors.conf /etc/nginx/errors.conf
COPY --chown=nginx:nginx lua/ /usr/local/openresty/nginx/lua/
COPY --chown=nginx:nginx nginx.conf /etc/nginx/nginx.conf.template
ARG NGINX_RESOLVER
ARG BROKER_HOST
RUN envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf \
    && chown nginx:nginx /usr/local/openresty/nginx/conf/nginx.conf \
    && rm -f /usr/local/openresty/nginx/lua/*_test.lua \
    && STACK_NAME=config-test INTERNAL_DOMAIN=config-test.invalid BUNSHIN_STACKS=config-test openresty -t \
    && rm -f /tmp/nginx.pid
USER nginx
