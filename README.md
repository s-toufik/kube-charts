# kube-charts

The Helm charts the homelab runs on. Every app, API and service on the server is one Helm release of
one of these charts; [homelab-infra](https://github.com/s-toufik/homelab-infra) lists the releases
(the release train) and deploys them with helmfile.

| Chart | What it runs |
|---|---|
| [`app`](charts/app) | Any container image: Deployment or StatefulSet, Service, config files, volumes, env and Secret env, ports on the Tailscale address, NetworkPolicy, RBAC, Jobs run on every deploy, CronJobs. Its full contract is [`charts/app/values.yaml`](charts/app/values.yaml), checked by [`values.schema.json`](charts/app/values.schema.json). |
| [`pg-cluster`](charts/pg-cluster) | A PostgreSQL cluster run by the CloudNativePG operator, with its roles, passwords and databases declared. |
| [`homelab-lib`](charts/homelab-lib) | Helpers both charts share: names, labels, image, env, secure defaults. Built into them, never deployed. |

## How an app ships

```
app repository                         GitHub                                   server
──────────────                         ──────                                   ──────
devops/docker/Dockerfile   ─┐
                            ├─ git tag v1.4.0 ─► image  toufik142/<app>:1.4.0 ─┐
devops/helm/values.yml     ─┘                    chart  ghcr.io/s-toufik/       ├─► helmfile -l name=<app> apply
  (env, ports, probes…)                                 charts/<app>:1.4.0     ─┘   (or helmfile apply: the whole train)
```

- The app's CI calls the reusable workflow [`app-chart.yml`](.github/workflows/app-chart.yml): it
  takes the `app` chart, names it after the app, sets its version to the tag and merges the app's
  `devops/helm/values.yml` over the defaults ([`scripts/package-app.sh`](scripts/package-app.sh)).
- The chart and the image always share one version, so a release is one number.
- The server only adds what is specific to it: the tailnet name, the Tailscale address and its own
  overrides.

## Secure by default

Every pod runs with the RuntimeDefault seccomp profile, no privilege escalation and every Linux
capability dropped, without a Kubernetes API token unless the chart grants it RBAC rules. Published
ports listen on the server's Tailscale address only. Secrets are referenced by name, never stored in
values.

## Repository layout

```
charts/
├── app/            generic chart: templates/, values.yaml (the contract), values.schema.json, ci/ test values
├── pg-cluster/     CloudNativePG cluster, roles and databases
└── homelab-lib/    shared helpers (library chart)
scripts/
├── check.sh        lint, render with ci/*-values.yaml, schema-check (make check)
├── publish.sh      push chart versions not in the registry yet (make publish, CI on main)
└── package-app.sh  build an app's chart from its values.yml (used by app-chart.yml)
.github/workflows/
├── charts.yml      check on every push and pull request; publish on main
└── app-chart.yml   reusable: called by app repositories on a release tag
```

## Use it

```bash
make check                 # every chart; make check CHART=app for one
```

Publishing happens in CI when a chart's `version` in `Chart.yaml` is new. The steps for every task
(publishing a chart, releasing an app, deploying) are in homelab-infra's DevOps guide.
