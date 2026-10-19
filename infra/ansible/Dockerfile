FROM alpine:3.20

RUN apk add --no-cache \
    ansible-core \
    openssh-client \
    sshpass \
    python3 \
    curl \
    jq \
    bash

ENV ANSIBLE_HOST_KEY_CHECKING=False

COPY infra/ansible/inventory.ini /etc/ansible/inventory.ini
COPY infra/ansible/playbooks/deploy-approle.yml /etc/ansible/playbooks/deploy-approle.yml

RUN sed -i 's/\r$//' /etc/ansible/inventory.ini /etc/ansible/playbooks/deploy-approle.yml

CMD ["/bin/bash", "-c", "ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/playbooks/deploy-approle.yml && touch /tmp/ansible-done && tail -f /dev/null"]
