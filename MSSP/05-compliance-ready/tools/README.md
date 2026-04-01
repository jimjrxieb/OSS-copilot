# FedRAMP Tools

## scan-and-map.py

Runs security scanners (Trivy, Semgrep, Gitleaks) against a target application and maps findings to NIST 800-53 controls with severity-based prioritization.

### Usage

```bash
# Full scan
python scan-and-map.py --client-name "Acme Corp" --target-dir /path/to/app

# Dry run (show what would execute)
python scan-and-map.py --client-name "Acme Corp" --target-dir /path/to/app --dry-run

# Custom output directory
python scan-and-map.py --client-name "Acme Corp" --target-dir /path/to/app --output-dir ./my-evidence

# Custom Semgrep rules
python scan-and-map.py --client-name "Acme Corp" --target-dir /path/to/app --semgrep-config ./custom-rules.yaml
```

### Prerequisites

Install the scanners:

```bash
# Trivy (container/IaC scanner)
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh

# Semgrep (SAST)
pip install semgrep

# Gitleaks (secret detection)
brew install gitleaks  # or download from GitHub releases
```

### Output

Generates `nist-mapping-report.json` with:
- Each finding mapped to NIST 800-53 controls
- Severity-based prioritization (E-S)
- Aggregations by rank, control, and family

### FedRAMP Controls

- **CA-2**: Security Assessments (the scan itself)
- **RA-5**: Vulnerability Monitoring (what the scanners find)
