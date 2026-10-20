#!/bin/bash
# pre_tool_call hook (container variant). Terminal and file tools may only run inside an OpenShell
# sandbox: the supervisor creates /run/openshell-supervisor-ca there, and the sandbox user cannot
# create it (the filesystem policy keeps /run read-only). Anywhere else the call is blocked, so a
# copy of this profile run on a laptop can never get a terminal on the host.
set -euo pipefail
cat > /dev/null
if [ -d /run/openshell-supervisor-ca ]; then
  echo '{}'
else
  echo '{"action":"block","message":"terminal is only allowed inside the OpenShell sandbox"}'
fi
