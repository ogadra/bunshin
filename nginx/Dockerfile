# checkov:skip=CKV_DOCKER_2:health check is not needed for config test stage
FROM nginx:1.30.0-alpine@sha256:0272e4604ed93c1792f03695a033a6e8546840f86e0de20a884bb17d2c924883 AS config-test
COPY errors.conf /etc/nginx/errors.conf
COPY nginx.conf /etc/nginx/nginx.conf.template
ARG NGINX_RESOLVER=127.0.0.11
ARG BROKER_HOST=broker
RUN envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf \
    && nginx -t
# USER is added to satisfy trivy DS-0002; nginx -t requires root so this must come after RUN
USER nginx

# checkov:skip=CKV_DOCKER_2:health check is managed by ECS task definition
FROM nginx:1.30.0-alpine@sha256:0272e4604ed93c1792f03695a033a6e8546840f86e0de20a884bb17d2c924883
RUN chown -R nginx:nginx /var/cache/nginx /run
COPY --chown=nginx:nginx errors.conf /etc/nginx/errors.conf
COPY --chown=nginx:nginx nginx.conf /etc/nginx/nginx.conf.template
ARG NGINX_RESOLVER
ARG BROKER_HOST
RUN envsubst '${NGINX_RESOLVER} ${BROKER_HOST}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf \
    && chown nginx:nginx /etc/nginx/nginx.conf \
    && nginx -t \
    && rm -f /run/nginx.pid
USER nginx
