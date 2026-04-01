# CI/CD Templates

GitHub Actions workflows for automated FedRAMP compliance.

## Workflows

| Workflow | Controls | Triggers | Purpose |
|----------|----------|----------|---------|
| `fedramp-compliance.yml` | RA-5, SI-2, IA-5, CM-6, CA-2 | Push, PR, Weekly | Full compliance pipeline |
| `sast-analysis.yml` | RA-5 | Push, PR, Weekly | CodeQL + Semgrep static analysis |
| `container-scan.yml` | SI-2 | Push (Dockerfile changes) | Build + Trivy container scan |
| `policy-check.yml` | CM-6, AC-6 | Push (K8s/policy changes) | Conftest + Kyverno validation |

## Setup

1. Copy workflows to `.github/workflows/` in your repo
2. Replace `{{TARGET_DIR}}` with your application directory path
3. Replace `{{APP_NAME}}` in container-scan.yml with your image name
4. Ensure GitHub Actions is enabled for your repository

## Placeholders

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{TARGET_DIR}}` | Application directory | `src/` or `app/` |
| `{{APP_NAME}}` | Image name for container registry | `acme-api` |
