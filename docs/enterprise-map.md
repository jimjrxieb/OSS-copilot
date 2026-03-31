# Enterprise Tool → Open Source Map

The bible. Every enterprise security tool mapped to its open source equivalent,
with an honest assessment of coverage.

---

## Code Security (SAST / SCA / Secrets)

| Capability | Enterprise | Open Source | Coverage |
|-----------|-----------|-------------|----------|
| SAST (Python) | Checkmarx, Snyk Code | Semgrep, Bandit | ~80% |
| SAST (Java) | Checkmarx, Fortify | Semgrep, SpotBugs | ~70% |
| SAST (JavaScript) | Snyk Code, SonarQube | Semgrep, ESLint security | ~75% |
| SAST (Go) | Snyk Code | Semgrep, gosec | ~75% |
| Secret Detection | GitGuardian | Gitleaks, TruffleHog | ~90% |
| Dependency Scanning | Snyk, Mend (WhiteSource) | Trivy fs, Grype, pip-audit | ~85% |
| License Compliance | Snyk, FOSSA | Trivy license, syft | ~70% |
| DAST | Burp Suite, Qualys | ZAP, Nuclei | ~60% |

**Where enterprise wins:** Snyk's developer workflow integration (IDE, PR comments,
auto-fix PRs) is genuinely better than anything open source offers. GitGuardian's
historical scanning across all branches catches secrets that Gitleaks misses in
default mode. Checkmarx dataflow analysis for complex injection chains is deeper
than Semgrep pattern matching.

---

## Container Security (CWPP)

| Capability | Enterprise | Open Source | Coverage |
|-----------|-----------|-------------|----------|
| Image Scanning (CVEs) | Prisma Cloud, Snyk Container | Trivy image, Grype | ~90% |
| Dockerfile Linting | Prisma Cloud | Hadolint | ~95% |
| Base Image Hygiene | Snyk Container | Trivy, Docker Scout | ~80% |
| Runtime Protection | Prisma Cloud CWPP, Sysdig | Falco | ~70% |
| Behavioral Analysis | Sysdig Secure | Falco + custom rules | ~50% |

**Where enterprise wins:** Prisma Cloud's runtime protection includes automatic
blocking, not just alerting. Sysdig Secure's ML-based behavioral analysis catches
zero-day container escapes that rule-based Falco misses. Both provide drift
detection (runtime vs image) out of the box.

---

## Cluster Security (Kubernetes)

| Capability | Enterprise | Open Source | Coverage |
|-----------|-----------|-------------|----------|
| CIS Benchmarks | Wiz K8s, Prisma Cloud | kube-bench | ~95% |
| Misconfiguration | Wiz, Prisma Cloud | Kubescape, Polaris | ~85% |
| RBAC Analysis | Wiz | kubectl, rbac-tool | ~60% |
| Admission Control | Styra DAS | Kyverno, Gatekeeper/OPA | ~90% |
| Network Policy | Tigera (Calico Enterprise) | Calico OSS, Cilium | ~75% |
| Pod Security | Prisma Cloud | PSA (built-in), Kyverno | ~90% |

**Where enterprise wins:** Wiz's graph-based attack path analysis connects K8s
misconfigurations to cloud IAM to data exposure in a single view. No open source
tool does this. Styra DAS provides policy-as-code lifecycle management (authoring,
testing, distribution, monitoring) that raw OPA/Kyverno requires you to build
yourself.

---

## Cloud Security (CSPM / CIEM)

| Capability | Enterprise | Open Source | Coverage |
|-----------|-----------|-------------|----------|
| AWS Misconfiguration | Wiz, Prisma Cloud | Prowler | ~80% |
| Multi-Cloud Posture | Wiz, Prisma Cloud | Prowler (AWS/Azure/GCP) | ~70% |
| IaC Scanning | Snyk IaC, Prisma Cloud | Checkov, tfsec, Trivy config | ~85% |
| IAM Analysis | Wiz CIEM, Ermetic | Prowler, Parliament | ~50% |
| Attack Path | Wiz | (nothing equivalent) | ~10% |
| Data Security Posture | Wiz DSP, Prisma Cloud | (nothing equivalent) | ~5% |

**Where enterprise wins:** Wiz's agentless scanning + graph database is genuinely
unique. It maps: "this S3 bucket is public → this IAM role can read it → this EC2
instance has that role → that instance runs in this VPC → that VPC has this K8s
cluster." No open source tool builds that graph. Prowler finds the individual
misconfigurations. Wiz finds the chain.

---

## Compliance & Evidence

| Capability | Enterprise | Open Source | Coverage |
|-----------|-----------|-------------|----------|
| Control Mapping | Drata, Vanta | Manual + OPA | ~60% |
| Evidence Collection | Drata, Vanta, Anecdotes | Scripts + screenshots | ~50% |
| Continuous Monitoring | Drata, Vanta | Cron + alerting | ~40% |
| Auditor Portal | Drata, Vanta | Static reports | ~20% |

**Where enterprise wins:** Drata and Vanta automate the entire audit lifecycle —
evidence collection, control mapping, auditor access, continuous monitoring, gap
tracking. Doing this with scripts requires significant manual effort. For SOC 2
Type II or FedRAMP continuous monitoring, the enterprise tools save hundreds of
hours per audit cycle.

---

## Runtime Detection & Response (SIEM / SOAR)

| Capability | Enterprise | Open Source | Coverage |
|-----------|-----------|-------------|----------|
| Log Aggregation | Splunk, Datadog | ELK, Loki | ~80% |
| K8s Runtime Detection | Sysdig Secure | Falco | ~70% |
| Cloud Detection | Splunk, Chronicle | Falco + CloudTrail scripts | ~40% |
| Automated Response | Splunk SOAR, Palo Alto XSOAR | Custom scripts | ~30% |
| Threat Intelligence | CrowdStrike, Recorded Future | MITRE ATT&CK, AlienVault OTX | ~40% |

**Where enterprise wins:** Splunk's correlation engine across cloud, K8s, and
application logs at scale is battle-tested. Sysdig's kernel-level detection catches
things Falco's rule engine cannot express. CrowdStrike's threat intel feed is
updated hourly with IOCs that open source feeds see days later.

---

## Decision Framework

**Buy enterprise when:**
- You need attack path analysis (Wiz graph — nothing else does this)
- You need continuous compliance monitoring for SOC 2 / FedRAMP (Drata/Vanta)
- You need ML-based runtime behavioral analysis (Sysdig Secure)
- You have >50 developers and need IDE/PR integration (Snyk)
- You need multi-cloud posture management at scale (Wiz, Prisma Cloud)

**Use open source when:**
- You need basic vulnerability scanning (Trivy = Prisma Cloud for CVEs)
- You need CIS benchmarks (kube-bench = Wiz for CIS checks)
- You need admission control (Kyverno = Styra DAS for policy enforcement)
- You need secret detection (Gitleaks = GitGuardian for current branch)
- You need IaC scanning (Checkov = Snyk IaC for Terraform)
- Your budget is <$50K/year for security tooling
- You're pre-SOC 2 and need to prove basic hygiene

**Run both when:**
- Enterprise tool is deployed but team is drowning in findings
- OSS-Copilot clears the LOWs and MEDIUMs
- Enterprise tool focuses on CRITICAL and HIGH with context
- This is how you get value from the license you already bought
