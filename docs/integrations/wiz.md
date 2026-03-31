# Wiz Integration

> Wiz is read-only — it scans your environment, you don't send it findings.
> The integration is Workflow B: fix first, Wiz sees a clean environment.

---

## What Wiz Expects

Nothing from you. Wiz connects to your AWS/Azure/GCP accounts via read-only
API access and scans everything itself. You can't push findings to Wiz.

**This makes Wiz the perfect Workflow B candidate:** Fix the noise with open
source, and when Wiz runs its own scan, it finds only the hard problems.

---

## The Fix First Workflow

```
Step 1: Run OSS-Copilot
  01-code scanners  → fix secrets, CVEs, SAST findings
  02-cluster audit  → fix securityContext, RBAC, admission control
  03-container scan → fix Dockerfile issues, image CVEs
  04-cloud scan     → fix AWS misconfigurations (Prowler)

Step 2: Wiz runs its own scan
  Wiz scans the same environment
  Wiz sees 400 findings instead of 2,847
  Every finding is signal, not noise
  The security team can actually act on what's left

Step 3: What Wiz catches that OSS didn't
  Attack paths (K8s misconfig → IAM → S3 with PII)
  CIEM (effective permissions across trust chains)
  DSPM (sensitive data classification)
  These are Wiz's 20% — the reason the license exists
```

---

## Before and After

### Without OSS-Copilot first:

```
Wiz Dashboard:
  CRITICAL:  47
  HIGH:      312
  MEDIUM:    1,208
  LOW:       1,280
  Total:     2,847

Security team reaction: "Where do we even start?"
Wiz license ROI: Questionable — they're drowning in LOW/MEDIUM
```

### With OSS-Copilot first:

```
OSS-Copilot fixed:
  Secrets rotated:           7 → 0
  CRITICAL CVEs patched:     7 → 0
  K8s misconfigs fixed:      47 → 3
  Dockerfiles hardened:      12 → 0
  RBAC scoped:               3 wildcard roles → 0

Wiz Dashboard (same environment, after fixes):
  CRITICAL:  3  (attack paths only Wiz can see)
  HIGH:      28 (cross-domain risks)
  MEDIUM:    189
  LOW:       180
  Total:     400

Security team reaction: "These are all real. Let's triage."
Wiz license ROI: Clear — it's finding things OSS can't
```

---

## What Wiz Catches That Open Source Can't

This is the honest 20% — and it's genuine value:

| Wiz Capability | What It Does | Why OSS Can't |
|----------------|-------------|---------------|
| **Attack paths** | "This public S3 bucket → accessible via this Lambda → triggered by unauthenticated API Gateway" | Requires cross-service graph that no OSS tool builds |
| **CIEM** | Resolves effective permissions across role chains, trust policies, and resource policies | Requires IAM policy simulation at scale |
| **DSPM** | Scans S3/RDS/DynamoDB for PII, PHI, credentials | No OSS equivalent for data classification |
| **Agentless scanning** | Reads EBS snapshots, no agent deployment | Trivy/Kubescape need access to the running environment |

**Don't compete with these.** Fix everything OSS can fix, and let Wiz earn its
license by finding what only it can find.

---

## When to Use This Approach

| Scenario | Fix First + Wiz |
|----------|----------------|
| Client just bought Wiz, team overwhelmed | Yes — reduce noise so Wiz's findings are actionable |
| Pre-Wiz deployment | Yes — cleaner baseline = better first impression |
| Wiz POC/evaluation | Yes — Wiz looks better when it finds 400 vs. 2,847 |
| Proving OSS-Copilot value alongside Wiz | Yes — before/after numbers tell the story |

---

## The Pitch to the Client

> "Wiz is excellent at attack path analysis and cross-service risk.
> But right now it's showing 2,800 findings and your team can't prioritize.
> Let us clear the routine findings — the secrets, the CVEs, the
> missing security contexts. That's what open source covers. Then Wiz
> shows you the 400 findings that actually need Wiz-level analysis.
> We're not replacing Wiz. We're making it useful."

That's the MSSP value proposition in one paragraph.
