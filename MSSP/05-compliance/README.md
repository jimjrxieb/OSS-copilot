# 05-Compliance — Evidence Packaging and Control Mapping

## What Drata / Vanta Does

Continuous compliance automation. Drata and Vanta connect to your cloud accounts,
identity providers, code repos, and ticketing systems. They automatically collect
evidence that maps to compliance controls (SOC 2, ISO 27001, HIPAA, FedRAMP),
track gaps, alert when controls drift out of compliance, and provide an auditor
portal where your external auditor can pull evidence without bothering your team.

## What Open Source Covers (the 80%)

| Tool | What It Does | Install |
|------|-------------|---------|
| **OPA/Conftest** | Policy-as-code — validate configs against compliance rules | `brew install conftest` |
| **Scripts (this repo)** | Map scanner findings to NIST/CIS/SOC 2 controls | Built-in |
| **kube-bench** | CIS Kubernetes Benchmark evidence | `brew install kube-bench` |
| **Prowler** | CIS AWS Benchmark evidence | `pip install prowler` |
| **OpenSCAP** | NIST SCAP content evaluation | Package manager |

## How to Run It

```bash
# Map findings to NIST 800-53 controls
./map-nist.sh /path/to/scan-results

# Package evidence for auditors
./package-evidence.sh
```

## What the Enterprise Tool Does Better (the 20%)

- **Continuous monitoring**: Drata checks compliance posture every 24 hours
  automatically. Scripts run when you remember to run them.
- **Auditor portal**: Drata gives your auditor direct, scoped access to evidence.
  Scripts produce files you email or upload to a shared drive.
- **Control mapping**: Drata maintains 1,400+ pre-mapped controls across frameworks.
  Scripts map the controls you write rules for.
- **Gap tracking**: Drata shows which controls are passing, failing, or missing
  evidence with trend lines. Scripts give you a point-in-time snapshot.
- **Integration breadth**: Drata pulls evidence from 75+ integrations (HR systems,
  ticketing, cloud, identity). Scripts cover what you automate yourself.

## When to Escalate to the Enterprise Tool

- You're preparing for **SOC 2 Type II** or **FedRAMP** — the continuous monitoring
  requirement alone justifies the tool
- Your auditor wants a **self-service portal** instead of ZIP files and spreadsheets
- You need to map across **multiple frameworks simultaneously** (SOC 2 + HIPAA + ISO 27001)
- You're spending **>40 hours per audit cycle** collecting evidence manually
- You need **historical compliance trending** for board reporting
