# Playbook 02: Reading Your Results

> Learn what the scanners found, what it means, and what to fix first.
>
> **Time:** 10 minutes
> **Prerequisites:** You've run [01-first-scan.md](01-first-scan.md)

---

## The Priority Order

Not all findings are equal. Fix them in this order:

```
1. SECRETS        ← Fix TODAY. Someone might already have your API key.
2. CRITICAL CVEs  ← Fix this week. Known exploits exist.
3. HIGH SAST      ← Fix this week. SQL injection, command injection.
4. HIGH CVEs      ← Fix this sprint. Vulnerabilities, no known exploit yet.
5. MEDIUM         ← Fix over time. Real issues, lower risk.
6. LOW/INFO       ← Nice to fix. Not urgent.
```

This isn't arbitrary — it's based on exploitability. A hardcoded AWS key can be
exploited in 5 minutes by anyone who finds it. A LOW severity CVE in a transitive
dependency might never be exploitable in your context.

---

## Reading Gitleaks Results (Secrets)

```bash
# Pretty-print the findings
python3 -c "
import json
data = json.load(open('.oss-copilot/code/gitleaks-results.json'))
if not data:
    print('No secrets found!')
else:
    for f in (data if isinstance(data, list) else []):
        print(f'  Rule:   {f.get(\"RuleID\", \"unknown\")}')
        print(f'  File:   {f.get(\"File\", \"unknown\")}:{f.get(\"StartLine\", \"?\")}')
        print(f'  Secret: {f.get(\"Secret\", \"\")[:20]}...')
        print()
"
```

### What to do with each finding:

| Rule | What It Found | What to Do |
|------|--------------|------------|
| `aws-access-token` | AWS Access Key ID | Rotate in AWS IAM Console **immediately** |
| `private-key` | Private key (SSH, TLS) | Regenerate the key, remove from code |
| `generic-api-key` | API key or token | Rotate with the provider, move to env var |
| `password` | Hardcoded password | Change the password, use a secrets manager |

