# Playbook 06: Auto-Fix with Open Source

> Let the tools fix what they can. Review the diff. Commit what's clean.
>
> **Time:** ~10 minutes
> **Prerequisites:** You've run [01-first-scan.md](01-first-scan.md) and know what's broken

---

## Why Auto-Fix Matters

Enterprise tools like Snyk auto-fix by opening PRs that bump vulnerable
dependencies. That feature alone justifies $25K/yr for some teams.

Open source tools have auto-fix too — it's just less polished. Semgrep can
rewrite code. npm/pip can bump dependencies. The key is knowing what's safe
to auto-fix and what needs human review.

---

## What Can Auto-Fix (and What Can't)

| Category | Tool | Auto-Fix? | Trust Level |
|----------|------|-----------|-------------|
| **Dependency CVEs (npm)** | `npm audit fix` | Yes | High — just version bumps |
| **Dependency CVEs (pip)** | `pip-audit --fix` | Yes | High — just version bumps |
| **SAST code patterns** | `semgrep --autofix` | Partial | Medium — review every diff |
| **Secrets** | None | No | Always manual — rotate + extract |
| **Dockerfile issues** | None reliable | No | Manual — Semgrep autofix breaks Dockerfiles |
| **K8s manifest issues** | None reliable | No | Manual — YAML autofix breaks indentation |

**The rule:** Auto-fix dependencies confidently. Auto-fix code patterns carefully.
Never auto-fix secrets, Dockerfiles, or K8s manifests.

---

## Step 1: Fix Dependencies (Safest — Do This First)

### npm projects:

```bash
cd /path/to/your/project

# See what npm can fix
npm audit

# Auto-fix non-breaking changes (safe)
npm audit fix

# See what's left after auto-fix
npm audit
```

`npm audit fix` only applies semver-compatible updates. It won't break your
app — it bumps `tar@7.5.6` to `tar@7.5.10` (patch version), not to `tar@8.0.0`.

**For breaking changes** (major version bumps):
```bash
# Shows what --force would do (DON'T run --force blindly)
npm audit fix --dry-run --force

# Only do this if you have tests and time to verify
npm audit fix --force
```

### pip projects:

```bash
# Install pip-audit if you don't have it
pip install pip-audit

# Scan and auto-fix
pip-audit --fix -r requirements.txt

# Verify the fix
pip-audit -r requirements.txt
```

### Go projects:

```bash
# Update all dependencies to latest patch versions
go get -u ./...
go mod tidy

# Verify
govulncheck ./...
```

### After fixing, rescan:

```bash
# Confirm CVEs are gone
trivy fs --severity HIGH,CRITICAL /path/to/your/project
```

---

## Step 2: Fix Code Patterns with Semgrep (Review Every Diff)

Semgrep has a built-in `--autofix` flag. It rewrites source code based on
rule-defined fix patterns.

```bash
# Dry run first — see what it would change
semgrep scan --config=auto --autofix --dryrun /path/to/your/project

# Apply fixes
semgrep scan --config=auto --autofix \
    --exclude=".oss-copilot" \
    --exclude="node_modules" \
    /path/to/your/project

# IMMEDIATELY review the diff
git diff
```

### What Semgrep auto-fix handles well:

| Finding | Auto-Fix | Safe? |
|---------|----------|-------|
| `use-of-md5` → SHA256 | Replaces `hashlib.md5()` with `hashlib.sha256()` | Yes |
| `insecure-yaml-load` → safe_load | Replaces `yaml.load()` with `yaml.safe_load()` | Yes |
| `weak-random` → secrets | Replaces `random.random()` with `secrets.token_hex()` | Review — different API |
| `missing-user` in Dockerfile | Adds `USER non-root` | **No — breaks HEALTHCHECK/CMD ordering** |
| K8s `runAsNonRoot` | Adds securityContext | **No — breaks YAML indentation** |

### What Semgrep auto-fix breaks (learned the hard way):

**Dockerfiles:** Semgrep inserts `USER non-root` but can clobber the line after
it, merging CMD instructions. Always review Dockerfile changes manually.

**YAML/K8s manifests:** Semgrep doesn't understand YAML indentation hierarchy.
It inserts `securityContext` blocks at the wrong indent level, producing
invalid YAML. Always review K8s manifest changes manually.

**The safe pattern:**
```bash
# 1. Run autofix
semgrep scan --config=auto --autofix /path/to/your/project

# 2. Review ONLY Python/JS/Go changes (safe)
git diff -- '*.py' '*.js' '*.go' '*.ts'

# 3. Stage the safe fixes
git add -p  # Interactive staging — review each hunk

# 4. Revert the broken YAML/Dockerfile changes
git checkout -- '*.yaml' '*.yml' 'Dockerfile*'

# 5. Commit the safe fixes
git commit -m "fix: semgrep auto-fix (safe code patterns only)"
```

