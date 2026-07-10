# checkov:skip=CKV_DOCKER_2:health check is managed by compose/orchestrator
FROM golang:1.26.5-alpine@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# firestore_stub tag は unit / race stage で real Firestore adapter を除外するために使う。
# adapter は Firestore SDK の具象型を直接触るため mock 不可で、unit test の 100% coverage が
# 保てない。integration test では tag を付けず real adapter を emulator で回す。

# test stage
FROM build AS test
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
RUN CGO_ENABLED=0 go test -v -tags=firestore_stub -coverpkg=./... -coverprofile=cover.out ./... \
    && total=$(go tool cover -func=cover.out | grep ^total: | awk '{print $NF}') \
    && echo "Total coverage: ${total}" \
    && test "${total}" = "100.0%" || { echo "FAIL: coverage ${total} is below 100.0%"; exit 1; }

# integration test stage
FROM build AS test-integration
CMD ["go", "test", "-v", "-count=1", "-tags=integration", "./..."]

# test with race detector (requires cgo + gcc)
FROM build AS test-race
RUN apk add --no-cache gcc musl-dev \
    && CGO_ENABLED=1 go test -race -tags=firestore_stub -v ./...

# binary build
# not FROM build: that stage runs on the target platform, which puts the compiler under QEMU
FROM --platform=$BUILDPLATFORM golang:1.26.5-alpine@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS binary
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG TARGETOS TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /server .

# production image
FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
ARG TARGETARCH
RUN adduser -D -H -s /sbin/nologin appuser
COPY apk-checksums.${TARGETARCH}.sha256 /tmp/apks.sha256
RUN set -euxo pipefail; \
    mkdir -p /tmp/apks; \
    apk update; \
    apk fetch --recursive -o /tmp/apks \
        bash=5.3.9-r1 \
        ca-certificates=20260611-r0 \
        curl=8.21.0-r0; \
    apk verify /tmp/apks/*.apk; \
    find /tmp/apks -type f -name '*.apk' -exec basename {} \; | sort > /tmp/apks.actual; \
    awk '{print $2}' /tmp/apks.sha256 | sort > /tmp/apks.expected; \
    diff -u /tmp/apks.expected /tmp/apks.actual; \
    (cd /tmp/apks && sha256sum -c /tmp/apks.sha256); \
    apk --network=no add --no-cache /tmp/apks/*.apk; \
    rm -rf /tmp/apks /tmp/apks.actual /tmp/apks.expected /tmp/apks.sha256 /var/cache/apk/*
COPY --from=binary /server /server
USER appuser
EXPOSE 8080
CMD ["/server"]
