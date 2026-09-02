FROM data.forgejo.org/forgejo/runner:13

USER root

RUN apk add --no-cache \
    bash \
    curl \
    git \
    ca-certificates \
    docker-cli \
    containerd \
    nodejs \
    npm \
    kubectl

COPY home-arpa-ca.crt /usr/local/share/ca-certificates/home-arpa-ca.crt
RUN update-ca-certificates

USER root