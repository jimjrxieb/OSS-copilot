# Scanning Configurations

FedRAMP-aligned scanner configurations for vulnerability detection and NIST 800-53 mapping.

## Files

| Config | Scanner | Controls | Purpose |
|--------|---------|----------|---------|
| `trivy-fedramp.yaml` | Trivy | SI-2, CM-8 | CVE scanning, SBOM generation |
| `semgrep-fedramp.yaml` | Semgrep | RA-5, SI-2 | Static analysis (SQLi, XSS, injection) |
| `gitleaks-fedramp.toml` | Gitleaks | IA-5 | Secret and credential detection |

## Customization

Replace `{{TARGET_DIR}}` placeholders with the client's application directory path.

### Trivy
```bash
trivy fs --config 01-scanning-configs/trivy-fedramp.yaml /path/to/app
```

### Semgrep
```bash
semgrep --config 01-scanning-configs/semgrep-fedramp.yaml /path/to/app
```

### Gitleaks
```bash
gitleaks detect --source /path/to/app --config 01-scanning-configs/gitleaks-fedramp.toml
```