**Every secret found means:**
1. Rotate the credential **right now** (assume it's compromised)
2. Remove it from code — use environment variables instead:
   ```python
   # Bad:  API_KEY = "sk-1234567890abcdef"
   # Good: API_KEY = os.environ["API_KEY"]
   ```
3. Add a `.env` file (gitignored) for local development
4. Use GitHub Secrets or your cloud's secrets manager for CI/CD

---

## Reading Semgrep Results (Code Vulnerabilities)

```bash
# Show findings grouped by severity
python3 -c "
import json
data = json.load(open('.oss-copilot/code/semgrep-results.json'))
results = data.get('results', [])
if not results:
    print('No code vulnerabilities found!')
else:
    by_severity = {}
    for r in results:
        sev = r.get('extra', {}).get('severity', 'UNKNOWN')
        by_severity.setdefault(sev, []).append(r)
    for sev in ['ERROR', 'WARNING', 'INFO']:
        findings = by_severity.get(sev, [])
        if findings:
            print(f'\n=== {sev} ({len(findings)} findings) ===')
            for f in findings[:5]:
                print(f'  {f[\"check_id\"]}')
                print(f'    {f[\"path\"]}:{f[\"start\"][\"line\"]}')
                print(f'    {f.get(\"extra\", {}).get(\"message\", \"\")[:100]}')
                print()
"
```

### Common findings and what they mean:

| Finding | Risk | Plain English |
|---------|------|--------------|
| `python.lang.security.audit.dangerous-system-call` | **HIGH** | Your code runs shell commands with user input — an attacker could inject commands |
| `python.lang.security.deserialization.avoid-pickle` | **HIGH** | Pickle can execute arbitrary code when loading untrusted data |
| `python.lang.security.audit.insecure-hash.use-of-md5` | **MEDIUM** | MD5 is broken for security — use SHA-256 instead |
| `javascript.lang.security.audit.sqli.sql-injection` | **HIGH** | SQL query built with string concatenation — use parameterized queries |
| `generic.secrets.security.detected-generic-secret` | **HIGH** | Something that looks like a hardcoded secret |

**For each finding, Semgrep tells you:**
- The file and line number (where the problem is)
- A message explaining the issue (what's wrong)
- A link to the rule documentation (how to fix it)

---

## Reading Trivy/Grype Results (Dependency CVEs)

```bash
# Show CRITICAL and HIGH CVEs
python3 -c "
import json
data = json.load(open('.oss-copilot/code/trivy-deps-results.json'))
for result in data.get('Results', []):
    vulns = result.get('Vulnerabilities', [])
    if vulns:
        print(f'=== {result.get(\"Target\", \"unknown\")} ===')
        for v in sorted(vulns, key=lambda x: x.get('Severity', ''), reverse=True)[:10]:
            fixed = v.get('FixedVersion', 'no fix yet')
            print(f'  [{v[\"Severity\"]}] {v[\"VulnerabilityID\"]}')
            print(f'    Package: {v.get(\"PkgName\", \"?\")} {v.get(\"InstalledVersion\", \"?\")}')
            print(f'    Fix: upgrade to {fixed}')
            print()
"
```

### What the severities mean:

| Severity | What It Means | Action |
|----------|--------------|--------|
| **CRITICAL** | Known exploit exists. Attackers are actively using this. | Upgrade this week |
| **HIGH** | Vulnerability confirmed, exploit likely possible. | Upgrade this sprint |
| **MEDIUM** | Vulnerability confirmed, exploit requires specific conditions. | Plan to upgrade |
| **LOW** | Minor issue or theoretical attack. | Upgrade when convenient |

### The "no fix yet" problem:

Some CVEs have no fix available — the maintainers haven't released a patch yet.
For these:
- Check if the vulnerable code path is actually used in your application
- Check if there's an alternative package
- Document it as "accepted risk — monitoring for fix" and move on
- This is where Snyk's reachability analysis helps (it tells you if the vulnerable
  function is actually called in your code)

---

## Reading Bandit Results (Python-Specific)

```bash
# Show HIGH severity findings
python3 -c "
import json
data = json.load(open('.oss-copilot/code/bandit-results.json'))
results = data.get('results', [])
high = [r for r in results if r.get('issue_severity') == 'HIGH']
print(f'HIGH findings: {len(high)}')
for r in high[:10]:
    print(f'  [{r[\"test_id\"]}] {r[\"issue_text\"]}')
    print(f'    {r[\"filename\"]}:{r[\"line_number\"]}')
    print()
"
```

### Bandit error codes cheat sheet:

| Code | What It Is | Risk | Quick Fix |
|------|-----------|------|-----------|
| B303 | Using MD5 or SHA1 | Medium | Replace with `hashlib.sha256()` |
| B311 | Using `random` for security | Medium | Use `secrets` module instead |
| B602 | `subprocess` with `shell=True` | High | Use `subprocess.run(["cmd", "arg"])` (list form) |
| B301 | Using `pickle.loads` | High | Use `json.loads` for untrusted data |
| B506 | Using `yaml.load` | High | Use `yaml.safe_load` instead |
| B608 | SQL injection risk | High | Use parameterized queries |
| B105 | Hardcoded password | High | Move to environment variable |

---

## Making Sense of It All

After reading your results, you should be able to fill in this summary:

```markdown
## My Security Baseline

Scan date: ___________

Secrets found:           ___  (fix today)
CRITICAL dependency CVEs: ___  (fix this week)
HIGH code findings:       ___  (fix this week)
HIGH dependency CVEs:     ___  (fix this sprint)
MEDIUM findings:          ___  (fix over time)
LOW/INFO findings:        ___  (nice to have)

Total:                    ___
```

Write this down. It's your "before" picture. When you rescan after fixing things,
you'll compare against these numbers.

---

## Next Steps

- Add automated scanning to your CI pipeline → [03-add-to-ci.md](03-add-to-ci.md)
- Set up pre-commit hooks to catch issues early → [04-pre-commit-hooks.md](04-pre-commit-hooks.md)
- Rescan after fixing to prove improvement → [05-track-progress.md](05-track-progress.md)
