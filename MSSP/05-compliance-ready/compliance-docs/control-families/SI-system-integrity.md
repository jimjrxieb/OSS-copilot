# SI — System and Information Integrity

## SI-2: Flaw Remediation

**Requirement**: Identify, report, and correct information system flaws. Install security-relevant software and firmware updates.

**Implementation**:
- **Container Image Scanning**: Trivy scans for known CVEs in base images and dependencies on every build
- **Automated Patching**: CI pipeline auto-fixes dependency vulnerabilities (E-D rank)
- **Image Freshness**: CI pipeline alerts on images older than 30 days
- **Dependency Updates**: Trivy + Grype check dependency manifests for vulnerable packages
- **Remediation Tracking**: All findings logged to POA&M with remediation timeline

**Remediation Workflow**:
```
Trivy scan → CVE detected
  → gap-analysis.py determines severity (E-S)
  → E-D rank: Auto-remediate (dependency upgrade, base image update)
  → C rank: Security review and approval
  → B-S rank: Human review required
  → Verification scan confirms fix
  → Evidence generated → POA&M updated
```

**Evidence**:
- `01-scanning-configs/trivy-fedramp.yaml` — Trivy scanning configuration
- `{{EVIDENCE_DIR}}/trivy-latest.json` — Trivy scan results
- `{{EVIDENCE_DIR}}/verification-scan.json` — Post-fix verification
- `{{EVIDENCE_DIR}}/remediation/` — Detailed remediation reports
- `04-remediation/image-security.yaml` — Image security templates

**Tooling**:
- **CI Pipeline**: Runs Trivy/Grype scans, auto-fixes E-D rank CVEs
- **Assessment Pipeline**: Approves C-rank remediations, tracks in POA&M
- **Runtime Monitoring**: Monitors running containers for newly disclosed CVEs

---

## SI-3: Malicious Code Protection

**Requirement**: Implement malicious code protection mechanisms at information system entry and exit points to detect and eradicate malicious code.

**Implementation**:
- Container image scanning: Trivy scans all images for known malware, trojans, and vulnerabilities at build time
- Registry admission: only images from approved registries allowed (Kyverno policy)
- Runtime detection: Falco monitors for malicious patterns (crypto mining, reverse shells, data exfiltration)
- CI pipeline blocks images with CRITICAL CVEs from deployment
- SBOM generation tracks all components for supply chain verification

**Evidence**:
- `ci-templates/container-scan.yml` — Automated image scanning in CI
- `01-scanning-configs/trivy-fedramp.yaml` — Trivy configuration
- Falco rule sets for malware detection
- `{{EVIDENCE_DIR}}/trivy-latest.json` — Most recent image scan results
- `{{EVIDENCE_DIR}}/sbom.json` — Software bill of materials

**Tooling**:
- **CI Pipeline**: Trivy scanning at build time (D-rank auto-block on CRITICAL)
- **Runtime Monitoring**: Falco runtime monitoring for malicious behavior
- **Assessment Pipeline**: Escalates novel malware patterns as B-rank findings

---

## SI-4: Information System Monitoring

**Requirement**: Monitor the information system to detect attacks, indicators of potential attacks, unauthorized connections, and system integrity violations.

**Implementation**:
- Falco DaemonSet: syscall-level monitoring on every node (shell in container, privilege escalation, sensitive file access)
- Kubescape: continuous K8s configuration posture monitoring
- Prometheus: metric collection for anomaly detection (pod restarts, resource spikes, error rates)
- Grafana dashboards: security posture visualization, incident timeline
- Alert routing: PagerDuty/Slack integration for real-time notification
- Kubescape scheduled scans: weekly compliance posture assessment

**Evidence**:
- `03-RUNTIME-SECURITY/ENGAGEMENT-GUIDE.md` — Runtime monitoring deployment guide
- Falco deployment manifests and custom rules
- `05-JADE-SRE/dashboards/` — Grafana dashboard definitions
- `{{EVIDENCE_DIR}}/monitoring-config/` — Prometheus alert rules, Falco rules
- `{{EVIDENCE_DIR}}/incident-logs/` — Historical alert data

**Tooling**:
- **Runtime Monitoring**: Primary monitoring layer — runs Falco, watches cluster state
- **Assessment Pipeline**: Aggregates monitoring data for trend analysis and reporting
- **Risk Prioritization**: Categorizes alert severity for routing
