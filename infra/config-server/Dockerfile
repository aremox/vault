FROM hashicorp/vault:1.17 AS vault-bin

FROM maven:3.9-eclipse-temurin-21 AS config-builder
WORKDIR /build
COPY config-server/pom.xml ./pom.xml
COPY config-server/src ./src
RUN mvn -q clean package -DskipTests

FROM eclipse-temurin:21-jdk-jammy

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    python3 \
    curl \
    jq \
    git \
    procps \
    iproute2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=vault-bin /bin/vault /usr/local/bin/vault
COPY --from=config-builder /build/target/config-server.jar /opt/config-server/config-server.jar

RUN mkdir -p /var/run/sshd /etc/vault.d/templates /run/secrets /opt/config-server /var/log/vault-agent && \
    echo "root:ansible_vm_pwd" | chpasswd && \
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    ssh-keygen -A

COPY infra/config-server/vault-agent.hcl /etc/vault.d/vault-agent.hcl
COPY infra/config-server/templates/git-creds.properties.ctmpl /etc/vault.d/templates/git-creds.properties.ctmpl
COPY infra/config-server/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /etc/vault.d/vault-agent.hcl /etc/vault.d/templates/*.ctmpl && \
    chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22 8888

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
