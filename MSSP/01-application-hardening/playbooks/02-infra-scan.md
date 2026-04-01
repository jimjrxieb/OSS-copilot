# 02 — Infrastructure Scan

> Scan your Kubernetes manifests, Terraform, Helm charts, and OPA policies for misconfigurations.

This catches the infrastructure problems that source code scanners miss — missing security contexts, open security groups, unencrypted S3 buckets, CIS benchmark failures.

Same deal as playbook 01: these open source scanners prep your infra so the enterprise tools (Prisma Cloud, Wiz, etc.) have a clean baseline when they take over in production.

---

## What You Need

- Playbook 00 completed (`.scanner-excludes` exists)
- Your paths set:
  ```bash
  export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
  export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
  ```
- For Polaris and Conftest: K8s manifests in a recognized directory (`k8s/`, `kubernetes/`, `infrastructure/`, `manifests/`, `deploy/`)
- For Kube-bench: cluster access (kubeconfig). Skip this one for repo-only scans.

## The Scanners

| # | Scanner | What It Finds | What It Replaces in Prod |
|---|---------|---------------|--------------------------|
| 1 | **Checkov** | IaC misconfigs (K8s, Terraform, Dockerfile, CloudFormation) | Prisma Cloud IaC |
| 2 | **Kubescape** | NSA/CISA K8s hardening failures | Wiz K8s scanning |
| 3 | **Polaris** | K8s best practice violations (limits, probes, security context) | Fairwinds Insights |
| 4 | **Conftest** | OPA policy violations on K8s manifests | Styra DAS |
| 5 | **Kube-bench** | CIS Kubernetes Benchmark (needs cluster access) | — |

---

## Step 1: Run the Scan

```bash
bash tools/run-infra-scanners.sh --target-dir $TARGET_DIR
```

**What happens:**
- 5 infrastructure scanners run one at a time
- Polaris and Conftest auto-detect your K8s manifest directories
- Kube-bench skips automatically if it's not installed (repo-only scans don't need it)
- JSON output per scanner lands in `$OUTPUT_DIR/`

**Useful options:**
```bash
# Skip scanners that don't apply
--skip-scanner kube-bench    # no cluster access, repo-only scan
--skip-scanner conftest      # no OPA policies written yet

# Scope to specific directories
--include-dir infrastructure --include-dir k8s
```

---

## Step 2: Understand What Each Scanner Tells You

**Checkov** — the workhorse. Covers Terraform, K8s, Dockerfile, and CloudFormation in one pass.
- `CKV_K8S_*` — Kubernetes misconfigs (missing security context, no resource limits)
- `CKV_AWS_*` — AWS misconfigs (public S3, open security groups)
- `CKV_DOCKER_*` — Dockerfile issues (running as root, no healthcheck)
- Kustomize repos get double-counted (base + overlay). This is normal.

**Kubescape** — maps findings to the NSA/CISA hardening guide. Good for compliance conversations.

**Polaris** — focused on K8s deployment basics: resource limits, readiness probes, privilege escalation.

**Conftest** — runs the OPA policies from `scanners/configs/conftest-policy.rego` against your manifests. These are the custom rules.

**Kube-bench** — CIS benchmark against a live cluster. Only runs when you have cluster access.

---

## Step 3: Triage

```bash
python3 tools/triage.py --scan-dir $OUTPUT_DIR --project <your-project-name>
```

Infrastructure findings land in `REMEDIATION-PLAN.md` alongside source code findings if you ran both scanners into the same output directory.

---

## What You Get

| File | What It Is |
|------|-----------|
| `results_json.json` | Checkov IaC scan results |
| `kubescape.json` | NSA/CISA hardening results |
| `polaris.json` | K8s best practice results |
| `conftest.json` | OPA policy check results |
| `kube-bench.json` | CIS benchmark results (if cluster access) |
| `SUMMARY.md` | Finding counts by scanner |
| `REMEDIATION-PLAN.md` | Prioritized fix list |

---

## Next Steps

- Source code scan not done yet? > [01-src-code-scan.md](01-src-code-scan.md)
- Ready to auto-fix findings? > [03-auto-fix.md](03-auto-fix.md)
- Run both at once: `bash tools/run-all-scanners.sh --target-dir $TARGET_DIR`
