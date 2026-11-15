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
    && git remote add origin https://github.com/psf/black.git \
    && git fetch -q --depth 1 origin 364941e1c29909e04f933bb0e87f365fc1d4c557 \
    && git checkout -q FETCH_HEAD \
    && git remote remove origin && rm -f .git/FETCH_HEAD
WORKDIR /testbed

RUN uv pip install --system --exclude-newer "$(git log -1 --format=%cI)" -e ".[d]" "pytest>=7.4.3" "pytest-xdist>=3.0.2" \
    && rm -rf /root/.cache

# build artifacts (egg-info, generated version files, ...) must not end up in patches
RUN git status --porcelain --untracked-files=all | sed -n 's/^?? //p' >> .git/info/exclude \
    && git status --short
