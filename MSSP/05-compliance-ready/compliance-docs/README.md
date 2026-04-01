# Compliance Templates

FedRAMP compliance documentation templates for SSP, POA&M, SAR, and NIST 800-53 control families.

## Files

| Template | Purpose | FedRAMP Artifact |
|----------|---------|-----------------|
| `ssp-skeleton.md` | System Security Plan | Core ATO document |
| `system-description.md` | System Description | SSP Section 1 |
| `authorization-boundary.md` | Authorization Boundary | SSP Section 4 |
| `poam-template.md` | Plan of Action & Milestones | Tracks open findings |
| `sar-template.md` | Security Assessment Report | 3PAO deliverable |
| `control-matrix-template.md` | Controls traceability matrix | Evidence mapping |
| `control-families/` | 8 NIST family detail files | SSP appendix |

## Usage

1. Copy this directory into your client engagement repo
2. Replace placeholders with client-specific values
3. Link evidence paths to actual scan artifacts

## Placeholders

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{CLIENT_NAME}}` | Organization name | Acme Corp |
| `{{APP_NAME}}` | Application name | AcmeApp |
| `{{NAMESPACE}}` | Kubernetes namespace | acme-prod |
| `{{EVIDENCE_DIR}}` | Evidence directory | evidence/scan-reports |
| `{{DATE}}` | Document date | 2026-02-10 |
| `{{SYSTEM_DESCRIPTION}}` | System overview text | web-based fintech platform |

## Quick Setup

```bash
cp -r 02-compliance-docs/ my-client/compliance/
find my-client/compliance/ -name "*.md" -exec sed -i 's/{{CLIENT_NAME}}/Acme Corp/g' {} \;
find my-client/compliance/ -name "*.md" -exec sed -i 's/{{APP_NAME}}/AcmeApp/g' {} \;
```
