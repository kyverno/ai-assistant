# kyverno-assistant

An on-demand review assistant for a Kyverno maintainer. It orders your PR queue, briefs you on
individual PRs, triages issues and Discussions, and acts on GitHub with your own credentials. It
**cannot merge**.

Built as a [Hermes profile distribution](https://hermes-agent.nousresearch.com/docs/user-guide/profile-distributions).
You install it, add your own credentials, and talk to it in the terminal (`kyverno chat`) or on
Slack. There is no server to run and no webhook receiver.

> **Status:** works today. Not yet validated across multiple maintainers' real workflows
> (see the validation plan in [`docs/deployment.md`](docs/deployment.md)).

## Contents

- [Quick start](#quick-start)
- [Setup](#setup)
- [What it does](#what-it-does)
- [The dashboard](#the-dashboard)
- [Repository layout](#repository-layout)
- [Further reading](#further-reading)

## Quick start

```bash
git clone https://github.com/kyverno/ai-assistant.git
cd ai-assistant
./scripts/install.sh      # first run installs, then tells you which credentials to fill in
$EDITOR ~/.hermes/profiles/kyverno/.env
./scripts/install.sh      # second run verifies everything
kyverno chat
```

You need Docker, the Hermes CLI, a GitHub token and a model provider. The details are below.

## Setup

### 1. Prerequisites

| Requirement | Notes |
|---|---|
| [Docker](https://docs.docker.com/get-docker/) | Must be running. The GitHub and Slack tools each run as their own container. |
| [Hermes CLI](https://hermes-agent.nousresearch.com) | On your `PATH`. |
| A model provider | **Either** an Anthropic API key, **or** a GitHub Copilot seat with Claude Sonnet enabled plus a fine-grained PAT (see below). |

For the Copilot route, the PAT must be owned by your **personal** account (not an org) and have the
Account permission **Copilot Requests**. It is a separate token from the GitHub token in step 2.

### 2. GitHub token

Create a fine-grained personal access token scoped to the repo you will point the assistant at
(for example `kyverno/kyverno`):

| Permission | Access |
|---|---|
| Contents | Read |
| Pull requests | Read & Write |
| Issues | Read & Write |
| Checks | Read |
| Code scanning alerts | Read |
| Dependabot alerts | Read |
| Secret scanning alerts | Read |
| Organization members | Read |

Do not grant Contents Write, merge, or admin scopes. See [`docs/architecture.md`](docs/architecture.md)
for the reasoning.

### 3. Slack (optional, skip for CLI-only use)

One Slack app serves two purposes: the **bot** you `@mention` or DM to talk to the assistant, and a
**tool** the assistant uses to read the maintainers channel and post into it (for example the merge
sequence, or a reply in a PTAL thread). The app, the channel and the people using it must all be in
the **same Slack workspace**.

<details>
<summary><b>Create the Slack app</b></summary>

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From scratch**.
   Name it and pick your workspace.
2. **OAuth & Permissions** → add these Bot Token Scopes:
   `chat:write`, `channels:history`, `channels:read`, `app_mentions:read`, `groups:read`,
   `mpim:read`, `im:read`.
   The last three are needed even though the assistant only reads one public channel: the Slack
   tool fetches every channel type at startup and needs a scope for each.
3. **Socket Mode** → turn it on → generate an App-Level Token with the `connections:write` scope.
   Save it.
4. **Event Subscriptions** → turn it on → subscribe to the bot events `app_mention` and
   `message.channels`.
5. **Install App** to your workspace → copy the **Bot User OAuth Token**.
6. Invite the bot to your maintainers channel (`/invite @<bot-name>`). Note the channel ID and your
   own Slack member ID (both are in the channel-details and profile menus).
7. If you change scopes after installing, click **reinstall your app** on the OAuth & Permissions
   page so they take effect.

</details>

### 4. Install

```bash
./scripts/install.sh
```

The script is idempotent: re-run it as often as you like and it only does what is left.

1. **First run:** installs the profile, then stops and lists the credentials to fill in at
   `~/.hermes/profiles/kyverno/.env` (copied from `.env.example`).
2. **Fill in the `.env`**, then run the script again. It installs the messaging gateway (only if
   Slack is configured), checks that the GitHub and Slack tools are reachable and the hooks are
   approved, and prints ✓ or ✗ for each check.

| Variable | Required | Purpose |
|---|---|---|
| `GITHUB_TOKEN` | yes | Token from step 2 |
| `MAINTAINER_GITHUB_LOGIN` | yes | Your GitHub username |
| `KYVERNO_REPO` | yes | `owner/repo` the assistant manages (default `kyverno/kyverno`) |
| `ANTHROPIC_API_KEY` or `COPILOT_GITHUB_TOKEN` | one of | Model provider |
| `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` | Slack only | Bot and app-level tokens |
| `SLACK_ALLOWED_USERS` | Slack only | Your Slack member ID |
| `SLACK_HOME_CHANNEL` | Slack only | Maintainers channel ID |

[`docs/deployment.md`](docs/deployment.md) describes each variable in full. Pasting real values into
`.env` once is the one manual step: `hermes profile install` has no non-interactive way to accept
credentials.

### 5. Run it

```bash
kyverno chat
```

Or mention the bot in the Slack channel you invited it to.

Claude Sonnet is the default model for both providers. To switch:

- In a chat, `/model <name>` changes the current session. `/model <name> --global` also saves it.
- From the shell, `hermes -p kyverno model` opens the picker for new sessions.

Saved choices survive re-running `./scripts/install.sh`.

### 6. Turn on the review digest (optional)

The profile ships a weekday-morning merge-sequence digest that posts to your Slack channel. It
arrives **paused**, so nothing posts to Slack on a schedule until you resume it:

```bash
hermes cron list                          # shows "kyverno-review-digest", paused
hermes cron resume kyverno-review-digest
hermes cron edit kyverno-review-digest    # change the time or channel
```

## What it does

| Area | Capabilities |
|---|---|
| **PR queue** | Fetches every open PR matching a focus (milestone, author, area or label) in one batched call, Dependabot PRs included. Builds a dependency graph, layers it into tiers (stacked PRs, generated-file conflicts, body references, closing-issue conflicts), then orders each tier by a precedence ladder and states the reason for every position. |
| **PR briefs** | Explains any PR: short by default, deeper on request (review threads, risk, suggested action, Slack and Discussions context). Open-ended questions are answered by looking things up. |
| **Merge gates** | Reports live e2e-gate status per target branch, kept separate from `ready-for-review`. |
| **Dependabot** | Reviews every open Dependabot PR and says which to merge now, fix first, review yourself, wait on, or close, citing call sites, release notes and Copilot's findings. |
| **Issues** | Classifies issues, maps issue and PR relationships, summarises progress, surfaces stale items, and runs the decide-table actions (label, close, assign, milestone, nudge, raise). |
| **Stale and author-blocked PRs** | Recommends close, reassign or needs-help, and checks status before a PR goes stale. |
| **PR actions** | Labels, comments, requests changes, approves, and brings a PR's branch up to date with its base, all with your own token. The branch update is a GitHub-API merge-update, not a git rebase, even when you ask for a rebase. |
| **Discussions** | Reads GitHub Discussions and drafts replies. Nothing is posted until you confirm. |
| **Memory** | Remembers your current focus and working style across sessions, plus past incidents, rejected PRs and contributor patterns, retrieved where relevant. |

**It cannot merge.** There is no merge tool in its toolset, and this is enforced in three
independent layers. See [`docs/architecture.md`](docs/architecture.md).

## The dashboard

A browser board that shows what the agent just told you, linked, grouped and sortable, so you don't
scroll the chat or copy links by hand.

```bash
hermes -p kyverno dashboard
```

Pick **Kyverno** in the sidebar under Plugins, or open
`http://127.0.0.1:9119/kyverno?profile=kyverno`. It refreshes every 15 seconds. Keep it open next to
the chat: it fills when the agent answers a queue, stale-PR, issue-triage or Discussions request,
not in the background.

| Tab | Shows |
|---|---|
| **Overview** | What is waiting on you, grouped by verdict (rescue, decide, review, close, triage…), the milestone and due date, gate status, recent actions. |
| **PRs / Issues / Discussions** | One row per item with a GitHub link, state (CI, merge state, size, labels) and the agent's verdict and reason. Switch views, filter by verdict, search, sort. |
| **Detail panel** | Summary, unresolved threads, a graph of related PRs and issues, and any drafted comment awaiting your confirmation, with a copy button. |
| **Activity** | Every action you confirmed (approvals, comments, nudges, closes, deferrals) with a timestamp and a link. |

The dashboard is read-only. Confirming and acting still happen in the chat.

## Repository layout

```
distribution.yaml        install manifest: name, version, required env vars
SOUL.md                  the agent's identity and boundaries
config.yaml              model default, GitHub/Slack MCP servers, tool allowlist
scripts/install.sh       idempotent installer and sanity checks
hooks/                   pre_tool_call backstops
plugins/                 bundled Hermes plugins
skills/                  agent skills
cron/jobs.json           scheduled jobs (installed paused)
docs/                    design, deployment and usage docs
```

<details>
<summary><b>Details</b></summary>

**Core files**

- `config.yaml`: the model default, the GitHub and Slack MCP server declarations (`mcp_servers:`),
  and the hand-picked tool allowlist. Security-critical, so edit by hand only.
- `scripts/install.sh`: profile install, credential check, gateway install, AGENTS.md cache
  seeding, toolset sanity checks.
- `cron/jobs.json`: a weekday review digest posted to Slack and two silent memory jobs
  (`kyverno-memory-sweep`, `kyverno-memory-consolidate`). All install paused.

**Hooks**

- `hooks/block-dangerous-tools.sh`: rejects any merge, delete-repo or force-push-shaped tool call.
- `hooks/block-mnemosyne-triples.sh`: restricts the memory plugin's `triple_add` to the exact facts
  this distribution writes.

**Plugins**

- `plugins/kyverno-fetch/`: `fetch_pr_candidates` and `fetch_file_diff_overlap`, one batched call
  over GitHub's GraphQL and REST APIs.
- `plugins/kyverno-sequencer/`: `sequence_prs`, a hard-dependency graph with cycle detection and
  topological layering into tiers.
- `plugins/kyverno-dashboard/`: the `update_dashboard` tool and the Kyverno tab in
  `hermes dashboard`.

**Skills**

| Skill | Purpose |
|---|---|
| `kyverno-context` | Live labels, CODEOWNERS and milestone lookup, plus Kyverno's codegen, CI split and e2e-gate facts |
| `pr-queue` | Merge-sequence recommendations and per-PR review briefs |
| `pr-actions` | Labels, comments, reviews and branch updates via your token |
| `dependabot-queue` | Dependabot PR verdicts |
| `issue-triage` | Issue classification, issue and PR relationships, progress, staleness |
| `issue-actions` | Issue label, close, assign, milestone, nudge and raise |
| `author-followup` | Stale and author-blocked PR decisions |
| `discussions` | Reads and answers GitHub Discussions, with confirmation before posting |
| `dashboard-sync` | Pushes presented results and confirmed actions to the dashboard |

</details>

## Further reading

| Doc | Contents |
|---|---|
| [`docs/capabilities.md`](docs/capabilities.md) | A tour of what it can do, with example prompts |
| [`docs/deployment.md`](docs/deployment.md) | Install runbook and every environment variable |
| [`docs/architecture.md`](docs/architecture.md) | Design and security model |
| [`docs/workflow.md`](docs/workflow.md) | The target maintainer workflow and build plan |
