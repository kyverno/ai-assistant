# The Kyverno assistant as one OpenShell sandbox image: Hermes (pinned) plus the maintainer profile.
# Build from the repo root:  docker build -f container/Dockerfile -t kyverno-assistant:dev .
FROM nvcr.io/nvidia/base/ubuntu:24.04

ARG HERMES_COMMIT=5307e93252ac655cd13fadbd561c0995142138c6

# libatomic1: the Node that Hermes installs needs it on arm64.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq less make python3 ripgrep unzip xz-utils libatomic1 \
    && rm -rf /var/lib/apt/lists/*

# Hermes keeps its install records and dependency venv under HERMES_HOME with absolute paths, so it
# runs from the directory it was installed into, owned by the sandbox user (uid 1000). The code in
# /opt/hermes stays root-owned and read-only.
ENV HOME=/opt/hermes-home
RUN mkdir -p "$HOME" \
    && curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
       | bash -s -- --non-interactive --skip-browser \
           --dir /opt/hermes --hermes-home /opt/hermes-home/.hermes --commit "${HERMES_COMMIT}" \
    && chown -R 1000:1000 /opt/hermes-home \
    && chmod -R a+rX /opt/hermes \
    && ln -s /opt/hermes-home/.local/bin/hermes /usr/local/bin/hermes

# The profile, baked in and read-only; kyverno-start installs it into HERMES_HOME on first run.
COPY SOUL.md config.yaml distribution.yaml .env.example .no-bundled-skills /opt/kyverno/profiles/maintainer/
COPY hooks   /opt/kyverno/profiles/maintainer/hooks
COPY plugins /opt/kyverno/profiles/maintainer/plugins
COPY skills  /opt/kyverno/profiles/maintainer/skills
COPY cron    /opt/kyverno/profiles/maintainer/cron
# The terminal runs locally inside the sandbox here, not over ssh into a second one.
COPY container/hooks/require-sandbox-terminal.sh /opt/kyverno/profiles/maintainer/hooks/require-sandbox-terminal.sh
COPY container/kyverno-start /usr/local/bin/kyverno-start
RUN chmod 755 /usr/local/bin/kyverno-start /opt/kyverno/profiles/maintainer/hooks/*.sh \
    && chmod -R a+rX /opt/kyverno