---

## Step 3: What to Fix Manually

These categories don't have reliable auto-fix. Fix them by hand.

### Secrets (always manual):

```bash
# 1. Rotate the credential (do this FIRST — assume it's compromised)
# 2. Replace hardcoded value with env var
#    Before: API_KEY = "sk-1234567890"
#    After:  API_KEY = os.environ["API_KEY"]
# 3. Add to .env (gitignored) for local dev
# 4. Add to GitHub Secrets / AWS Secrets Manager for CI/prod
```

### Dockerfiles (manual — Semgrep breaks them):

```dockerfile
# Add USER instruction before CMD (not after HEALTHCHECK)
USER 1001
CMD ["python", "app.py"]
```

### K8s manifests (manual — Semgrep breaks indentation):

```yaml
# Add securityContext at the right indent level
spec:
  containers:
    - name: my-app
      securityContext:          # ← must be at container level
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
```

---

## Step 4: The Auto-Fix Pipeline

Run this sequence after every scan:

```bash
TARGET=/path/to/your/project
OUTPUT=/path/to/output

# 1. Scan everything
./scan-code.sh "$TARGET" --output "$OUTPUT"
./scan-secrets.sh "$TARGET" --output "$OUTPUT"
./scan-dependencies.sh "$TARGET" --output "$OUTPUT"

# 2. Auto-fix dependencies (safe)
cd "$TARGET"
npm audit fix 2>/dev/null || true
pip-audit --fix -r requirements.txt 2>/dev/null || true

# 3. Auto-fix code patterns (review required)
semgrep scan --config=auto --autofix \
    --exclude=".oss-copilot" --exclude="node_modules" "$TARGET"

# 4. Review and selectively stage
git diff                    # Review everything
git checkout -- '*.yaml' '*.yml' 'Dockerfile*'  # Revert broken YAML
git add -p                  # Interactive staging for code changes
git commit -m "fix: auto-fix dependency CVEs and safe code patterns"

# 5. Rescan to confirm
./scan-code.sh "$TARGET" --output "$OUTPUT"
./scan-dependencies.sh "$TARGET" --output "$OUTPUT"
```

---

## Other Open Source Auto-Fix Tools

| Tool | What It Fixes | Install | Notes |
|------|--------------|---------|-------|
| **npm audit fix** | JavaScript dependency CVEs | Built into npm | Safe for patch/minor bumps |
| **pip-audit --fix** | Python dependency CVEs | `pip install pip-audit` | Rewrites requirements.txt |
| **go get -u** | Go dependency CVEs | Built into Go | Run `go mod tidy` after |
| **semgrep --autofix** | Code patterns (SAST) | `pip install semgrep` | Review diffs — breaks YAML |
| **prettier** | Code formatting after autofix | `npm install prettier` | Cleans up mangled formatting |
| **yamllint + yq** | YAML formatting | `pip install yamllint` / `brew install yq` | Fix Semgrep's YAML damage |

### What enterprise adds (the gap):

| Enterprise Tool | Auto-Fix Capability | Cost |
|----------------|--------------------|----|
| **Snyk** | Opens PRs for dependency bumps, tests pass before merge | $25-100K/yr |
| **Checkmarx** | Suggests fixes in IDE with one-click apply | $50-200K/yr |
| **Mend (WhiteSource)** | Auto-PRs for dependency + license issues | $30-80K/yr |
| **GitHub Dependabot** | Auto-PRs for dependency bumps (free for public repos) | Free / $4/user/mo |

**Dependabot is free** for public repos and included with GitHub Teams. If you're
on GitHub, enable it — it's the closest thing to Snyk's auto-fix PRs at zero cost.

```
GitHub → Settings → Security → Code security and analysis
  [x] Dependabot alerts
  [x] Dependabot security updates
```

---

## What We Learned Testing This on Portfolio

| Category | Findings | Auto-Fixed | Result |
|----------|----------|-----------|--------|
| Dependencies (npm) | 70 Grype CVEs | `npm audit fix` → 0 remaining | Clean |
| Dependencies (Trivy) | 4 HIGH CVEs | `npm update tar` → 0 remaining | Clean |
| Code patterns (Semgrep) | 56 findings | 43 had autofix, but YAML broke | Mixed |
| Secrets (Gitleaks) | 7 findings | 0 (always manual) | Manual |

**The honest result:** Dependency auto-fix works great. Semgrep auto-fix works
for Python/JS/Go source code but breaks Dockerfiles and K8s YAML. Secrets
always need human attention.

---

## Next Steps

- Back to tracking progress → [05-track-progress.md](05-track-progress.md) (rescan after fixes)
- Back to the overview → [../README.md](../README.md)
