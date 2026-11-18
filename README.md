# 2FAuth on Kubernetes

[![CI](https://github.com/GuillaumeSaile/2fauth-helm-chart/actions/workflows/release.yaml/badge.svg)](https://github.com/GuillaumeSaile/2fauth-helm-chart/actions/workflows/release.yaml)

An unofficial Helm chart for [2FAuth](https://github.com/Bubka/2FAuth), the
self-hosted web app for managing your two-factor authentication (2FA) accounts.
Upstream supports only bare-metal and Docker installs.

```sh
helm install my-2fauth oci://ghcr.io/guillaumesaile/charts/2fauth \
  --version 2.0.1 \
  --namespace 2fauth --create-namespace \
  --set config.app.url=https://2fa.example.com
```

The current chart, `2.0.1`, deploys 2FAuth [`9.0.1`](https://github.com/Bubka/2FAuth/releases/tag/v9.0.1).

The documentation is in [`charts/2fauth/README.md`](charts/2fauth/README.md).
Read its "Things that will bite you" section before you deploy. It explains
how to keep `APP_KEY` safe, especially under Argo CD.

## Development

| Workflow | Runs on | What it does |
| --- | --- | --- |
| [`ci.yaml`](.github/workflows/ci.yaml) | pull requests | Lints the chart and checks its guardrails with Helm 3 and Helm 4. Installs every `charts/2fauth/ci/*-values.yaml` scenario on kind, then runs `helm test`, upgrades, asserts `APP_KEY` survived, and runs `helm test` again. Fails if the chart changed but its version is already released. |
| [`release.yaml`](.github/workflows/release.yaml) | pushes to `main` | Runs CI. If `Chart.yaml`'s `version` has no `2fauth-<version>` tag yet, it pushes the chart to `oci://ghcr.io/guillaumesaile/charts` and creates a GitHub release linking to the 2FAuth changelog. |
| [`upstream-update.yaml`](.github/workflows/upstream-update.yaml) | daily, 05:23 UTC | Looks for 2FAuth releases that have been out for at least 48 hours on GitHub and on Docker Hub, so a bad release has time to be pulled first. It moves `appVersion` to the newest one, bumps the chart version by the same step (2FAuth major, minor or patch → chart major, minor or patch), updates this README, commits to `main` and starts `release.yaml`. |

To release, bump `version` in `charts/2fauth/Chart.yaml` and merge to `main`.
2FAuth updates are automatic; to pick one up early, run `upstream-update.yaml`
by hand (the 48-hour quarantine still applies).

The test scripts also run against any cluster in your current kube context:

```sh
.github/scripts/lint.sh
.github/scripts/install-test.sh charts/2fauth/ci/default-values.yaml
```

## License

[Apache-2.0](LICENSE). 2FAuth itself is AGPL-3.0.
