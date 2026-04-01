# 03 — Auto-Fix

> Run the auto-fixer. It reads your scan results and fixes what it can.

You ran the scans (playbooks 01 and 02). Now fix what they found. The `auto-fix.sh` script reads the scanner JSON, maps findings to fixer scripts, and applies the fixes it's confident about. Everything else gets logged for you to review.

---

## What You Need

- Playbooks 01 and/or 02 completed (scan results in your output directory)
- Your paths set:
  ```bash
  export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
  export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
  ```

---

## Step 1: Dry Run First

Always see what would change before changing anything.

```bash
bash tools/auto-fix.sh --scan-dir $OUTPUT_DIR --target $TARGET_DIR --dry-run
```

This shows you:
- Which findings have automated fixes
- What each fix would do
- Which findings need manual review

---

## Step 2: Run the Fix

```bash
bash tools/auto-fix.sh --scan-dir $OUTPUT_DIR --target $TARGET_DIR
```

**What it does:**
- Reads every scanner JSON file in your output directory
- **High-confidence fixes** run automatically (backs up originals as `.bak` first)
- **Medium-confidence fixes** are proposed but not applied — you review and approve
- **Complex findings** are logged to `ESCALATED.md` for manual review

**What gets auto-fixed (examples):**
- Missing `securityContext` in K8s manifests
- Missing resource limits
- `yaml.load()` → `yaml.safe_load()`
- `subprocess(..., shell=True)` → safe list form
- Pinning `:latest` image tags
- Adding non-root USER to Dockerfiles
- Bumping vulnerable dependency versions

---

## Step 3: Approve Medium-Confidence Fixes

If the dry run showed proposed fixes you want to apply:

```bash
bash tools/auto-fix.sh --scan-dir $OUTPUT_DIR --target $TARGET_DIR --approve-c
```

---

## Step 4: Review What Changed

```bash
# See the git diff
cd $TARGET_DIR
git diff

# Read the fix report
cat $OUTPUT_DIR/FIX-REPORT.md

# Read the escalated findings (things that need manual attention)
cat $OUTPUT_DIR/ESCALATED.md
```

**Check these things:**
- Did the fixes produce correct changes? (spot-check a few)
- Are the `.bak` backups there? (your rollback safety net)
- Do the escalated findings make sense?

---

## Step 5: Handle Escalated Findings

`ESCALATED.md` contains findings that can't be auto-fixed. Common ones:

| Finding | What to Do |
|---------|-----------|
| SQL injection | Rewrite to use parameterized queries |
| EKS public endpoint | Architecture decision — make private, add bastion |
| Secrets as env vars | Look into External Secrets Operator |
| hostPath mounts | Switch to PVC/CSI volumes |
| Cross-account IAM trust | Review each trust relationship manually |

For each one: understand the context, decide if it's a real risk, document the decision.

---

## Rollback

Every fix creates a `.bak` backup:

```bash
# Restore a single file
cp path/to/file.yaml.bak path/to/file.yaml

# Restore everything
find $TARGET_DIR -name "*.bak" | while read bak; do cp "$bak" "${bak%.bak}"; done
```

---

## Next Step

Go to [04-rescan-and-compare.md](04-rescan-and-compare.md) to verify the fixes worked.
