FROM --platform=linux/amd64 python:3.12-slim

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
RUN apt-get update && apt-get install -y --no-install-recommends git patch build-essential ca-certificates curl libcurl4-openssl-dev libssl-dev libmemcached-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir uv
RUN git config --global --add safe.directory /testbed \
    && git config --global user.email "nca@localhost" && git config --global user.name "nca"
ENV PIP_DISABLE_PIP_VERSION_CHECK="1"
ENV UV_LINK_MODE="copy"
ENV BOTO_CONFIG="/dev/null"
ENV PYTHONIOENCODING="UTF-8"

# repo at base_commit only: no remote, no later history (the agent cannot peek at the fix)
RUN git init -q /testbed && cd /testbed \
    && git remote add origin https://github.com/celery/celery.git \
    && git fetch -q --depth 1 origin 05e0ea4233c89d26465c1330c285f93859ff1b7e \
    && git checkout -q FETCH_HEAD \
    && git remote remove origin && rm -f .git/FETCH_HEAD
WORKDIR /testbed

RUN uv pip install --system --exclude-newer "$(git log -1 --format=%cI)" -e . -r requirements/test.txt -r requirements/test-ci-default.txt \
    && rm -rf /root/.cache

# build artifacts (egg-info, generated version files, ...) must not end up in patches
RUN git status --porcelain --untracked-files=all | sed -n 's/^?? //p' >> .git/info/exclude \
    && git status --short
