# Playbook 05: Track Your Progress

> Rescan after fixing things and prove it worked. The before/after is the deliverable.
>
> **Time:** ~10 minutes
> **Prerequisites:** You ran [01-first-scan.md](01-first-scan.md) before fixing things

---

## The Rule

"We fixed it" means nothing without proof. The proof is a rescan showing the
finding is gone. This is how you show your team, your manager, or your auditor
that the work actually mattered.

---

## Step 1: Rescan

Run the exact same scanners you ran during your first scan:

```bash
TARGET=/path/to/your/project

cd /path/to/oss-copilot/01-code

# Same commands as Playbook 01
./scan-secrets.sh "$TARGET"
./scan-code.sh "$TARGET"
./scan-dependencies.sh "$TARGET"
```

---

## Step 2: Save the Post-Fix Results

```bash
POSTFIX_DIR="$TARGET/.oss-copilot/postfix-$(date +%Y%m%d)"
mkdir -p "$POSTFIX_DIR"
cp "$TARGET/.oss-copilot/code/"*.json "$POSTFIX_DIR/"
echo "Post-fix results saved to $POSTFIX_DIR"
```

---

## Step 3: Compare Before and After

This is the money step. Run this to see your improvement:

```bash
BASELINE="$TARGET/.oss-copilot/baseline-YYYYMMDD"  # ← Replace with your actual date
POSTFIX="$TARGET/.oss-copilot/postfix-$(date +%Y%m%d)"

python3 - "$BASELINE" "$POSTFIX" << 'PYTHON'
import json, sys, os

baseline_dir = sys.argv[1]
postfix_dir = sys.argv[2]

def count_findings(directory, filename, counter):
    filepath = os.path.join(directory, filename)
    if not os.path.exists(filepath):
        return 0
    try:
        data = json.load(open(filepath))
        return counter(data)
    except:
        return 0

def count_gitleaks(data):
    return len(data) if isinstance(data, list) else 0

def count_semgrep(data):
    return len(data.get('results', []))

def count_trivy(data):
    return sum(len(r.get('Vulnerabilities', [])) for r in data.get('Results', []))

def count_bandit(data):
    return len(data.get('results', []))

def count_grype(data):
    return len(data.get('matches', []))

scanners = [
    ("Secrets (Gitleaks)", "gitleaks-results.json", count_gitleaks),
    ("Code (Semgrep)", "semgrep-results.json", count_semgrep),
    ("Python (Bandit)", "bandit-results.json", count_bandit),
    ("Deps (Trivy)", "trivy-deps-results.json", count_trivy),
    ("Deps (Grype)", "grype-results.json", count_grype),
]

print(f"\n{'Category':<25} {'Before':>8} {'After':>8} {'Change':>8} {'Reduction':>10}")
print("-" * 65)

total_before = 0
total_after = 0

for name, filename, counter in scanners:
    before = count_findings(baseline_dir, filename, counter)
    after = count_findings(postfix_dir, filename, counter)
    total_before += before
    total_after += after
    change = after - before
    pct = f"{((before - after) / before * 100):.0f}%" if before > 0 else "—"
    sign = "+" if change > 0 else ""
    print(f"{name:<25} {before:>8} {after:>8} {sign+str(change):>8} {pct:>10}")

print("-" * 65)
change = total_after - total_before
pct = f"{((total_before - total_after) / total_before * 100):.0f}%" if total_before > 0 else "—"
sign = "+" if change > 0 else ""
print(f"{'TOTAL':<25} {total_before:>8} {total_after:>8} {sign+str(change):>8} {pct:>10}")
print()
PYTHON
```

### Example output:

```
Category                   Before    After   Change  Reduction
-----------------------------------------------------------------
Secrets (Gitleaks)              3        0       -3       100%
Code (Semgrep)                 24       12      -12        50%
Python (Bandit)                18        4      -14        78%
Deps (Trivy)                   45       12      -33        73%
Deps (Grype)                   38        9      -29        76%
-----------------------------------------------------------------
TOTAL                         128       37      -91        71%
```

That's your proof. 71% reduction in findings.

---

## Step 4: What "Done" Looks Like

Not every finding needs to be at zero. Here's a realistic target:

