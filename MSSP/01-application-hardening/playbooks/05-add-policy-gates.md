# 05 — Add Policy Gates

> Deploy OPA/Conftest policies into your repo so bad manifests get blocked before they reach the cluster.

You fixed the findings. Now prevent them from coming back. Conftest runs OPA policies against your K8s manifests, Terraform, Dockerfiles, and GitHub Actions — and blocks anything that violates the rules.

This is your pre-deploy gate. No cluster required. The enterprise admission controllers (Kyverno, Gatekeeper, Styra) enforce the same rules at the cluster level in production. This is training camp — get everything passing here first.

---

## What You Need

- Playbook 04 completed (findings fixed and verified)
- `conftest` installed:
  ```bash
  # macOS
  brew install conftest
  # Linux
  wget https://github.com/open-policy-agent/conftest/releases/download/v0.50.0/conftest_0.50.0_Linux_x86_64.tar.gz
  tar xzf conftest_0.50.0_Linux_x86_64.tar.gz && sudo mv conftest /usr/local/bin/
  ```

---

## Step 1: Copy the Policy Into Your Project

```bash
cd $TARGET_DIR
mkdir -p policy/
cp ../../MSSP/01-application-hardening/scan-configs/conftest-policy.rego policy/
```

This one file contains all the rules. Here's what it checks:

**Kubernetes:**
- Privileged containers (deny)
- Running as root (deny)
- `:latest` image tags (deny)
- Untrusted registries (deny)
- Dangerous capabilities like SYS_ADMIN (deny)
- Wildcard RBAC and cluster-admin bindings (deny)
- Missing resource limits (warn)
- Missing health probes (warn)

**Terraform:**
- Unencrypted S3 buckets (deny)
- Public S3 buckets (deny)
- Open security groups 0.0.0.0/0 (deny)
- Public RDS instances (deny)
- IAM wildcard actions (deny)

**Dockerfiles:**
- `USER root` (deny)
- `:latest` base image (warn)

**GitHub Actions:**
- Unpinned actions without `@sha` (deny)
- `write-all` permissions (warn)

---

## Step 2: Run It

```bash
# Kubernetes manifests
conftest test k8s/ --policy policy/

# Terraform (plan JSON — recommended for CI)
terraform -chdir=terraform/ plan -out=tfplan
terraform -chdir=terraform/ show -json tfplan | conftest test - --policy policy/

# Dockerfiles
conftest test Dockerfile --policy policy/

# GitHub Actions
conftest test .github/workflows/ --policy policy/
```

**Reading the output:**
```
FAIL - k8s/deployment.yaml - Privileged container not allowed: nginx     <- blocked
WARN - k8s/deployment.yaml - Container missing resource limits: nginx    <- flagged only
```

`FAIL` = deny rule = blocks CI. `WARN` = advisory only.

---

## Step 3: Test the Policy Itself

Create test fixtures to make sure the rules actually work:

```bash
mkdir -p policy/tests/fixtures/

# Bad deployment — should be denied
cat > policy/tests/fixtures/bad-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bad-app
spec:
  template:
    spec:
      containers:
      - name: bad
        image: nginx:latest
        securityContext:
          privileged: true
EOF

# Good deployment — should pass
cat > policy/tests/fixtures/good-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: good-app
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
      containers:
      - name: good
        image: ghcr.io/myorg/myapp:v1.2.3
        securityContext:
          allowPrivilegeEscalation: false
          privileged: false
        resources:
          limits:
            cpu: "500m"
            memory: "256Mi"
EOF

# Test them
conftest test policy/tests/fixtures/bad-deployment.yaml --policy policy/
# Expected: FAIL

conftest test policy/tests/fixtures/good-deployment.yaml --policy policy/
# Expected: PASS (warns OK, no denies)
```

---

## Step 4: Add Exceptions

Some things legitimately need elevated permissions (logging DaemonSets, monitoring agents). Document every exception in the policy file:

```rego
# Exception: logging agent needs SYS_ADMIN
# Approved by: <team>, <date>
# Ticket: SEC-142
```

---

## Step 5: Wire Into CI

Add this to your GitHub Actions workflow:

```yaml
    - name: OPA Policy Check
      run: |
        conftest test k8s/ --policy policy/ --output json | tee conftest-results.json
```

The exit code is non-zero if any deny rule fires — it blocks the PR automatically.

---

## Step 6: Commit

```bash
git add policy/
git commit -m "security: add OPA/Conftest policy gate"
```

---

## How This Connects to Production

```
DEV/STAGING (this playbook)     PRODUCTION
Conftest in CI/CD          -->  Kyverno / Gatekeeper at the API server
Blocks bad manifests            Blocks bad deployments
before they reach K8s           at kubectl apply time
```

Same rules, different enforcement point. Get everything passing Conftest here, and the production admission controller has nothing to block.

---

## Next Step

Go to [06-add-ci-pipeline.md](06-add-ci-pipeline.md) to add a full security scanning pipeline to GitHub Actions.
