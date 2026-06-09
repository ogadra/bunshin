# checkov:skip=CKV_DOCKER_2:health check is not needed for config test stage
FROM openresty/openresty:1.31.1.1-alpine@sha256:23520ed7708e21bbc49229eae9bb1baf4ed915a262f84a9235ebf47fbf9cc3ac AS config-test
RUN apk add --no-cache gettext
COPY errors.conf /etc/nginx/errors.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY nginx.conf /etc/nginx/nginx.conf.template
ARG NGINX_RESOLVER=127.0.0.11
ARG BROKER_HOST=broker
RUN envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf \
    && openresty -t \
    && rm -f /tmp/nginx.pid
# USER is added to satisfy trivy DS-0002; openresty -t requires root so this must come after RUN
USER nobody

# checkov:skip=CKV_DOCKER_2:health check is managed by ECS task definition
FROM openresty/openresty:1.31.1.1-alpine@sha256:23520ed7708e21bbc49229eae9bb1baf4ed915a262f84a9235ebf47fbf9cc3ac
RUN apk add --no-cache gettext \
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
    && openresty -t \
    && rm -f /tmp/nginx.pid
USER nginx
