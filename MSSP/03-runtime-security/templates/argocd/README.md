# ArgoCD Integration — Runtime Security Gates

## What This Does

Plugs runtime security into the ArgoCD sync lifecycle:

```
Git push → ArgoCD detects → PreSync (security gate) → Sync (apply) → PostSync (verify) → Falco watches
                                    │                                       │
                                    ▼                                       ▼
                            conftest validates                    health-check.sh +
                            manifests against                     Falco baseline +
                            02-CLUSTER-HARDEN                  new alert check
                            policies
```

Without this integration, ArgoCD blindly applies whatever passes admission control. These hooks add:

1. **PreSync** — Block deployment if manifests fail conftest policy checks
2. **PostSync** — Verify runtime health after deployment lands
3. **Sync failure alerts** — Prometheus rules that fire when syncs fail or get stuck
4. **Sync waves** — Ensure Falco is running before app workloads deploy

## Files

| File | What It Does |
|------|-------------|
| `pre-sync-security-gate.yaml` | ArgoCD PreSync hook Job — runs conftest against synced manifests |
| `post-sync-runtime-verify.yaml` | ArgoCD PostSync hook Job — runs health-check + Falco baseline diff |
| `runtime-appproject.yaml` | ArgoCD AppProject scoping runtime security resources to allowed namespaces |
| `falco-application.yaml` | ArgoCD Application CRD for Falco itself (sync wave -1, deploys before apps) |
| `sync-fail-alerts.yaml` | PrometheusRule for ArgoCD sync failures, degraded apps, stuck syncs |
| `README.md` | This file |

## How It Fits

```
02-CLUSTER-HARDEN                        03-RUNTIME-SECURITY
┌─────────────────────┐                     ┌──────────────────────────┐
│ setup-argocd.sh     │  installs ArgoCD    │ 03-templates/argocd/     │
│ golden-path/argocd/ │  Application CRDs   │   pre-sync gate          │
│ conftest policies   │◄─── referenced ────►│   post-sync verify       │
│ Kyverno policies    │     by hooks        │   sync-fail alerts       │
└─────────────────────┘                     │   Falco Application CRD  │
                                            └──────────────────────────┘
```

- `02-CLUSTER-HARDEN` owns ArgoCD installation and policy definitions
- `03-RUNTIME-SECURITY` owns runtime verification and the sync lifecycle hooks
- No duplication — pre-sync hook references policies from `02-CLUSTER-HARDEN`

## Deployment

```bash
# Deploy all ArgoCD integration resources
bash tools/deploy-argocd-hooks.sh

# Dry run first
bash tools/deploy-argocd-hooks.sh --dry-run

# Skip Falco Application CRD (Falco already managed separately)
bash tools/deploy-argocd-hooks.sh --skip-falco-app
```

## Sync Wave Order

When using sync waves, resources deploy in this order:

| Wave | What | Why |
|------|------|-----|
| -3 | Namespaces (falco, gp-security) | Must exist before anything else |
| -2 | Falco DaemonSet | Runtime detection must be watching before apps land |
| -1 | falco-exporter + Prometheus rules | Metrics pipeline ready |
| 0 | Application workloads | Normal app sync |
| 1 | PostSync verification Job | Confirm everything is healthy |

## PreSync Gate — How It Works

The PreSync Job:
1. Renders the Application's manifests (helm template or kustomize build)
2. Runs `conftest test` against `01-APP-SEC/scanning-configs/conftest-policy.rego`
3. Checks for: privileged containers, missing resource limits, latest tags, root users, dangerous capabilities
4. **If any DENY rule fires → Job fails → ArgoCD blocks the sync**
5. WARN rules are logged but don't block

The Job uses the `gp-copilot/runtime-toolkit` container image (built from this package's Dockerfile).

## PostSync Verify — How It Works

The PostSync Job:
1. Runs `health-check.sh` to verify Falco + falco-exporter are healthy
2. Checks Falco logs for new critical alerts in the last 60 seconds
3. Verifies the deployed pods have correct security contexts (non-root, read-only rootfs, drop ALL)
4. **If critical alerts or health failures → Job fails → ArgoCD marks sync as degraded**

PostSync failure doesn't roll back — it alerts. Rollback is a human (B-rank) or JADE (C-rank) decision.

## Requirements

- ArgoCD installed (see `02-CLUSTER-HARDEN/tools/platform/setup-argocd.sh`)
- conftest binary available in the runtime-toolkit image
- Prometheus Operator for sync-fail alerts
- Falco deployed (or let `falco-application.yaml` manage it)
