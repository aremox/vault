FROM alpine:3.20

RUN apk add --no-cache \
    gitea \
    git \
    sqlite \
    curl \
    jq \
    bash \
    su-exec

RUN (id -u gitea >/dev/null 2>&1 || adduser -D -H -s /bin/bash gitea) && \
    mkdir -p /data/gitea/conf /data/git /run/gitea && \
    chown -R gitea /data /run/gitea

COPY infra/git/bootstrap-gitea.sh /usr/local/bin/bootstrap-gitea.sh
RUN sed -i 's/\r$//' /usr/local/bin/bootstrap-gitea.sh && \
    chmod +x /usr/local/bin/bootstrap-gitea.sh

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/bootstrap-gitea.sh"]
