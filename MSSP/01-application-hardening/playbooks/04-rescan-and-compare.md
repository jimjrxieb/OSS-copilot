# 04 — Rescan and Compare

> Re-run all scanners after fixes. Compare before and after. Produce proof.

Every fix needs proof. "We fixed it" means nothing without a rescan showing the finding is gone. The before/after comparison is the deliverable.

---

## What You Need

- Playbook 03 completed (auto-fix ran)
- Your paths set:
  ```bash
  export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
  export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
  ```

---

## Step 1: Re-Run All Scanners

```bash
bash tools/run-all-scanners.sh --target-dir $TARGET_DIR --label post-fix
```

This runs both source and infrastructure scanners. Output lands in `$OUTPUT_DIR/` with a `post-fix` label so it doesn't overwrite your baseline results.

---

## Step 2: Triage Post-Fix Results

```bash
python3 tools/triage.py --scan-dir $OUTPUT_DIR --project <your-project-name>
```

---

## Step 3: Compare Before and After

### Quick Count

```bash
BASELINE=$OUTPUT_DIR/baseline
POSTFIX=$OUTPUT_DIR/post-fix

echo "=== Source Code ==="

echo "--- Secrets ---"
echo "Before: $(jq 'length' $BASELINE/gitleaks.json 2>/dev/null || echo 0)"
echo "After:  $(jq 'length' $POSTFIX/gitleaks.json 2>/dev/null || echo 0)"

echo "--- Dependency CVEs (CRITICAL) ---"
echo "Before: $(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' $BASELINE/trivy-fs.json 2>/dev/null || echo 0)"
echo "After:  $(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' $POSTFIX/trivy-fs.json 2>/dev/null || echo 0)"

echo ""
echo "=== Infrastructure ==="

echo "--- IaC Failed Checks ---"
echo "Before: $(jq '.results.failed_checks | length' $BASELINE/results_json.json 2>/dev/null || echo 0)"
echo "After:  $(jq '.results.failed_checks | length' $POSTFIX/results_json.json 2>/dev/null || echo 0)"
```

### Detailed Diff

```bash
# Which secrets were removed?
diff <(jq -r '.[].RuleID' $BASELINE/gitleaks.json 2>/dev/null | sort) \
     <(jq -r '.[].RuleID' $POSTFIX/gitleaks.json 2>/dev/null | sort)

# Which IaC checks now pass?
diff <(jq -r '.results.failed_checks[]? | "\(.check_id) \(.file_path)"' $BASELINE/results_json.json 2>/dev/null | sort) \
     <(jq -r '.results.failed_checks[]? | "\(.check_id) \(.file_path)"' $POSTFIX/results_json.json 2>/dev/null | sort)
```

---

## Step 4: Write the Report

Copy this template and fill in the numbers:

```markdown
# Security Scan Report — <PROJECT_NAME>
Date: <DATE>

## Before / After

| Category | Baseline | Post-Fix | Reduction |
|----------|----------|----------|-----------|
| Hardcoded Secrets | ___ | ___ | ___% |
| Critical CVEs | ___ | ___ | ___% |
| High SAST Findings | ___ | ___ | ___% |
| Dockerfile Issues | ___ | ___ | ___% |
| IaC Misconfigs | ___ | ___ | ___% |
| K8s Hardening Gaps | ___ | ___ | ___% |

## What Was Fixed
- ___ hardcoded secrets removed
- ___ vulnerable dependencies upgraded
- ___ code vulnerabilities fixed
- ___ Dockerfiles hardened
- ___ K8s manifests: securityContext added
- ___ K8s manifests: resource limits set

## Remaining Findings
- ___ medium findings (documented, require review)
- ___ low findings (accepted risk)
- ___ dependencies with no fix available (monitoring)
```

---

## What "Done" Looks Like

**Source code:**
- 0 hardcoded secrets
- 0 critical CVEs
- 80%+ reduction in HIGH findings
- All Dockerfiles have USER + HEALTHCHECK

**Infrastructure:**
- 0 missing securityContext
- 0 missing resource limits
- Health probes on every deployment
- CIS benchmark passing (if cluster access)

If you're not there yet, go back to [03-auto-fix.md](03-auto-fix.md) and address the remaining findings.

---

## Next Steps

- Add policy gates to prevent regression? > [05-add-policy-gates.md](05-add-policy-gates.md)
- Add CI/CD scanning pipeline? > [06-add-ci-pipeline.md](06-add-ci-pipeline.md)
