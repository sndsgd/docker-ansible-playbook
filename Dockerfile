FROM alpine:3.12

ARG ANSIBLE_VERSION

ENV ANSIBLE_GATHERING smart
ENV ANSIBLE_HOST_KEY_CHECKING False
ENV ANSIBLE_PYTHON_INTERPRETER /usr/bin/python
ENV ANSIBLE_RETRY_FILES_ENABLED False
ENV ANSIBLE_SSH_PIPELINING True
ENV PATH /ansible/bin:$PATH
ENV PYTHONPATH /ansible/lib

RUN \
  apk add --update --no-cache \
    g++ \
    libffi-dev \
    openssh-client \
    openssl-dev \
    git \
    py3-pip \
    python3-dev \
  && pip3 install --upgrade --no-cache-dir \
    pip \
    python-keyczar \
    setuptools \
    wheel \
  && pip3 install --upgrade --no-cache-dir ansible==${ANSIBLE_VERSION}

ENTRYPOINT ["ansible-playbook"]
