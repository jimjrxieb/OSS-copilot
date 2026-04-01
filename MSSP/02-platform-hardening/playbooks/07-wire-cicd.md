# 07 — Wire CI/CD

> Add Conftest policy checks to your CI pipeline so bad K8s manifests and Terraform get caught before merge.

Kyverno catches bad deployments at the cluster. Conftest catches them in CI — before the code even gets merged. Two layers, same rules.

---

## What You Need

- CI pipeline set up (see 01-application-hardening playbook 06)
- Conftest installed locally for testing

---

## Step 1: Copy Policies to Your Project

```bash
cd $TARGET_DIR
mkdir -p policy/

# Copy the Rego policies
cp ../../MSSP/02-platform-hardening/policies/conftest/*.rego policy/
```

These policies cover:
- K8s security (privileged, root, :latest, capabilities, RBAC)
- Terraform security (S3 encryption, public access, open SGs, RDS)
- CI/CD security (unpinned actions, overly broad permissions)
- Image security (untrusted registries)
- Secrets management (native secrets banned)

---

## Step 2: Test Locally

```bash
# Test against your K8s manifests
conftest test k8s/ --policy policy/

# Test against Terraform
terraform show -json tfplan | conftest test - --policy policy/

# Test against GitHub Actions
conftest test .github/workflows/ --policy policy/
```

---

## Step 3: Add to GitHub Actions

```yaml
# .github/workflows/policy-check.yml
name: Policy Check
on:
  pull_request:
    paths:
      - 'k8s/**'
      - 'terraform/**'
      - 'infrastructure/**'
      - '*.yaml'
      - '*.yml'

jobs:
  conftest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Conftest
        run: |
          wget -q https://github.com/open-policy-agent/conftest/releases/download/v0.50.0/conftest_0.50.0_Linux_x86_64.tar.gz
          tar xzf conftest_0.50.0_Linux_x86_64.tar.gz
          sudo mv conftest /usr/local/bin/

      - name: Check K8s manifests
        run: conftest test k8s/ --policy policy/ --output json | tee conftest-k8s.json

      - name: Check Terraform (if present)
        if: hashFiles('terraform/') != ''
        run: conftest test terraform/ --policy policy/ --output json | tee conftest-tf.json
```

---

## Step 4: Set Up Branch Protection

```
GitHub repo > Settings > Branches > main
  [x] Require status checks to pass
      Required: conftest
```

---

## Step 5: Commit

```bash
cd $TARGET_DIR
git add policy/ .github/workflows/policy-check.yml
git commit -m "ci: add Conftest policy checks for K8s and Terraform"
```

---

## Next Step

Go to [08-deploy-staging.md](08-deploy-staging.md) to deploy to the staging environment.