| Category | Target | Why |
|----------|--------|-----|
| Secrets | **0** | Non-negotiable. Every secret must be removed and rotated. |
| CRITICAL CVEs | **0** | Known exploits exist. Fix all of them. |
| HIGH code findings | **80% reduction** | Fix injection, shell exec, deserialization. Some need architecture changes. |
| HIGH CVEs | **Fix what's fixable** | Some have no patch yet — document as accepted risk. |
| MEDIUM findings | **50% reduction** | Work through over time. Not urgent. |
| LOW/INFO | **Don't chase** | Fix when you're touching the file anyway. |

**The honest answer:** You will never reach 0 total findings on a real project.
The goal is 0 secrets, 0 CRITICAL CVEs, and a significant reduction in everything
else. That's what separates a team that scans from a team that doesn't.

---

## Step 5: Keep Scanning

Security isn't a one-time thing. New CVEs are disclosed every day. New code
gets written every week. You need continuous scanning.

**If you set up CI (Playbook 03):** Every PR is already scanned. New code
can't introduce known vulnerabilities without the PR failing.

**If you set up pre-commit hooks (Playbook 04):** Developers catch issues
before they commit. Fastest feedback loop.

**For ongoing baseline tracking:**

```bash
# Monthly rescan — save results with date
TARGET=/path/to/your/project
cd /path/to/oss-copilot/01-code
./scan-secrets.sh "$TARGET"
./scan-code.sh "$TARGET"
./scan-dependencies.sh "$TARGET"

MONTHLY="$TARGET/.oss-copilot/scan-$(date +%Y%m%d)"
mkdir -p "$MONTHLY"
cp "$TARGET/.oss-copilot/code/"*.json "$MONTHLY/"
```

Over time, you build a history:
```
.oss-copilot/
├── baseline-20260315/    ← First scan: 128 findings
├── postfix-20260322/     ← After first fixes: 37 findings
├── scan-20260401/        ← Monthly check: 29 findings
├── scan-20260501/        ← Monthly check: 22 findings
└── code/                 ← Latest results
```

That trend line — 128 → 37 → 29 → 22 — is the story. It shows continuous
improvement, not just a one-time effort.

---

## Sharing Results

### For your team:

```markdown
## Security Scan Progress — [Project Name]

| Date | Secrets | CRITICAL CVEs | HIGH Findings | Total |
|------|---------|--------------|---------------|-------|
| Mar 15 (baseline) | 3 | 8 | 45 | 128 |
| Mar 22 (post-fix)  | 0 | 0 | 12 | 37 |
| Apr 1              | 0 | 0 | 9 | 29 |

CI pipeline: Active (blocks on secrets + CRITICAL CVEs)
Pre-commit hooks: Installed (Gitleaks + Semgrep)
```

### For your manager:

> "We went from 128 security findings to 37 in the first week, and we're down
> to 29 now. Zero secrets in the codebase, zero critical CVEs. The CI pipeline
> blocks any new ones from merging. We're handling this with open source tools —
> no additional license spend."

That's a conversation that gets you noticed.

---

## When to Scan the Other Layers

Code scanning is just the first C. If your project has containers, a cluster,
or cloud infrastructure, there's more to scan:

| Your Project Has... | Next Step |
|--------------------|-----------|
| Kubernetes manifests | [02-cluster/](../../02-cluster/) — CIS benchmarks, RBAC, admission control |
| Dockerfiles | [03-container/](../../03-container/) — image scanning, Dockerfile linting, runtime detection |
| AWS/cloud infrastructure | [04-cloud/](../../04-cloud/) — cloud posture, IaC scanning |
| Compliance requirements | [05-compliance/](../../05-compliance/) — NIST mapping, evidence packaging |

---

## You Did It

If you followed all five playbooks, you now have:
1. An understanding of what you're scanning (Playbook 00)
2. A baseline of your security posture (Playbook 01)
3. Knowledge of what the findings mean (Playbook 02)
4. Automated scanning on every PR (Playbook 03)
5. Pre-commit hooks for instant feedback (Playbook 04)
6. A before/after comparison proving improvement (this playbook)

That's the open source version of what Checkmarx, Snyk, and GitGuardian sell
for $50K-$200K per year. You just did it for free.

The enterprise tools have better dashboards, auto-fix PRs, and reachability
analysis. But the core — finding vulnerabilities in your code, dependencies,
and secrets — you've got it covered.
