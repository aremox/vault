FROM hashicorp/vault:1.17 AS vault-bin

FROM maven:3.9-eclipse-temurin-21 AS app-builder
WORKDIR /build
COPY app/pom.xml ./pom.xml
COPY app/src ./src
RUN mvn -q clean package -DskipTests

FROM eclipse-temurin:21-jdk-jammy

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    python3 \
    postgresql-client \
    curl \
    jq \
    procps \
    iproute2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copiar binario de Vault para ejecutar Vault Agent en la VM
COPY --from=vault-bin /bin/vault /usr/local/bin/vault

# Copiar el JAR compilado de la aplicacion Spring Boot
COPY --from=app-builder /build/target/app.jar /opt/app/app.jar

# Configurar SSH para permitir conexion de aprovisionamiento desde vm-ansible
RUN mkdir -p /var/run/sshd /etc/vault.d/templates /run/secrets /opt/app /var/log/vault-agent && \
    echo "root:ansible_vm_pwd" | chpasswd && \
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    ssh-keygen -A

COPY infra/app-vm/vault-agent.hcl /etc/vault.d/vault-agent.hcl
COPY infra/app-vm/templates/db-dynamic.properties.ctmpl /etc/vault.d/templates/db-dynamic.properties.ctmpl
COPY infra/app-vm/templates/db-static.properties.ctmpl /etc/vault.d/templates/db-static.properties.ctmpl
COPY infra/app-vm/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /etc/vault.d/vault-agent.hcl /etc/vault.d/templates/*.ctmpl && \
    chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
