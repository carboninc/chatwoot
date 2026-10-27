#!/usr/bin/env bash
# Executed on the test server by deploy.sh. Output belongs in RELEASE/deploy.log.
set -Eeuo pipefail
umask 077
started_at=$(date +%s)
revision=${1:?Pass the full commit SHA}
[[ $revision =~ ^[0-9a-f]{40}$ ]]
release_dir="/opt/rc-chatwoot-releases/$revision"
trap 'printf "%s\n" "$?" > "$release_dir/deploy.exit"' EXIT
exec 9>/opt/rc-chatwoot-deploy.lock
flock -n 9
previous_dir=$(readlink -f /opt/rc-chatwoot)
[[ $previous_dir != "$release_dir" ]]
cd "$release_dir/deployment/test-server"
cp "$previous_dir/deployment/test-server/.env" .env
sed -i '/^CHATWOOT_IMAGE_TAG=/d; /^CHATWOOT_IMAGE_REPOSITORY=/d' .env
printf '\nCHATWOOT_IMAGE_TAG=%s\n' "$revision" >> .env
docker compose config --quiet

# Build and validate the image before stopping any running service.
docker compose build rails < /dev/null
image_revision=$(docker compose run --rm --no-deps --entrypoint cat rails /app/.git_sha < /dev/null)
[[ $image_revision == "$revision" ]]
docker compose run --rm --no-deps rails bundle exec rails runner \
  'Account.limit(1).load; abort "Redis unavailable" unless Redis.new(Redis::Config.app).ping == "PONG"' < /dev/null

backup_dir="/opt/rc-chatwoot-backups/$(date -u +%Y%m%dT%H%M%SZ)-$revision"
mkdir -p "$backup_dir"
cp "$previous_dir/deployment/test-server/.env" "$backup_dir/previous.env"
printf '%s\n' "$previous_dir" > "$backup_dir/previous-release.txt"
writes_stopped=false
migration_started=false
on_error() {
  status=$?
  trap - ERR
  docker compose logs --no-color --tail=160 rails sidekiq > "$release_dir/startup-failure.log" 2>&1 || true
  if [[ $writes_stopped == true && $migration_started == false ]]; then
    (cd "$previous_dir/deployment/test-server" && docker compose up -d --no-build --no-deps rails sidekiq < /dev/null) || true
  fi
  printf 'Deployment failed. Logs: %s; backup: %s\n' "$release_dir" "$backup_dir" >&2
  exit "$status"
}
trap on_error ERR
writes_stopped=true
docker compose stop --timeout 60 rails sidekiq < /dev/null
docker compose exec -T postgres sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  < /dev/null > "$backup_dir/database.dump"
docker compose exec -T postgres pg_restore --list < "$backup_dir/database.dump" > "$backup_dir/database-contents.txt"
docker compose run --rm --no-deps --entrypoint tar rails -czf - -C /app/storage . \
  < /dev/null > "$backup_dir/storage.tar.gz"
gzip -t "$backup_dir/storage.tar.gz"

migration_started=true
docker compose run --rm --no-deps rails bundle exec rails db:chatwoot_prepare < /dev/null
# Preserve the proxy, database, Redis and their existing containers.
docker compose up -d --no-build --no-deps rails sidekiq < /dev/null
for attempt in $(seq 1 36); do
  if curl --silent --show-error --fail --max-time 10 https://rc-chatwoot.ru/api > "$release_dir/health.json" &&
     docker compose exec -T rails ruby -rjson -e \
       'data = JSON.parse(STDIN.read); exit(data["queue_services"] == "ok" && data["data_services"] == "ok" ? 0 : 1)' \
       < "$release_dir/health.json"; then
    break
  fi
  [[ $attempt -lt 36 ]]
  sleep 5
done
curl --silent --show-error --fail --max-time 10 https://rc-chatwoot.ru/health
running_revision=$(docker compose exec -T rails cat /app/.git_sha < /dev/null)
[[ $running_revision == "$revision" ]]
docker compose exec -T sidekiq bundle exec rails runner '
require "sidekiq/api"
require "socket"
require "timeout"
Timeout.timeout(60) do
  sleep 2 until Sidekiq::ProcessSet.new.any? { |process| process["hostname"] == Socket.gethostname }
end
Channel::Wappi.find_each do |channel|
  health = Wappi::HealthService.new(channel).fetch
  puts({ channel_id: channel.id, platform: channel.platform, status: health[:status], authorized: health[:authorized] }.to_json)
  abort "Wappi profile is not online" unless health[:status] == "online" && health[:authorized]
end
' < /dev/null
ln -sfn "$release_dir" /opt/rc-chatwoot
trap - ERR
printf '\nDEPLOYED %s\nBACKUP %s\nPREVIOUS %s\nDURATION %ss\n' \
  "$revision" "$backup_dir" "$previous_dir" "$(($(date +%s) - started_at))"
