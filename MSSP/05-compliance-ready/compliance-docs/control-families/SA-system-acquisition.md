# SA — System and Services Acquisition

## SA-10: Developer Configuration Management

**Requirement**: Require developers to perform configuration management during system development, manage and control changes.

**Implementation**:
- All infrastructure-as-code tracked in Git with full change history
- Branch protection: require PR review + CI pass before merge to main
- Gitleaks pre-commit hooks prevent secrets from entering the repository
- CI pipeline runs security scans on every PR (Semgrep, Trivy, Conftest)
- Configuration drift detection: Kubescape compares runtime state to declared IaC

**Evidence**:
- `ci-templates/fedramp-compliance.yml` — CI pipeline configuration
- Git branch protection settings
- Pre-commit config
- `{{EVIDENCE_DIR}}/ci-scan-logs/` — CI scan execution logs

**Tooling**:
- **CI Pipeline**: Validates configs pre-deploy via CI pipeline scans
- **Runtime Monitoring**: Detects configuration drift post-deploy by comparing runtime state to IaC

---

## SA-11: Developer Testing and Evaluation

**Requirement**: Require developers to create and implement security assessment plan, perform unit/integration/system testing, produce evidence of execution.

**Implementation**:
- SAST (Semgrep) runs on every PR — blocks merge on ERROR findings
- Dependency scanning (Trivy FS) runs on every PR — blocks on CRITICAL CVEs
- Secret detection (Gitleaks) runs on every PR — blocks on any finding
- Policy validation (Conftest) runs on every PR — validates K8s manifests against OPA policies
- Container scanning (Trivy image) runs on every build — CRITICAL CVEs block deployment
- All scan results mapped to NIST 800-53 controls via scan-and-map.py

**Evidence**:
- `ci-templates/sast-analysis.yml` — SAST pipeline definition
- `ci-templates/container-scan.yml` — Container scan pipeline definition
- CI run logs
- `{{EVIDENCE_DIR}}/scan-reports/` — Scan result archives

**Tooling**:
- **CI Pipeline**: Operates the full testing pipeline across all scan types
