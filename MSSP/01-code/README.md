# 01-Code — Application Security Scanning

> This is what Checkmarx, Snyk, and GitGuardian do.
> Here's Semgrep + Bandit + Gitleaks + Trivy doing 80% of it.

---

## Start Here

If you've never run a security scanner before, that's fine. This directory gives you
everything you need to scan your code for vulnerabilities, secrets, and dangerous
dependencies — using free, open source tools that companies like Netflix, Airbnb, and
Shopify use in production.

**Follow the playbooks in order. Each one builds on the last.**

| # | Playbook | What You'll Do | Time |
|---|----------|---------------|------|
| 00 | [Understand Your Repo](playbooks/00-understand-your-repo.md) | Figure out what you're scanning before you scan it | 5 min |
| 01 | [Your First Scan](playbooks/01-first-scan.md) | Run all the scanners and see what they find | 15 min |
| 02 | [Reading Your Results](playbooks/02-read-your-results.md) | Understand what the findings mean and what to fix first | 10 min |
| 03 | [Add Scanning to CI](playbooks/03-add-to-ci.md) | Make GitHub Actions scan every pull request automatically | 10 min |
| 04 | [Pre-Commit Hooks](playbooks/04-pre-commit-hooks.md) | Catch secrets and bugs before they leave your machine | 5 min |
| 05 | [Track Your Progress](playbooks/05-track-progress.md) | Rescan after fixes and measure improvement | 10 min |
| 06 | [Auto-Fix with Open Source](playbooks/06-auto-fix.md) | Let tools fix deps and code patterns, review the diff | 10 min |

---

## The Tools

You don't need all of these installed to start. The scripts skip whatever's missing
and tell you how to install it.

| Tool | What It Does | One-Liner Install | Enterprise Equivalent |
|------|-------------|-------------------|----------------------|
| **Semgrep** | Finds bugs in your code (SQL injection, XSS, insecure patterns) | `pip install semgrep` | Checkmarx ($50K+/yr) |
| **Bandit** | Finds Python-specific security issues | `pip install bandit` | Fortify ($100K+/yr) |
| **Gitleaks** | Finds API keys, passwords, and tokens in your code | `brew install gitleaks` | GitGuardian ($15K+/yr) |
| **Trivy** | Finds known vulnerabilities in your dependencies | `brew install trivy` | Snyk ($25K+/yr) |
| **Grype** | Same as Trivy but uses a different vulnerability database | `brew install grype` | Mend/WhiteSource ($30K+/yr) |

Running two scanners for the same thing (Trivy + Grype) isn't redundant — they use
different databases and catch different things. A CVE that Trivy misses, Grype might
catch, and vice versa.

---

## Quick Start (Skip the Playbooks)

If you just want to scan something right now:

```bash
cd 01-code

# Scan your code for security bugs
./scan-code.sh /path/to/your/project

# Scan for hardcoded secrets (API keys, passwords)
./scan-secrets.sh /path/to/your/project

# Scan dependencies for known CVEs
./scan-dependencies.sh /path/to/your/project
```

Results land in `/path/to/your/project/.oss-copilot/code/` as JSON files.

---

## What the Big 4 Run (and What You Can Run Instead)

When GuidePoint, Deloitte, PwC, or KPMG walk into a client environment for an
application security engagement, this is the tooling they deploy. The left column
is what they charge you for. The right column is what you can run yourself today.

| Engagement Phase | What the Big 4 Use | What You Run (Free) | Coverage |
|-----------------|-------------------|---------------------|----------|
| **Secret Detection** | GitGuardian ($15-50K/yr) | Gitleaks | 90% — catches same patterns, misses historical cross-branch scanning |
| **SAST (multi-lang)** | Checkmarx ($50-200K/yr) | Semgrep | 80% — 2,000+ rules, misses cross-file dataflow analysis |
| **SAST (Python)** | Fortify ($100K+/yr) | Bandit | 85% — covers all OWASP Python patterns |
| **Dependency CVEs** | Snyk ($25-100K/yr) | Trivy + Grype | 90% — same CVE databases, misses reachability analysis |
| **License Compliance** | FOSSA ($20-60K/yr) | Trivy license scan | 70% — detects licenses, no policy engine |
| **DAST** | Burp Suite Pro ($450/yr per seat) | ZAP + Nuclei | 60% — good for OWASP Top 10, misses complex auth flows |
| **CI Integration** | Snyk (built into PR workflow) | GitHub Actions + these tools | 85% — same gates, less polish |
| **Triage & Reporting** | Custom dashboards + analysts | JSON + scripts | 50% — you do the triage manually |

