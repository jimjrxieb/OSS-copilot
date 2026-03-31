# Prisma Cloud Integration

> Forward Checkov findings to Prisma Cloud via SARIF, or fix first
> so Prisma sees a clean environment on its own scan.

---

## What Prisma Cloud Expects

Prisma Cloud (by Palo Alto Networks) accepts findings via:
1. **Checkov native integration** — Checkov is built by Prisma Cloud's team (Bridgecrew). It outputs Prisma-compatible format natively.
2. **SARIF format** — Standard format for static analysis results. Prisma Cloud's API accepts SARIF uploads.
3. **API** — Prisma Cloud Compute REST API for programmatic finding submission.

---

## How to Format Your Findings

### Checkov → Prisma Cloud (native — easiest)

Checkov was built by Bridgecrew (acquired by Palo Alto/Prisma). The integration
is native — Checkov can push results directly to Prisma Cloud.

```bash
# Checkov with Prisma Cloud API key
checkov \
    --directory /path/to/terraform \
    --bc-api-key $PRISMA_API_KEY \
    --repo-id your-org/your-repo

# This pushes results directly to Prisma Cloud Code Security dashboard
```

### Semgrep/Trivy → SARIF → Prisma Cloud

```bash
# Generate SARIF from Semgrep
semgrep scan --config=auto --sarif --output findings.sarif /path/to/repo

# Generate SARIF from Trivy
trivy fs --format sarif --output findings.sarif /path/to/repo

# Upload SARIF to Prisma Cloud via API
curl -X POST "https://api.prismacloud.io/code/api/v1/scans" \
    -H "Authorization: Bearer $PRISMA_TOKEN" \
    -H "Content-Type: application/json" \
    -d @findings.sarif
```

---

## The Command

### Full pipeline: Scan → Format → Push

```bash
TARGET=/path/to/your/project

# 1. Checkov IaC scan → Prisma Cloud (native)
checkov \
    --directory "$TARGET" \
    --bc-api-key "$PRISMA_API_KEY" \
    --repo-id "my-org/my-repo" \
    --framework terraform kubernetes

# 2. Semgrep SAST → SARIF
semgrep scan --config=auto --sarif --output semgrep.sarif "$TARGET"

# 3. Trivy deps → SARIF
trivy fs --format sarif --output trivy.sarif "$TARGET"
```

### Using Existing OSS-Copilot Output

If you already ran the MSSP scans and have JSON output in `example-output/`,
the JSON is for local review. For Prisma Cloud, re-run with SARIF format:

```bash
# Your existing output (JSON — for local review)
MSSP/example-output/01-code/semgrep-results.json    # SAST findings
MSSP/example-output/01-code/trivy-deps-results.json  # dependency CVEs
MSSP/example-output/02-cluster/checkov-results.json   # IaC findings

# Re-run with SARIF/Prisma format (for Prisma Cloud)
semgrep scan --config=auto --sarif --output semgrep.sarif /path/to/project
trivy fs --format sarif --output trivy.sarif /path/to/project
checkov --directory /path/to/infrastructure --bc-api-key "$PRISMA_API_KEY" --repo-id "my-org/my-repo"
```

**The pattern:** Run once with JSON for your review. Run again with SARIF/native
for the enterprise tool. Or add `--sarif` to your CI pipeline so both formats
are generated on every scan.

---

## What It Looks Like in Prisma Cloud

```
Prisma Cloud → Code Security → Supply Chain

┌──────────────────────────────────────────────────────┐
│ Repository: my-org/my-repo                           │
│ Source: Checkov                                       │
│                                                      │
│ IaC Misconfigurations: 16                            │
│   CRITICAL: 0  HIGH: 4  MEDIUM: 8  LOW: 4           │
│                                                      │
│ Vulnerabilities: 70                                  │
│   CRITICAL: 7  HIGH: 32  MEDIUM: 27  LOW: 4         │
│                                                      │
│ Secrets: 7                                           │
└──────────────────────────────────────────────────────┘
```

Your open source findings appear in Prisma Cloud's dashboard alongside
Prisma's own findings. Security teams see one view.

---

## When to Use This vs. Fix First

| Scenario | Forward to Prisma | Fix First |
|----------|------------------|-----------|
| Client already pays for Prisma Cloud | Yes — consolidate reporting | Both |
| Proving coverage overlap | Yes — shows OSS catches same findings | No |
| Pre-engagement cleanup | No | Yes — Prisma sees clean env |
| Compliance evidence | Yes — one dashboard for auditors | Both |

**The power move:** Fix routine findings with OSS-Copilot — the secrets, the
dependency bumps, the missing security contexts. Push the remaining complex
and critical findings to Prisma Cloud. The client's Prisma dashboard shows
only the hard problems — no noise, all signal. That's how you make a $200K/yr
license actually earn its cost.

---

## Without Prisma Cloud API Access

If you don't have API keys (common in pre-sales or assessments):

```bash
# Generate SARIF files and hand them to the client's Prisma admin
checkov --directory /path/to/terraform --output sarif --output-file-path ./
semgrep scan --config=auto --sarif --output semgrep.sarif /path/to/repo

# Client uploads manually:
# Prisma Cloud → Settings → Code Security → Add Repository → Upload SARIF
```
