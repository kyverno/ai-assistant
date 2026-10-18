# Running the assistant in an OpenShell sandbox

Everything the assistant needs (Hermes, pinned, and the maintainer profile) is in one image that runs
inside an [OpenShell](https://github.com/NVIDIA/OpenShell) sandbox. You install nothing but Docker.

```bash
container/kyverno --build      # builds the image from this checkout, then starts it
container/kyverno              # every later run: reattach (or start) the sandbox
```

Needs Docker Desktop 4.60 or newer (Apple Silicon macOS or Linux). The launcher installs OpenShell if
it is missing.

## What happens

| Where | What |
|---|---|
| Your laptop | Docker, the OpenShell gateway, the launcher, and your GitHub token (stored by OpenShell) |
| The sandbox | Hermes, the profile, the agent's terminal, its memory and settings, and the Copilot sign-in token |

- **GitHub token.** Asked once by the launcher (hidden input) and checked against your repo. The sandbox only
  holds a placeholder in `REPO_GITHUB_TOKEN`; OpenShell's proxy swaps in the real value on requests to
  `api.github.com` (reads only) and the GitHub MCP server, and only from Hermes' Python. See
  `providers/repo-github.yaml`.
- **Cannot merge.** The MCP tool list has no merge tool, a hook blocks merge-like tools, and the proxy refuses
  REST merges, repo deletion and GraphQL mutations.
- **Copilot.** Hermes' own device-code sign-in runs on the first start: open the printed page in your browser
  and enter the code. The token is kept inside the sandbox.
- **Network.** Everything not listed in `policy.yaml` is denied.

## Files

- `Dockerfile`: the image (Hermes pinned by commit, profile baked in under `/opt/kyverno`)
- `kyverno`: the launcher you run on your laptop
- `kyverno-start`: runs inside the sandbox: first-run setup, Copilot sign-in, then the chat
- `policy.yaml`: the sandbox's filesystem and network policy
- `providers/repo-github.yaml`: the OpenShell provider profile for the GitHub token
- `hooks/require-sandbox-terminal.sh`: lets the terminal run locally, but only inside an OpenShell sandbox

## Not done yet

Slack (its MCP server runs under Docker), the dashboard, the mnemosyne memory plugin, the contributor
profile, a published image (use `--build` for now), and keeping state when the image is upgraded: state
survives stop and start, not deleting and recreating the sandbox.
