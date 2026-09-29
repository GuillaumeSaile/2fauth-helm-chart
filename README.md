# 2FAuth on Kubernetes

An unofficial Helm chart for [2FAuth](https://github.com/Bubka/2FAuth), the
self-hosted web app for managing your two-factor authentication (2FA) accounts.
Upstream supports only bare-metal and Docker installs.

```sh
helm install my-2fauth ./charts/2fauth \
  --namespace 2fauth --create-namespace \
  --set config.app.url=https://2fa.example.com
```

The documentation is in [`charts/2fauth/README.md`](charts/2fauth/README.md).
Read its "Things that will bite you" section before you deploy. It explains
how to keep `APP_KEY` safe, especially under Argo CD.
