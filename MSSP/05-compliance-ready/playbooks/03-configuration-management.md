# 03 — Configuration Management (CM)

> NIST 800-53: CM-2, CM-6, CM-7, CM-8 — Baselines, settings, least functionality, inventory.

---

## CM-2: Baseline Configuration

Git is your baseline. ArgoCD enforces it.

```bash
# Verify ArgoCD self-heal is enabled (drift gets auto-corrected)
argocd app get my-app --output json | jq '.spec.syncPolicy.automated.selfHeal'
# Expected: true

# Verify Kustomize base exists (the "golden" config)
ls $TARGET_DIR/k8s/base/
```

**Evidence:** Git repo is source of truth, ArgoCD auto-syncs drift, Kustomize base defines the standard.

---

## CM-6: Configuration Settings

```bash
# Verify Kyverno policies are in Enforce mode
kubectl get clusterpolicy -o json | jq -r '.items[] | "\(.metadata.name): \(.spec.validationFailureAction)"'
# Expected: all say "Enforce"

# Verify Checkov passes in CI
grep -l "checkov" $TARGET_DIR/.github/workflows/*.yml
# Expected: at least one workflow

# Run Conftest with FedRAMP policies
conftest test $TARGET_DIR/k8s/ --policy policies/conftest/fedramp-controls.rego
```

**Evidence:** Kyverno enforcing, Checkov in CI pipeline, Conftest FedRAMP policies passing.

---

## CM-7: Least Functionality

```bash
# Verify distroless or minimal base images
kubectl get pods -A -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | sort -u
# Look for: -slim, -alpine, distroless. Flag: ubuntu, debian (full), centos

# Verify no debug tools in production containers
kubectl exec -n app deploy/api -- which curl wget nc ncat 2>/dev/null
# Expected: command not found for all
```

**Evidence:** Minimal base images, no debug tools in containers.

---

## CM-8: Information System Component Inventory

```bash
# Container inventory
kubectl get pods -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) \(.spec.containers[0].image)"' > $OUTPUT_DIR/container-inventory.txt

# Cloud resource inventory
aws resourcegroupstaggingapi get-resources --output json > $OUTPUT_DIR/aws-inventory.json

# Dependency SBOM
trivy fs $TARGET_DIR --format spdx-json > $OUTPUT_DIR/sbom.json
```

**Evidence:** Weekly inventory generation, SBOM per application.

---

## Next Step

Go to [04-system-communications.md](04-system-communications.md).
