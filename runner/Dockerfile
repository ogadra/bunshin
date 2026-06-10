# checkov:skip=CKV_DOCKER_3:runner executes user commands and requires root
# checkov:skip=CKV_DOCKER_2:health check is managed by compose/orchestrator
FROM golang:1.26.4-alpine@sha256:f23e8b227fb4493eabe03bede4d5a32d04092da71962f1fb79b5f7d1e6c2a17f AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./

# test stage
FROM build AS test
RUN apk add --no-cache bash~=5.3
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
RUN CGO_ENABLED=0 go test -v -coverprofile=cover.out -timeout=30s ./... \
    && total=$(go tool cover -func=cover.out | grep ^total: | awk '{print $NF}') \
    && echo "Total coverage: ${total}" \
    && test "${total}" = "100.0%" || { echo "FAIL: coverage ${total} is below 100.0%"; exit 1; }

# race detection stage
FROM build AS test-race
RUN apk add --no-cache bash~=5.3 gcc musl-dev
RUN CGO_ENABLED=1 go test -race -v -count=1 ./...

# binary build
FROM build AS binary
RUN CGO_ENABLED=0 go build -o /server .

# nix runtime build
FROM nixos/nix:2.34.7@sha256:bf1d938835ab96312f098fa6c2e9cab367728e0aad0646ee3e02a787c80d8fb8 AS nix-runtime

ENV PATH="/usr/local/bin:${PATH}"

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

RUN mkdir -p /etc/nix
COPY ./nix/build.conf /etc/nix/nix.conf

RUN nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs && \
    nix-channel --add https://github.com/nix-community/home-manager/archive/release-25.11.tar.gz home-manager && \
    nix-channel --update

RUN nix-env -e man man-db || true

RUN nix-shell '<home-manager>' -A install

RUN command -v home-manager && \
    HM_REAL="$(readlink -f "$(command -v home-manager)")" && \
    mkdir -p /usr/local/bin && \
    printf '%s\n' '#!/bin/sh' "exec \"$HM_REAL\" \"\$@\"" > /usr/local/bin/home-manager && \
    chmod +x /usr/local/bin/home-manager

RUN nix-env -e bash-interactive bash || true

RUN mkdir -p /root/.config/home-manager
COPY ./nix/home.nix /root/.config/home-manager/home.nix

RUN home-manager switch

RUN nix shell nixpkgs#gnused --command sh -c '\
    sed -i '\''s|TZ = "Asia/Tokyo";|TZ = "Pacific/Honolulu";|g'\'' /root/.config/home-manager/home.nix && \
    sed -i '\''s|LANG = "ja_JP.UTF-8";|LANG = "en_US.UTF-8";|g'\'' /root/.config/home-manager/home.nix && \
    sed -i '\''s|LC_ALL = "ja_JP.UTF-8";|LC_ALL = "en_US.UTF-8";|g'\'' /root/.config/home-manager/home.nix && \
    home-manager switch'

COPY ./nix/prebuilt-tools.nix /tmp/prebuilt-tools.nix
RUN nix build --no-link --print-out-paths --file /tmp/prebuilt-tools.nix > /tmp/prebuilt-tools-paths.txt && \
    prebuilt_tools="$(cat /tmp/prebuilt-tools-paths.txt)" && \
    mkdir -p /nix/var/nix/gcroots/prebuilt-tools /usr/local/bin && \
    nix-store --add-root /nix/var/nix/gcroots/prebuilt-tools/runner-prebuilt-tools --indirect -r "$prebuilt_tools" && \
    for bin in fastfetch cowsay pokemonsay lolcat figlet ip awk; do \
      ln -sf "$prebuilt_tools/bin/$bin" "/usr/local/bin/$bin"; \
    done

COPY ./nix/make-registry.sh /tmp/make-registry.sh
RUN /root/.nix-profile/bin/bash /tmp/make-registry.sh /tmp/prebuilt-tools-paths.txt

COPY ./nix/root-registry.sh /tmp/root-registry.sh
RUN /root/.nix-profile/bin/bash /tmp/root-registry.sh

RUN mkdir -p /app
COPY ./app/ /app/
WORKDIR /app

RUN nix flake archive

RUN HM_OUT="$(nix-build '<home-manager>' -A home-manager --no-out-link)" && \
    HM_REAL="$HM_OUT/bin/home-manager" && \
    NIX_REAL="$(readlink -f "$(command -v nix)")" && \
    BASH_REAL="$(readlink -f /root/.nix-profile/bin/bash)" && \
    printf '%s\n' '#!/bin/sh' "exec \"$HM_REAL\" \"\$@\"" > /usr/local/bin/home-manager && \
    ln -sf "$NIX_REAL" /usr/local/bin/nix && \
    ln -sf "$BASH_REAL" /usr/local/bin/bash && \
    mkdir -p /nix/var/nix/gcroots/runtime && \
    nix-store --add-root /nix/var/nix/gcroots/runtime/home-manager --indirect -r "$HM_OUT" && \
    nix-store --add-root /nix/var/nix/gcroots/runtime/nix --indirect -r "$NIX_REAL" && \
    nix-store --add-root /nix/var/nix/gcroots/runtime/bash --indirect -r "$BASH_REAL" && \
    rm -rf /root/.cache /tmp/* && \
    rm -f /root/.nix-defexpr/channels \
      /nix/var/nix/profiles/per-user/root/channels \
      /nix/var/nix/profiles/per-user/root/channels-*-link \
      /nix/var/nix/gcroots/docker/* && \
    nix-collect-garbage -d

# production image
FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

ENV PATH="/usr/local/bin:/root/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NIX_SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"

RUN addgroup -S nixbld && \
    mkdir -p /etc/nix /etc/profile.d && \
    for i in $(seq 1 32); do \
      adduser -S -D -H -h /var/empty -s /sbin/nologin -G nixbld "nixbld$i"; \
    done

COPY ./nix/runtime.conf /etc/nix/nix.conf
COPY ./nix/path.sh /etc/profile.d/nix-path.sh
COPY --from=nix-runtime /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=nix-runtime /etc/nix/registry.json /etc/nix/registry.json
COPY --from=nix-runtime /nix /nix
COPY --from=nix-runtime /root /root
COPY --from=nix-runtime /usr/local/bin /usr/local/bin
COPY ./app/ /app/
WORKDIR /app

COPY --from=binary /server /server
EXPOSE 3000
CMD ["/server"]
