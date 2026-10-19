# Running the assistant in an OpenShell sandbox

The assistant (Hermes, its Kyverno profile, and the memory plugin) runs entirely inside one
[OpenShell](https://github.com/NVIDIA/OpenShell) sandbox, started from one image. You install Docker; the
launcher does the rest.

```bash
container/kyverno --build     # first time: builds the image from this checkout, then starts it
container/kyverno             # every later run: reattach (or start) the sandbox
container/kyverno --build --upgrade   # after pulling a new version: rebuild and recreate, keeping your state
```

Needs Docker Desktop 4.60 or newer on Apple Silicon macOS, or Docker on Linux (arm64 image only for now).
The first image build takes 15 to 20 minutes on a laptop with 8 GB of RAM; after that, starting is quick.

## What runs where

| Where | What runs there |
|---|---|
| **Your laptop** | Docker, the OpenShell CLI and gateway, and the launcher (`container/kyverno`). Nothing else. |
| **OpenShell gateway** (on the laptop) | Holds your GitHub token and any model API keys, enforces the network policy through a proxy, and keeps the audit log. |
| **The sandbox** | Hermes, the profile (skills, plugins, hooks), the memory plugin and its database, the agent's terminal, and the Copilot sign-in token. |

The image is built once. Hermes is pinned to a commit and every package it needs is installed at build time,
because the sandbox has no open internet and the chat screen hides first-use prompts.

## How secrets are handled

| Secret | Where it lives | What the sandbox sees |
|---|---|---|
| GitHub token (fine-grained PAT) | OpenShell, asked once by the launcher | A placeholder in `REPO_GITHUB_TOKEN`. The proxy swaps in the real value on requests to `api.github.com` (reads) and the GitHub MCP server, and only from Hermes' Python. |
| Model API key (`--provider anthropic\|openai\|nvidia`) | OpenShell, asked once | A placeholder. Hermes accepts it for these providers. OpenRouter is not supported this way: Hermes requires an `sk-or-` prefix. |
| GitHub Copilot sign-in | Created by Hermes' own device-code login inside the sandbox | The real token, in the profile's `.env`. It only grants Copilot model access. |

The Copilot token and the repo token never share a variable name, so Hermes cannot pick the wrong one.

## What the agent can reach

Everything not listed is denied (`policy.yaml` and `providers/*.yaml`).

| Destination | Allowed |
|---|---|
| `api.github.com` REST and GraphQL | Reads only. Merges, repo deletion and GraphQL mutations are refused by the proxy. |
| `api.githubcopilot.com/mcp/` (GitHub MCP) | `GET`, `POST`, `DELETE`, with the repo token swapped in |
| Copilot inference (`api.githubcopilot.com`, `api.individual.githubcopilot.com`, ...) | Yes, with Hermes' own Copilot token |
| `github.com` login endpoints | Only the two device-code paths |
| `github.com`, `codeload`, `raw.githubusercontent.com` | Read-only, for the agent's terminal, no credential |
| `models.dev` | Read-only, for the `/model` list |
| A model provider you added with `--provider` | Only that provider's API host |

## What works

Verified means I ran it in a real sandbox on the current image.

| Area | Status | Notes |
|---|---|---|
| Image build, sandbox start, first run | Verified | First run takes about a second; agent start to reply about 30 seconds |
| GitHub MCP with the real token | Verified | Connects, 63 tools. Merge tools are not in the list |
| REST and GraphQL reads with the real token | Verified | Merge, delete and GraphQL mutations refused by the proxy |
| Safety hooks (merge blocker, mnemosyne triples, terminal guard) | Verified | Approved at build time, listed as allowed |
| Memory plugin (mnemosyne) | Verified | Starts, searches, consolidates, with the network off. Embedding model is in the image |
| Skills, plugins (`kyverno-fetch`, `kyverno-sequencer`) | Verified loaded | 63 GitHub tools, 29 skills in the banner |
| GitHub Copilot sign-in and a model reply | Verified | Device-code login works inside the sandbox. Which models answer depends on your plan: see below |
| Anthropic / NVIDIA / OpenAI keys | Partly | The request reaches the provider with the key swapped in. A real reply is untested |
| Agent terminal and file tools | Enabled, not exercised | They run locally in the sandbox; the hook allows them only inside OpenShell |
| Slack | Not available | The Slack MCP server runs under Docker, which a sandbox does not have |
| Dashboard | Not available | Not packaged yet |
| Scheduled jobs (cron, the Slack digest) | Not available | They run inside the Hermes gateway, which is not started |
| `AGENTS.md` cache seeding | Not done | `kyverno-context` falls back to searching GitHub |
| Keeping state when the image is upgraded | Verified | `--upgrade`: see below |

## Upgrading and your state

State lives inside the sandbox and survives stopping and starting it. A new image means a new sandbox, so
`container/kyverno --build --upgrade` (or `--image NEW`) saves your state, recreates the sandbox from the new
image, and puts the state back. It carries only what is yours:

- the memory database, the notes in `memories/`, and the chat history and sessions
- your repo and username, and the Copilot sign-in (just those settings, not the whole `.env`)
- the model you chose

The profile itself (skills, plugins, hooks, settings) always comes from the new image. If saving fails, the old
sandbox is left alone. If restoring fails, the saved copy stays in a temporary folder and its path is printed; it
holds your Copilot token, so delete it when you are done. OpenShell only moves files in and out of `/sandbox`,
so the bundle goes through there and is removed afterwards. Skills you created inside the sandbox are not carried.

## Safety layers

The agent cannot merge, and no single mechanism is trusted on its own:

1. The GitHub token has no merge permission (Pull requests: write without Contents: write).
2. The proxy refuses REST merges, repo deletion and GraphQL mutations.
3. The GitHub MCP tool allowlist (`X-MCP-Tools` and `tools.include` in `config.yaml`) has no merge tool.
4. A pre-tool hook blocks tools whose names look like merge, delete or force-push.
5. The network policy denies everything not listed above.

Trade-off compared with the older host install: Hermes and its config now live in the same sandbox as the
agent, so the agent can edit its own `config.yaml` and hooks. Layers 1, 2 and 5 do not depend on those files.

## Choosing a model

- **GitHub Copilot** is the default. A free account may not allow the model Hermes pre-selects. Copilot's
  model list marks several models `enabled` that a free account still rejects with
  `model_not_supported`, so only a real request tells you. `gpt-4.1` and `gpt-4o-mini` answered on a free
  account. Switch in chat with `/model gpt-4.1 --global`.
- **Another provider:** `container/kyverno --provider anthropic` (or `openai`, `nvidia`). The key is
  asked once and kept in OpenShell.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Chat looks frozen right after start | Hermes may be waiting on a question the screen hides. This image is built so that does not happen; if it does, rebuild with `--build` |
| `The requested model is not supported` | The model is not available on your Copilot plan. `/model gpt-4.1` |
| `No LLM provider configured ... openrouter` | You selected a mixture-of-agents option that needs an OpenRouter key. Pick a normal model |
| Sandbox goes to `Error`, "UID or GID zero" | The image's default user must be 1000, not root |
| Agent takes about 30 seconds to appear | It loads the memory plugin's search engine. The `cpuinfo` and `onnxruntime` lines are harmless |
| Image build is slow or fails to pull | Docker Desktop's VM memory. 8 GB hosts leave Docker about 4 GB |
| Needs the real reason a sandbox is not Ready | The launcher prints the sandbox state and the last lines of its create log |

## How the image is built, and why

Anything Hermes would fetch, install or ask on first use is done when the image is built:

- the profile, skills, hook paths and terminal settings (`container/setup-profile.sh`)
- the mnemosyne memory plugin, pinned to `mnemosyne-hermes 0.7.3` and `mnemosyne-memory 4.0.0b3` (0.7.4
  stops the memory provider from starting with this Hermes)
- the `anthropic` library, and the embedding model the memory plugin reads from the profile cache
- approval of the profile's own hooks (`hooks_auto_accept`)

The build fails if the memory provider does not load, and its last step runs a full memory cycle (import,
search, consolidate) with no network at all, so a missing download shows up at build time, not on a laptop.
