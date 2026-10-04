# Community Edition workflow

This fork keeps the upstream Git history intact while excluding Chatwoot's
separately licensed Enterprise overlay from local development and production
artifacts.

## Local development

Enable the Community Edition sparse checkout:

```sh
bin/community-edition enable
```

This removes `enterprise/` and `spec/enterprise/` from the working tree without
recording hundreds of deletions in Git. Restore the complete upstream checkout
when it is needed for comparison:

```sh
bin/community-edition disable
```

The setting belongs to the local clone. Run the enable command once after each
new clone.

The local `docker-compose.override.yaml` also labels Rails and Sidekiq as
Community Edition and fixes the PostgreSQL volume target so development data
survives container recreation.

## Updating from Chatwoot

Keep `upstream` pointed at `https://github.com/chatwoot/chatwoot.git`, fetch it,
and merge the upstream development branch into the product branch:

```sh
git fetch upstream
git merge upstream/develop
bin/community-edition enable
```

Sparse checkout keeps Enterprise-only upstream changes out of the working tree,
so they do not create delete/modify conflicts.

## Production images

Build Community Edition images using the same process as Chatwoot's
`.github/workflows/publish_foss_docker.yml`: remove `enterprise/` and
`spec/enterprise/` in the temporary CI checkout before `docker build` runs, and
set `CW_EDITION=ce` in the resulting image.

Do not commit deletion of the Enterprise directories to the product branch.
