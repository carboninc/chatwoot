# Тестовый сервер RC Chatwoot

Адрес: https://rc-chatwoot.ru. Сервер: `root@168.113.171.75`.
Первое развёртывание: исходники `develop`, ревизия `d54dec0062b8bfafccc4ad5db798e1c6e657eb80`.

## Устройство стенда

- CI собирает приложение через `docker/Dockerfile` и публикует образ в `ghcr.io/carboninc/chatwoot`.
- Сервер скачивает готовый образ по полному SHA коммита; повторной сборки на сервере нет.
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

## Сборка и проверки pull request

`Test Docker Build` проверяет AMD64 и ARM64 на нативных runners. Устаревшая
сборка ветки отменяется при следующем push. Ruby и JavaScript устанавливаются
в независимых слоях; изменение одного lock-файла не сбрасывает второй кэш.
Скомпилированные gems сохраняются до сборки приложения, поэтому сбой assets
или публикации не теряет результат компиляции. Финальный runtime-образ проверяется
загрузкой native gems и запуском Node на каждой архитектуре.
Зависимости Vite устанавливаются один раз, а production-контейнер при запуске
проверяет готовый bundle вместо повторного `bundle install`.

После push в `develop` workflow также публикует обе архитектуры под тегом
полного SHA коммита и прогревает кэш базовой ветки для следующих PR. Первый
запуск нового Dockerfile требует холодной сборки. Ручной `workflow_dispatch`
позволяет собрать и опубликовать выбранную ветку до merge. PR из внешнего
репозитория только собирается, без доступа к registry на запись.

`Deploy Check` проверяет Compose-конфигурацию с `.env.example` и shell-скрипты.
Upstream-публикация в Docker Hub и Heroku review apps запускаются только в
`chatwoot/chatwoot`. Ветки PR на общий сервер автоматически не выкладываются.

## Обновление тестового сервера

Дождитесь успешного `Test Docker Build`, включая `Publish deployable image`,
для нужного коммита. На сервер отправляется только сжатая конфигурация из
`deployment/test-server`, без всего дерева исходников.

Пакет GHCR остаётся приватным. Один раз создайте отдельный classic PAT
с единственным scope `read:packages` у пользователя с доступом к пакету:
[создать токен для стенда](https://github.com/settings/tokens/new?description=rc-chatwoot-test&scopes=read:packages).
Передайте его Docker на сервере через stdin (запускайте из локального терминала):

```sh
bash -ec 'read -r -s -p "GHCR token (read:packages): " rc_ghcr_token; printf "\n"; printf "%s" "$rc_ghcr_token" | ssh root@168.113.171.75 "docker login ghcr.io --username carboninc --password-stdin"; unset rc_ghcr_token'
```

Ввод скрыт; значение не включается в аргументы команд и историю shell. При входе
под другой учётной записью замените `carboninc` её GitHub login. Docker сохраняет
учётные данные в root-конфигурации сервера. Токен сборки CI (`GITHUB_TOKEN`,
`packages:write`) серверу не передаётся. Без доступа к registry скрипт завершится
на скачивании образа до остановки приложения.

Из корня локального checkout выполните:

```sh
deployment/test-server/deploy.sh FULL_COMMIT_SHA
```

Скрипт запускает обновление в фоне, независимо от SSH-сессии. Прогресс и результат:

```sh
ssh root@168.113.171.75 'tail -f /opt/rc-chatwoot-releases/FULL_COMMIT_SHA/deploy.log'
ssh root@168.113.171.75 'cat /opt/rc-chatwoot-releases/FULL_COMMIT_SHA/deploy.exit'
```

`deploy.exit` появляется при завершении: `0` означает успех. Параллельные
выкладки исключены серверной блокировкой. Повторный запуск той же ревизии
с существующим логом запрещён, чтобы сохранить результат предыдущей попытки.

До остановки приложения скрипт скачивает образ, сверяет `/app/.git_sha`
и проверяет подключение к PostgreSQL/Redis. Затем останавливает Rails/Sidekiq,
сохраняет согласованную копию БД и файлов в `/opt/rc-chatwoot-backups`, запускает
миграции и обновляет только Rails/Sidekiq. Caddy, PostgreSQL и Redis продолжают
работать. После проверки HTTP, PostgreSQL, Redis, регистрации Sidekiq и статусов
Wappi/MAX переключается `/opt/rc-chatwoot`. Сообщения для проверки не отправляются.

Название Compose-проекта (`rc-chatwoot-test`) и volumes сохраняются. Если ошибка
возникла до миграции, прежние Rails/Sidekiq запускаются снова. После начала
миграции автоматический откат образа не выполняется: проверьте совместимость
схемы или восстановите согласованную резервную копию БД и файлов. Логи ошибки
сохраняются в `startup-failure.log`; текущая ссылка указывает на последний
успешный релиз. Caddy-конфигурацию при необходимости меняют отдельно.

Для ручного обновления только образа в существующем checkout используется:

```sh
docker compose pull rails sidekiq
```

`docker compose build` в конфигурации стенда больше не используется.

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
