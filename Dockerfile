FROM python:3.8-alpine

ARG ANSIBLE_VERSION

ENV ANSIBLE_GATHERING smart
ENV ANSIBLE_HOST_KEY_CHECKING False
ENV ANSIBLE_PYTHON_INTERPRETER /usr/bin/python
ENV ANSIBLE_RETRY_FILES_ENABLED False
ENV ANSIBLE_SSH_PIPELINING True
ENV PATH /ansible/bin:$PATH
ENV PYTHONPATH /ansible/lib
ENV CRYPTOGRAPHY_DONT_BUILD_RUST 1

RUN \
  apk add --update --no-cache \
    g++ \
    libffi-dev \
    openssh-client \
    openssl-dev \
    git \
  && pip install --upgrade --no-cache-dir \
    pip \
    python-keyczar \
    setuptools \
    wheel \
  && pip install --upgrade --no-cache-dir ansible==${ANSIBLE_VERSION}

ENTRYPOINT ["ansible-playbook"]
