ARG PYTHON_VERSION=3.13
FROM python:${PYTHON_VERSION}-alpine
LABEL maintainer="sndsgd"

ARG ANSIBLE_VERSION

ENV ANSIBLE_GATHERING=smart
ENV ANSIBLE_RETRY_FILES_ENABLED=False
ENV ANSIBLE_SSH_PIPELINING=True

RUN \
  apk add --no-cache \
    git \
    openssh-client \
  && pip install --upgrade --no-cache-dir pip \
  && pip install --no-cache-dir ansible==${ANSIBLE_VERSION}

ENTRYPOINT ["ansible-playbook"]
