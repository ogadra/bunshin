# checkov:skip=CKV_DOCKER_2:test-only container, no health check needed
FROM golang:1.26-alpine@sha256:f23e8b227fb4493eabe03bede4d5a32d04092da71962f1fb79b5f7d1e6c2a17f
RUN adduser -D -s /sbin/nologin appuser
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
USER appuser
CMD ["go", "test", "-v", "-count=1", "-tags=integration", "-timeout=120s", "./..."]
