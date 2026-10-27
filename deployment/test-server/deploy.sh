#!/usr/bin/env bash
# Run from a local checkout: deployment/test-server/deploy.sh FULL_COMMIT_SHA [SSH_HOST]
set -euo pipefail
revision=${1:?Pass the full commit SHA to deploy}
host=${2:-root@168.113.171.75}
if [[ ! $revision =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Expected a full, lowercase Git commit SHA' >&2
  exit 1
fi
cd "$(git rev-parse --show-toplevel)"
git cat-file -e "$revision^{commit}"
release_dir="/opt/rc-chatwoot-releases/$revision"
ssh_options=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30)
# The source cache is initialized once on the server. Only new Git objects cross the network.
# shellcheck disable=SC2029
ssh "${ssh_options[@]}" "$host" bash -s -- "'$revision'" <<'REMOTE'
set -euo pipefail
revision=$1
source_repo=/opt/rc-chatwoot-source.git
release_dir="/opt/rc-chatwoot-releases/$revision"
git --git-dir="$source_repo" fetch --depth=1 --no-tags origin "$revision"
git --git-dir="$source_repo" update-ref refs/heads/deploy "$revision"
umask 077
mkdir -p "$release_dir"
test ! -e "$release_dir/deploy.log"
git --git-dir="$source_repo" archive "$revision" | tar -xf - -C "$release_dir"
nohup bash "$release_dir/deployment/test-server/deploy-release.sh" "$revision" \
  > "$release_dir/deploy.log" 2>&1 < /dev/null &
REMOTE
printf 'Deployment started. Follow progress:\n  ssh %s "tail -f %s/deploy.log"\nResult: %s/deploy.exit (0 = success)\n' "$host" "$release_dir" "$release_dir"