### The time savings:

```
Without OSS-Copilot:
  Enterprise tool scans codebase → 500+ findings
  Team spends 2-3 weeks triaging LOW/MEDIUM noise
  Secrets and critical CVEs sit in the backlog alongside informational findings

With OSS-Copilot first:
  Open source clears routine findings in hours (secrets, dep bumps, SAST patterns)
  Enterprise tool scans same codebase → 100 findings
  Every finding needs enterprise-level analysis (dataflow, reachability)
  Team acts on signal from day 1 — weeks of triage eliminated
```

### How consultants actually use this:

1. **First meeting** — Run the scanners, show the client what's broken
2. **Triage** — Separate critical findings (secrets, CRITICAL CVEs) from noise
3. **Quick wins** — Fix the obvious stuff (secrets, dependency bumps, Dockerfile hardening)
4. **Policy gates** — Deploy CI scanning so nothing new gets introduced
5. **Deliverable** — Before/after comparison proving value

That's exactly what these playbooks walk you through — the same methodology
consultants follow, using the same open source tools they run under the hood.

---

## What These Scanners Actually Catch

**Real examples of what open source catches that would cost you $50K+/yr in enterprise tools:**

```
Gitleaks    →  AWS_ACCESS_KEY_ID = "AKIA..." hardcoded in config.py
Semgrep     →  cursor.execute("SELECT * FROM users WHERE id=" + user_input)  # SQL injection
Bandit      →  yaml.load(data)  # Should be yaml.safe_load() — remote code execution
Trivy       →  requests==2.25.0  # CVE-2023-32681 — CRITICAL, fixed in 2.31.0
Grype       →  lodash@4.17.15  # CVE-2021-23337 — prototype pollution
```

These are not theoretical findings. These are real vulnerabilities that exist in
production codebases right now.

---

## What Enterprise Does Better (the Honest 20%)

Open source catches the finding. Enterprise tools help you act on it faster.

| Gap | What Enterprise Does | Why It Matters |
|-----|---------------------|----------------|
| **Dataflow analysis** | Checkmarx traces input → function → database across files | Catches injection chains Semgrep can't see |
| **Auto-fix PRs** | Snyk opens a PR that bumps the vulnerable dependency | You fix it with one click instead of manual work |
| **IDE integration** | Snyk highlights vulnerabilities as you type in VS Code | Faster feedback loop than waiting for CI |
| **Reachability** | Snyk tells you if the vulnerable function is actually called | Reduces false positives by 60%+ |
| **Historical scanning** | GitGuardian scans all branches and git history continuously | Gitleaks scans current state; secrets in old branches get missed |

**When to buy the enterprise tool:**
- You have >50 developers and need findings surfaced in PRs, not CI logs
- You need dataflow SAST for Java/C# where injection chains span 10+ files
- Your team spends more time triaging false positives than fixing real issues
- You need license compliance tracking across hundreds of repositories

**When open source is enough:**
- Teams under 50 developers
- Projects that are primarily Python, JavaScript, Go, or Terraform
- Pre-SOC 2 environments proving basic security hygiene
- Budget under $50K/year for security tooling

---

## How This Connects to GP-Copilot

This directory is the open source version of
GP-CONSULTING/01-APP-SEC in the [GP-Copilot](https://github.com/jimjrxieb/GP-copilot) repo — the full engagement
framework with 16 scanners, 29 auto-fix scripts, and a rank-based triage system.

| You're Here (OSS-Copilot) | Full Framework (GP-Copilot) |
|---------------------------|----------------------------|
| 5 scanners | 16 scanners |
| Manual triage | Automated triage with severity classification |
| Playbooks for scanning | Playbooks for scanning + fixing + deploying |
| You fix findings yourself | Auto-fix scripts for 80% of findings |
| Evidence as JSON files | Evidence packaged for auditors |

OSS-Copilot gives you the scanning layer for free. If you need the full engagement
framework — the automated fixes, the rank-based triage, the CI templates, the
compliance mapping — that's what GP-Copilot's consulting packages are built for.
