# AVD Lab — Dev Container image
# Based on the official Python 3.11 devcontainer base so Python is already
# present and configured. System packages and containerlab are baked in at
# build time so the image can be prebuilt by GitHub Codespaces for fast startup.

FROM mcr.microsoft.com/devcontainers/python:3.11-bullseye

# ── System packages ───────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        git \
        openssh-client \
        iputils-ping \
        dnsutils \
    && rm -rf /var/lib/apt/lists/*

# ── containerlab ──────────────────────────────────────────────────────────────
# The install script detects the OS and drops the binary into /usr/bin.
RUN bash -c "$(curl -sL https://get.containerlab.dev)"

# ── Python packages ───────────────────────────────────────────────────────────
# Copy only the requirements files so Docker can cache this layer independently
# of the rest of the repo content.
COPY requirements.txt requirements.yml /tmp/avd-lab/

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/avd-lab/requirements.txt

# Ansible Galaxy collections are intentionally NOT installed here.
# They are installed in postCreate.sh so the collection versions are always
# fresh and not locked to the image build date.
