# Тестовый сервер RC Chatwoot

Адрес: https://rc-chatwoot.ru. Сервер: `root@168.113.171.75`.
Первое развёртывание: исходники `develop`, ревизия `d54dec0062b8bfafccc4ad5db798e1c6e657eb80`.

## Устройство стенда

- Приложение собирается из исходников через `docker/Dockerfile`.
- Rails и Sidekiq используют один образ с тегом ревизии исходников.
- PostgreSQL 16 с pgvector, Redis и файлы приложения хранятся в Docker volumes.
- Caddy принимает запросы на 80/443 и автоматически обновляет HTTPS-сертификат.
- Mailpit принимает тестовые письма. Его интерфейс доступен только через SSH-туннель.
- Регистрация отключена. Первый администратор создаётся до публикации приложения.

Конфигурация на сервере: `/opt/rc-chatwoot/deployment/test-server`.
Файл `.env` содержит отдельные секреты стенда и доступен только root.
Он исключён из Git и контекста Docker-сборки.
Локальная `.env` разработчика на сервер не переносится.

## Управление

```sh
ssh root@168.113.171.75
cd /opt/rc-chatwoot/deployment/test-server
docker compose ps
docker compose logs --tail=100 rails sidekiq
docker compose restart rails sidekiq
```

Пароль первоначального администратора сохранён на сервере:

```sh
ssh root@168.113.171.75 'cat /root/rc-chatwoot-admin.env'
```

После изменения пароля в приложении этот файл не обновляется.

Пока распространяется DNS, приложение доступно через защищённый SSH-туннель:

```sh
ssh -N -L 8080:127.0.0.1:8080 root@168.113.171.75
```

Откройте http://localhost:8080. Порт 8080 на сервере доступен только локально;
Caddy передаёт запросы в Rails с признаком HTTPS. Публичный адрес приложения
остаётся https://rc-chatwoot.ru, поэтому ссылки в письмах и внешние интеграции
требуют готового DNS.

Для просмотра тестовой почты запустите на своём компьютере:

```sh
ssh -N -L 8025:127.0.0.1:8025 root@168.113.171.75
```

Откройте http://localhost:8025. SMTP-доставка наружу не настроена.
Для интеграций используйте отдельные тестовые учётные записи.

## Обновление исходников

Команды ниже используют зафиксированные изменения текущей локальной ветки.
Конфигурация из этой директории и изменение `GIT_SHA` в Dockerfile должны быть
зафиксированы в развёртываемой ветке. Выполняйте из корня репозитория:

```sh
deploy_sha=$(git rev-parse HEAD)
git archive HEAD | ssh root@168.113.171.75 "mkdir -p /opt/rc-chatwoot-releases/$deploy_sha && tar -xf - -C /opt/rc-chatwoot-releases/$deploy_sha"
ssh root@168.113.171.75 bash -s -- "$deploy_sha" <<'REMOTE'
set -eu
release_dir="/opt/rc-chatwoot-releases/$1"
previous_dir=$(readlink -f /opt/rc-chatwoot)
cp "$previous_dir/deployment/test-server/.env" "$release_dir/deployment/test-server/.env"
chmod 600 "$release_dir/deployment/test-server/.env"
sed -i "s/^CHATWOOT_IMAGE_TAG=.*/CHATWOOT_IMAGE_TAG=$1/" "$release_dir/deployment/test-server/.env"
cd "$release_dir/deployment/test-server"
docker compose config --quiet
docker compose build rails
docker compose stop rails sidekiq
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
docker compose up -d --no-build
curl --fail --retry 12 --retry-delay 5 --retry-all-errors https://rc-chatwoot.ru/health
# Сохраняем первоначальную директорию и переключаем постоянный путь на новый релиз.
if [ ! -L /opt/rc-chatwoot ]; then
  mv /opt/rc-chatwoot /opt/rc-chatwoot-initial
fi
ln -sfn "$release_dir" /opt/rc-chatwoot
REMOTE
```

Название Compose-проекта фиксировано (`rc-chatwoot-test`), поэтому новые релизы
используют существующие данные. Перед изменением схемы сохраните резервную копию
БД и файлов. Откат образа после миграции требует проверки совместимости схемы.

## DNS и HTTPS

Зона `rc-chatwoot.ru` создана в DNS-хостинге AdminVPS с A-записью
`168.113.171.75`. Name-серверы домена: `ns1.adminvps.ru`, `ns2.adminvps.ru`.
При первом развёртывании домен ещё ожидал начального делегирования в зоне `.ru`.
Проверить распространение DNS можно так:

```sh
dig @ns1.adminvps.ru rc-chatwoot.ru A +short
dig @a.dns.ripn.net rc-chatwoot.ru NS +norecurse
dig @1.1.1.1 rc-chatwoot.ru A +short
```

После появления публичного DNS Caddy повторит получение сертификата
автоматически. Состояние сертификата: `docker compose logs --tail=50 caddy`.

## Проверка

```sh
curl --fail https://rc-chatwoot.ru/health
curl --head http://rc-chatwoot.ru
```

Затем войдите в приложение, создайте тестовый inbox и проверьте сообщения.
Администрирование установки: https://rc-chatwoot.ru/super_admin.

Документация: [Docker для Ubuntu](https://docs.docker.com/engine/install/ubuntu/),
[Caddy в Docker Compose](https://caddyserver.com/docs/running#docker-compose).
