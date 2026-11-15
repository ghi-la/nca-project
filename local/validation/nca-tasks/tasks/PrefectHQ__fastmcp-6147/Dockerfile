FROM --platform=linux/amd64 python:3.12-slim

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
RUN apt-get update && apt-get install -y --no-install-recommends git patch build-essential ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir uv
RUN git config --global --add safe.directory /testbed \
    && git config --global user.email "nca@localhost" && git config --global user.name "nca"
ENV PIP_DISABLE_PIP_VERSION_CHECK="1"
ENV UV_LINK_MODE="copy"

# repo at base_commit only: no remote, no later history (the agent cannot peek at the fix)
RUN git init -q /testbed && cd /testbed \
    && git remote add origin https://github.com/PrefectHQ/fastmcp.git \
    && git fetch -q --depth 1 origin fde5a7921281bae12267833c0b5624d5029229f6 \
    && git checkout -q FETCH_HEAD \
    && git remote remove origin && rm -f .git/FETCH_HEAD
WORKDIR /testbed

RUN uv export --frozen --no-hashes --no-emit-project -q -o /tmp/requirements.txt && \
    uv pip install --system -r /tmp/requirements.txt && \
    uv pip install --system --no-deps -e . \
    && rm -rf /root/.cache

# build artifacts (egg-info, generated version files, ...) must not end up in patches
RUN git status --porcelain --untracked-files=all | sed -n 's/^?? //p' >> .git/info/exclude \
    && git status --short
