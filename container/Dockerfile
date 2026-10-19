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
RUN chmod 755 /opt/kyverno/profiles/maintainer/hooks/*.sh && chmod -R a+rX /opt/kyverno

# Install the profile and its memory plugin (mnemosyne) now, while the network is open. The sandbox
# cannot reach PyPI, and at runtime Hermes would stop at a hidden "Prepare these dependencies? [y/N]"
# prompt. Hermes wants that answer on a terminal, so `script` supplies one. Runs as the sandbox user
# (uid 1000), so everything it writes into Hermes' home is already writable at runtime.
USER 1000:1000
RUN export HERMES_HOME=/opt/hermes-home/.hermes \
    && hermes profile install /opt/kyverno/profiles/maintainer --name kyverno -y \
    && printf 'y\n' | script -qec "hermes -p kyverno plugins install mnemosyne --enable" /dev/null \
    && hermes -p kyverno plugins list 2>&1 | grep -q 'mnemosyne.*enabled'

# Model-provider libraries. Hermes installs these on first use by re-resolving its whole dependency lock
# from PyPI and GitHub, which the sandbox cannot reach. OpenAI, NVIDIA, OpenRouter, Gemini and Copilot use
# the OpenAI library already in the image; Anthropic has its own.
#
# Then pin mnemosyne to the versions that work with this Hermes. mnemosyne-hermes 0.7.4 (3 Oct 2026) adds
# a per-home check that makes the memory provider fail to start ("loaded but no provider instance
# found"), and the plugin's own ranges (>=0.7.3, >=4.0.0b3) pick it up. `pm install --extra` makes a new
# environment each time, so the pin goes into whichever one Hermes is actually running, last. Remove it
# when the Hermes pin moves to a version that works with newer mnemosyne.
#
# The final lines fail the build if either library is not really usable: `anthropic` must import, and
# mnemosyne must come up as the memory provider (it fails silently otherwise).
RUN export HERMES_HOME=/opt/hermes-home/.hermes \
    && hermes pm install --extra anthropic \
    && PY="$(ls -d /opt/hermes-home/.hermes/tools/python-*/bin/python3 | head -n 1)" \
    && UV="$(find /opt/hermes-home/.hermes/tools -name uv -type f | head -n 1)" \
    && ACTIVE="$(HERMES_HOME=$HERMES_HOME/profiles/kyverno "$PY" -I -c 'import sys; sys.path.insert(0, "/opt/hermes"); import hermes_bootstrap, mnemosyne_hermes as m; print(m.__file__.split("/lib/python")[0])' | tail -n 1)" \
    && "$UV" pip install --python "$ACTIVE/bin/python" --prerelease=allow "mnemosyne-hermes==0.7.3" "mnemosyne-memory==4.0.0b3" \
    && HERMES_HOME=$HERMES_HOME/profiles/kyverno "$PY" -I -c '\
import sys; sys.path.insert(0, "/opt/hermes"); import hermes_bootstrap, anthropic; \
from plugins.memory import load_memory_provider; \
p = load_memory_provider("mnemosyne"); \
print("anthropic", anthropic.__version__, "| memory provider:", type(p).__name__ if p else None); \
sys.exit(0 if p else 1)'

# The memory plugin's embedding model (BAAI/bge-small-en-v1.5, the 64 MB quantized ONNX build). Mnemosyne's
# searches only ever read it from the profile's cache folder (local_files_only); the download happens in a
# separate first-start path that works on a laptop with internet. The sandbox cannot reach HuggingFace, so
# without this the first memory lookup stalls for a retry cycle and falls back to a weaker search.
# Download it now, into that same folder.
RUN export HERMES_HOME=/opt/hermes-home/.hermes \
    && PY="$(ls -d /opt/hermes-home/.hermes/tools/python-*/bin/python3 | head -n 1)" \
    && "$PY" -I -c 'import sys; sys.path.insert(0, "/opt/hermes"); import hermes_bootstrap; from fastembed import TextEmbedding; v = list(TextEmbedding("BAAI/bge-small-en-v1.5", cache_dir="/opt/hermes-home/.hermes/profiles/kyverno/cache/fastembed").embed(["warm up"]))[0]; print("embedding model ready, dimensions:", len(v)); sys.exit(0 if len(v) == 384 else 1)'

# The rest of the one-time profile setup (skills, hook paths, terminal and Slack settings): see the script.
COPY --chmod=755 container/setup-profile.sh /usr/local/bin/kyverno-setup-profile
RUN /usr/local/bin/kyverno-setup-profile

# Proof that the memory plugin is self-contained. This step runs with NO network: import two memories, search
# them (that needs the embedding model, read locally), and run a consolidation. If the plugin needs anything
# else from the internet, this fails the build and the output says what. The warm-up data is removed after,
# so every user starts with an empty memory.
RUN --network=none export HERMES_HOME=/opt/hermes-home/.hermes \
    && printf '%s' '{"mnemosyne_export": {"version": "1.3"}, "working_memory": [{"id": "warmup:1", "content": "Kyverno warm-up memory: the review queue is ordered by dependency tier.", "source": "warmup", "timestamp": "2026-01-01T00:00:00", "session_id": "warmup", "importance": 0.9, "scope": "global", "pinned": 1}]}' > /tmp/warmup.json \
    && hermes -p kyverno mnemosyne import -i /tmp/warmup.json --force \
    && OUT="$(hermes -p kyverno mnemosyne inspect 'dependency tier review queue' 2>&1)" \
    && echo "$OUT" \
    && ! echo "$OUT" | grep -q 'ERROR' \
    && echo "$OUT" | grep -q 'warm-up memory' \
    && hermes -p kyverno mnemosyne sleep \
    && rm -rf /tmp/warmup.json /opt/hermes-home/.hermes/profiles/kyverno/mnemosyne/data

# The image's final user must stay uid 1000: OpenShell refuses an image whose default user is root.
COPY --chmod=755 container/kyverno-start /usr/local/bin/kyverno-start
