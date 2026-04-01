# 05 — Deploy Application (ArgoCD)

> Deploy your application through ArgoCD with security gates on sync.

Everything is ready — Falco is watching, monitoring is live, logging is flowing, containers are verified. Now deploy the application through ArgoCD with pre-sync security checks and post-sync runtime verification.

In production, ArgoCD or Flux handle GitOps delivery. This sets up the same pattern for staging with security hooks baked in.

---

## What You Need

- Playbooks 00-04 completed (runtime stack deployed, containers verified)
- ArgoCD installed (from 02-platform-hardening or pre-existing)
- Application manifests in a git repo

---

## Step 1: Create the AppProject

```bash
kubectl apply -f templates/argocd/runtime-appproject.yaml
```

Review the template — it restricts which repos, clusters, and namespaces the project can deploy to:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: app-project
  namespace: argocd
spec:
  sourceRepos:
  - 'https://github.com/your-org/*'
  destinations:
  - namespace: 'app-*'
    server: 'https://kubernetes.default.svc'
```

---

## Step 2: Deploy Security Hooks

```bash
bash tools/deploy-argocd-hooks.sh
```

This deploys:

**Pre-Sync Gate** — runs before every sync:
```bash
kubectl apply -f templates/argocd/pre-sync-security-gate.yaml
```
- Runs Conftest against the manifests being deployed
- Blocks the sync if any deny rules fire
- Ensures no policy-violating manifests reach the cluster

**Post-Sync Verification** — runs after every sync:
```bash
kubectl apply -f templates/argocd/post-sync-runtime-verify.yaml
```
- Runs the container hardening verifier against new pods
- Checks Falco for alerts on the newly deployed containers
- Reports results back to ArgoCD sync status

---

## Step 3: Deploy the Application

```bash
kubectl apply -f templates/argocd/falco-application.yaml
```

Or create the Application manually:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: app-project
  source:
    repoURL: https://github.com/your-org/your-app
    targetRevision: main
    path: k8s/overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: app-staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## Step 4: Watch the Sync

```bash
# ArgoCD CLI
argocd app get my-app
argocd app sync my-app

# Or watch in the ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8443:443 &
# Open https://localhost:8443
kill %1
```

**What happens during sync:**
1. Pre-sync hook runs Conftest → blocks if policy violations found
2. ArgoCD applies manifests
3. Kyverno validates at admission → blocks if policy violations found
4. Pods start, Falco watches syscalls
5. Post-sync hook runs container hardening check
6. Sync status reports pass/fail

---

## Step 5: Deploy Sync Failure Alerts

```bash
kubectl apply -f templates/argocd/sync-fail-alerts.yaml -n monitoring
```

Fires a Prometheus alert when:
- ArgoCD sync fails
- Pre-sync security gate blocks a deployment
- Post-sync verification finds hardening failures

---

## Step 6: Verify

```bash
# App is synced and healthy?
argocd app get my-app

# Pods running?
kubectl get pods -n app-staging

# Falco watching?
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=5 | grep "app-staging"

# No alerts fired?
kubectl logs -n falco -l app.kubernetes.io/name=falco --since=5m | grep -c "Warning\|Error"
# Expected: 0 (or only known-good noise)
```

---

## ArgoCD Rules

- **Never `kubectl apply` what ArgoCD manages.** Fix in git. ArgoCD self-heals and reverts manual changes.
- **Never `argocd app sync --replace`.** This deletes PVCs. Data loss.
- **Check ownership before patching:** `kubectl get <resource> -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}'` — if it returns an app name, it's ArgoCD-managed.

---

## Next Step

Go to [06-tune-falco.md](06-tune-falco.md) to reduce noise now that the application is live.
