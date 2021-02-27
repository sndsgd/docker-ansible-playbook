FROM python:3.8-alpine

ARG ANSIBLE_VERSION

ENV ANSIBLE_GATHERING smart
ENV ANSIBLE_PYTHON_INTERPRETER /usr/bin/python
ENV ANSIBLE_RETRY_FILES_ENABLED False
ENV ANSIBLE_SSH_PIPELINING True

RUN \
  apk add --update --no-cache --virtual dependencies \
    rust \
    cargo \
    g++ \
  && apk add --no-cache \
    libffi-dev \
    openssh-client \
    openssl-dev \
    git \
  && pip install --upgrade --no-cache-dir \
    pip \
    python-keyczar \
    setuptools \
    wheel \
  && pip install --upgrade --no-cache-dir ansible==${ANSIBLE_VERSION} \
  && apk del --purge dependencies

ENTRYPOINT ["ansible-playbook"]
