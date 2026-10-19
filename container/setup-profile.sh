#!/bin/bash
# Runs once, at image build time, after `hermes profile install` and the mnemosyne install: the
# one-time profile setup that used to run on every user's first start. Doing it here means a user's
# first start only handles what is theirs (repo, username, sign-in), and each Hermes command costs
# nothing extra at runtime.
set -uo pipefail

export HERMES_HOME=/opt/hermes-home/.hermes
PROFILE=kyverno
PROFILE_DIR="$HERMES_HOME/profiles/$PROFILE"
SRC=/opt/kyverno/profiles/maintainer

step() { printf '\n== %s\n' "$1"; }
# Hermes asks for confirmation on some commands when a terminal is attached; never wait on one.
hq() { timeout 300 hermes -p "$PROFILE" "$@" </dev/null >/dev/null 2>&1 || echo "   (note: hermes $* did not finish cleanly)"; }

step "skills: this distribution's plus a small curated set of Hermes ones (same as scripts/install.sh)"
hq skills reset hermes-agent --restore --yes
hq skills opt-in --sync
(cd "$SRC" && python3 - "$PROFILE_DIR/skills" <<'PY'
import shutil, sys
from pathlib import Path
root = Path(sys.argv[1])
keep = {p.parent.name for p in Path("skills").glob("*/SKILL.md")} | set("""
hermes-agent codebase-inspection dogfood github hermes-agent-skill-authoring
inspecting-hermes-desktop-dom node-inspect-debugger python-debugpy requesting-code-review
simplify-code spike systematic-debugging test-driven-development
arxiv competitor-news-monitor grounded-citations llm-wiki blocked-page-recovery sdlc-review
""".split())
for skill in sorted(root.rglob("SKILL.md")):
    if ".archive" not in skill.parts and skill.parent.name not in keep:
        shutil.rmtree(skill.parent)
for d in sorted((q for q in root.rglob("*") if q.is_dir()), reverse=True):
    if not any(d.iterdir()):
        d.rmdir()
PY
)
hq skills opt-out

step "hooks: pin the commands to the profile directory (Hermes runs them relative to its start directory)"
python3 - "$PROFILE_DIR" <<'PY'
import sys
d = sys.argv[1]
p = d + "/config.yaml"
s = open(p).read()
open(p, "w").write(s.replace('command: "./hooks/', 'command: "' + d + '/hooks/'))
PY

step "tools: terminal and file run locally inside the sandbox; Slack is left out for now"
python3 - "$PROFILE_DIR/config.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
for tool in ("terminal", "file"):
    if not re.search(r"(?m)^    - %s$" % tool, s):
        s = s.replace("    - cronjob\n", "    - cronjob\n    - %s\n" % tool, 1)
s = re.sub(r"(?m)^    - mcp-slack\n", "", s)
open(p, "w").write(s)
PY
hq mcp remove slack
hq config set terminal.backend local
hq config set terminal.cwd /sandbox

step "hooks: approve our own hooks up front"
# Hermes asks "Allow this hook to run? [y/N]" the first time a shell hook is used, and an unapproved
# hook does not run at all (including the merge-block hook). The chat screen hides that question, so
# approve them here. These are the profile's own scripts, inside the sandbox.
hq config set hooks_auto_accept true

step "memory plugin: never go online for its embedding model (it is already in the profile's cache)"
# Without this, HuggingFace can still be asked whether the cached model is current, and in the sandbox that
# request is refused and retried. Hermes loads the profile's .env into every process (the image's own ENV
# does not reach the sandbox). Append: the terminal settings above already wrote TERMINAL_ENV here, and
# kyverno-start adds the user's repo and login later.
echo 'HF_HUB_OFFLINE=1' >> "$PROFILE_DIR/.env"

step "check"
grep -c 'mcp-slack' "$PROFILE_DIR/config.yaml" | sed 's/^/   mcp-slack lines left in config: /'
grep -E '^\s+command: ".*/hooks/' "$PROFILE_DIR/config.yaml" | head -3 | sed 's/^ */   /'
hermes -p "$PROFILE" mcp list </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'github|slack' | sed 's/^ */   /'
