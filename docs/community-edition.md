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

Keep `upstream` pointed at `https://github.com/chatwoot/chatwoot.git`. For
production updates, merge an explicit stable release tag into a separate branch
based on our product branch (`develop`). For example, when upgrading to v4.19.0:

```sh
git fetch origin develop
git fetch --no-tags upstream refs/tags/v4.19.0:refs/tags/v4.19.0
git worktree add -b codex/upgrade-chatwoot-4-19 ../chatwoot-upgrade-4-19 origin/develop
cd ../chatwoot-upgrade-4-19
git merge --no-ff v4.19.0
bin/community-edition enable
```

Resolve conflicts in the update branch and verify migrations against a separate
database before opening a pull request into `develop`. Check both Wappi platforms
(WhatsApp and MAX): creating an inbox, starting a conversation by phone, incoming
and outgoing messages, attachments, delivery statuses, webhook authentication,
and MAX contacts whose phone number is hidden. Provider stubs verify application
behavior; a live check with dedicated test profiles verifies actual delivery.

Merge the update pull request with a **merge commit**, preserving the upstream tag
in the product branch's ancestry. Do not squash or rebase the upstream update:
retaining ancestry lets Git recognize changes already imported on later updates.
Use `upstream/develop` only for a deliberate preview of unreleased changes.

Sparse checkout keeps Enterprise-only upstream changes out of the working tree,
so they do not create delete/modify conflicts. Their Git history stays intact.

## Keeping fork changes small

Keep provider behavior in `Channel::Wappi` and `app/services/wappi/`, and provider
UI in its own components. Limit edits to shared code to the registration and
integration points that connect these features to Chatwoot. Prefer delegation to
provider code over copying upstream controllers, jobs, or Vue components.

For backend overrides, existing `prepend_mod_with` hooks are candidates for small
extension modules. The injector recognizes a `Custom` namespace when `custom/`
exists, but custom autoload and reload paths are not configured by this fork;
adding that directory alone is insufficient. Introduce and verify extension
loading in a separate change before moving Wappi behavior into an overlay. Keep
fork code separate from the separately licensed `enterprise/` directory.

Frontend registries and shared composables can reduce scattered channel checks,
but a private plugin still needs upstream integration points. Keep those changes
small and consider contributing general extension hooks upstream. Avoid broad
formatting changes or unrelated schema annotation churn in feature branches.
Move deployment configuration, branding assets, and provider components into
fork-owned files where practical. An API channel with an external integration
service is another option for stronger isolation, but migrating to it requires
checking Wappi/MAX feature parity and existing inbox data first.

## Production images

Build Community Edition images using the same process as Chatwoot's
`.github/workflows/publish_foss_docker.yml`: remove `enterprise/` and
`spec/enterprise/` in the temporary CI checkout before `docker build` runs, and
set `CW_EDITION=ce` in the resulting image.

Do not commit deletion of the Enterprise directories to the product branch.
