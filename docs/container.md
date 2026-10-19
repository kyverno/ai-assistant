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
The first image build takes 15 to 30 minutes on a laptop with 8 GB of RAM; after that, starting is quick.

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
agent, so the agent can edit its own `config.yaml` (for example to remove a hook entry or widen the tool list).
The hook *scripts* run from `/opt/kyverno/profiles/maintainer/hooks`, which is root-owned and read-only under the
sandbox policy, so the agent cannot rewrite them. Layers 1, 2 and 5 do not depend on `config.yaml` at all.

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

## Publishing the image (maintainers)

Users can always build the image themselves with `container/kyverno --build`. To let them download it instead
(a few minutes, and identical for everyone), `.github/workflows/container-image.yml` builds it in CI and publishes
it to the GitHub Container Registry as `ghcr.io/<owner>/ai-assistant`, one multi-architecture image for Apple
Silicon / arm64 Linux and Intel / amd64 Linux. Each architecture is built on a native runner.

To release: push a tag.

```bash
git tag v1.0.0 && git push origin v1.0.0     # publishes v1.0.0 and moves "latest"
```

Running the workflow by hand from the Actions tab publishes the `edge` tag and leaves `latest` alone.

One-time setup for an org admin:

1. Allow the repository's workflows to publish packages (the workflow asks for `packages: write`).
2. After the first publish, open the package's settings and make it **public**. New packages are private, and the
   launcher pulls without logging in.

The launcher pulls `ghcr.io/kyverno/ai-assistant:latest` by default. A fork or a different registry can set
`KYVERNO_IMAGE` or pass `--image`.

**Not tested yet:** the workflow has not been run, and the Intel (amd64) image has not been built or run. The
Dockerfile is architecture-neutral by design (the Hermes installer picks the right tools for the machine), but the
first amd64 build is the real test.

## Security notes

Checked on this branch (19 Oct 2026): shellcheck on every script, hadolint on the Dockerfile, a secret scan of
everything the PR adds, the image's contents, and a vulnerability scan with Trivy. The scan numbers change from
day to day, so they are not recorded here; the command to rerun it is under "Updating dependencies".

**Fixed in this PR:**

- The base image is pinned by digest, and OpenShell's installer is fetched from its pinned tag, not `main`.
- A failed download inside a piped build step fails the build.
- The repo and username you type are validated before they are used in a URL or written to a settings file.
- The safety hooks run from a read-only location (`/opt/kyverno`), and the build checks that the agent cannot write
  to them or to Hermes' code.
- The final image contains only live files (see "How the image is built, and why").

**Known limits, not fixed:**

- The agent can edit its own `config.yaml` inside the sandbox (above).
- Hermes' installer is fetched from Hermes' website while the image is built (`curl | bash`). That is the same trust as
  running Hermes at all, and the Hermes commit it installs is pinned, but the script itself is not.
- Hermes' own pinned dependency set had known vulnerabilities in the Trivy scan: Python and Node libraries, none in OS
  packages, including one CRITICAL (an authentication bypass in PyJWT). They come from the Hermes version we pin, so
  the fix is to bump it. Whether each one is reachable in this setup has not been assessed.
- Packages the memory plugin brings in (`fastembed`, `onnxruntime`, ...) and `apt` packages are resolved when the
  image is built, not locked with hashes. `mnemosyne-hermes`, `mnemosyne-memory` and `anthropic` are pinned by hand.
- The published image is not signed and has no SBOM or provenance attestation.
- The launcher installs OpenShell with its own installer (`curl | sh`, from a pinned tag, but not checksum-verified).
  OpenShell is 0.x and the launcher reads its command output; it was tested with 0.1.3.
- There is no automated end-to-end test of the launcher and sandbox. The image build proves the memory plugin loads
  and works offline, CI lints the scripts, and a full chat is only tested by hand.

## Updating dependencies

Things are pinned so builds are reproducible, which means updates are deliberate. What moves what:

| Dependency | Pinned in | How it is updated |
|---|---|---|
| Base image | Both `FROM ...@sha256:` lines in `container/Dockerfile` | Dependabot proposes a new digest weekly. Build, then scan it (below) |
| GitHub Actions | Commit hashes in `.github/workflows/` | Dependabot, weekly |
| Hermes | `HERMES_COMMIT` in the Dockerfile | By hand. See below |
| `mnemosyne-hermes`, `mnemosyne-memory`, `anthropic` | The `uv pip install` line in the Dockerfile | By hand, when Hermes moves |
| OpenShell | `OPENSHELL_VERSION` in `container/kyverno` | By hand. See below |
| shellcheck, hadolint | Digests in `.github/workflows/container-lint.yml` | By hand, occasionally |

**Bumping Hermes** (about monthly, and whenever a scan shows a CRITICAL):

1. Change `HERMES_COMMIT` in the Dockerfile and build. The build fails if the memory plugin does not load or needs the
   network, if Hermes cannot tell its own version, or if the agent could write to Hermes' code or the safety hooks.
2. Check whether the `mnemosyne-*` pin is still right: remove it, build, and see if the memory provider still
   loads. It was needed because `mnemosyne-hermes` 0.7.4 refuses to start with the Hermes we pin.
3. Start a sandbox from the new image and check: the hooks are listed as allowed (`hermes -p kyverno hooks list`),
   the GitHub MCP connects (`hermes -p kyverno mcp test github`), and a short chat answers.
4. Scan the new image:
   ```bash
   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image \
     --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed kyverno-assistant:dev
   ```

**Bumping OpenShell:** change `OPENSHELL_VERSION`, then run the launcher through: first start, `--upgrade`,
`--provider`, and a policy re-apply. The launcher parses `openshell sandbox list` and `openshell provider list`,
and the provider profile format and policy schema are OpenShell's, so those are what can break.

**Not rebuilt, but can change under you:** GitHub's and Copilot's APIs, which Copilot models your plan allows, and
Docker Desktop. The first two only need the chat to be tried; the launcher checks Docker Desktop is 4.60 or newer.

## How the image is built, and why

Anything Hermes would fetch, install or ask on first use is done when the image is built:

- the profile, skills, hook paths and terminal settings (`container/setup-profile.sh`)
- the mnemosyne memory plugin, pinned to `mnemosyne-hermes 0.7.3` and `mnemosyne-memory 4.0.0b3` (0.7.4
  stops the memory provider from starting with this Hermes)
- the `anthropic` library, and the embedding model the memory plugin reads from the profile cache
- approval of the profile's own hooks (`hooks_auto_accept`)
- removal of what the finished image does not need: the Python environments that Hermes' installer and plugin installs
  leave behind (about 0.9 GB; Hermes' own `hermes pm gc` treats them as still in use) and its package download cache.
  They are only history for an in-place repair, which needs the network. The Dockerfile has two stages, so the final
  image is assembled from live files only and none of that is left in a layer

The build fails if the memory provider does not load, and its last step runs a full memory cycle (import,
search, consolidate) with no network at all, so a missing download shows up at build time, not on a laptop.
