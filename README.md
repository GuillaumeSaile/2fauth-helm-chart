# 2FAuth on Kubernetes

[![CI](https://github.com/GuillaumeSaile/2fauth-helm-chart/actions/workflows/release.yaml/badge.svg)](https://github.com/GuillaumeSaile/2fauth-helm-chart/actions/workflows/release.yaml)

An unofficial Helm chart for [2FAuth](https://github.com/Bubka/2FAuth), the
self-hosted web app for managing your two-factor authentication (2FA) accounts.
Upstream supports only bare-metal and Docker installs.

```sh
helm install my-2fauth oci://ghcr.io/guillaumesaile/charts/2fauth \
  --version 1.0.0 \
  --namespace 2fauth --create-namespace \
  --set config.app.url=https://2fa.example.com
```

The documentation is in [`charts/2fauth/README.md`](charts/2fauth/README.md).
Read its "Things that will bite you" section before you deploy. It explains
how to keep `APP_KEY` safe, especially under Argo CD.

## Development

| Workflow | Runs on | What it does |
| --- | --- | --- |
| [`ci.yaml`](.github/workflows/ci.yaml) | pull requests | Lints the chart and checks its guardrails with Helm 3 and Helm 4. Installs every `charts/2fauth/ci/*-values.yaml` scenario on kind, then runs `helm test`, upgrades, asserts `APP_KEY` survived, and runs `helm test` again. Fails if the chart changed but its version is already released. |
| [`release.yaml`](.github/workflows/release.yaml) | pushes to `main` | Runs CI. If `Chart.yaml`'s `version` has no `2fauth-<version>` tag yet, it pushes the chart to `oci://ghcr.io/guillaumesaile/charts` and creates a GitHub release. |

To release, bump `version` in `charts/2fauth/Chart.yaml` and merge to `main`.
Change `appVersion` too when you move to a new 2FAuth image.

The test scripts also run against any cluster in your current kube context:

```sh
.github/scripts/lint.sh
.github/scripts/install-test.sh charts/2fauth/ci/default-values.yaml
```

## License

[Apache-2.0](LICENSE). 2FAuth itself is AGPL-3.0.
