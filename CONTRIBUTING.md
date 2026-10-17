# Contributing

## Setup

```sh
bundle install                                                              # from the repo root
podman compose -f tarantool-client/docker-compose.yml up -d --wait          # 2.11 on 3301, 3.x on 3302
podman compose -f tarantool-model/docker-compose.yml up -d --wait box-2.11 box-3
```

`docker compose` works the same. Each gem's README has a Development section with the commands and ports for
its own integration specs (tarantool-crud and the crud storage of tarantool-model pull a prebuilt image from
GHCR).

## Checks

Run from the repo root before opening a pull request:

```sh
bundle exec rubocop
bundle exec rake rbs                  # RBS validate + unit specs under rbs/test
bundle exec yard --fail-on-warning
cd tarantool-client && bundle exec rspec                  # unit specs of the gem you changed
INTEGRATION=1 TARANTOOL_URI=tcp://app:secret@localhost:3301 bundle exec rspec   # against a running instance
```

CI runs every suite against Tarantool 2.11 and 3.x on Ruby 3.2, 3.3 and 3.4.

## Changes

- One pull request per change, with a short conventional subject (`tarantool-client: ...`, `ci: ...`).
- Specs first: a bug fix comes with a failing example, a feature with unit specs and, when it touches the
  server, an integration spec. Follow the style of the surrounding specs.
- Public API changes update the gem's README, its CHANGELOG under the `(unreleased)` version heading, and its `sig/` signatures.
- Comments explain a non-obvious why; code that needs a comment to say what it does should be rewritten.
- Nothing that only works on Tarantool Enterprise (TLS, read views) is accepted; it cannot be tested here.

## Releases

Maintainers tag `<gem>-v<version>` on master; the Release workflow verifies the version, runs CI and publishes
to rubygems.org through a trusted publisher.
