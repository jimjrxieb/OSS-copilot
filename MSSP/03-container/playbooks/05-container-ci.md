# Playbook 05: Container Security in CI

> Block vulnerable images before they reach production.
> Scan on every build. No CRITICAL CVEs ship.
>
> **Time:** ~10 minutes
> **Prerequisites:** GitHub Actions (or any CI system)

---

## Why CI Image Scanning

You scanned your images manually in Playbook 01. That's a start. But images
need to be scanned on every build because:

1. **New CVEs are disclosed daily** — an image that was clean yesterday might
   have a CRITICAL CVE today
2. **Developers update dependencies** — a new `pip install` might pull in a
   vulnerable package
3. **Base images change** — even pinned base images get new CVE disclosures

CI scanning makes this automatic. Every time you build an image, it gets scanned.
If it has CRITICAL CVEs, the build fails. The vulnerable image never reaches
your registry.

---

## Step 1: Add Image Scanning to GitHub Actions

Create `.github/workflows/container-security.yml`:

```yaml
name: Container Security

on:
  push:
    paths:
      - 'Dockerfile*'
      - 'docker-compose*.yml'
      - 'requirements.txt'
      - 'package.json'
      - 'go.mod'
  pull_request:
    paths:
      - 'Dockerfile*'

permissions:
  contents: read
  security-events: write  # For uploading SARIF results

jobs:
  dockerfile-lint:
    name: Dockerfile Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Hadolint
        uses: hadolint/hadolint-action@v3.1.0
        with:
          dockerfile: Dockerfile
          failure-threshold: error  # Fail on errors, warn on warnings

  image-scan:
    name: Image CVE Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: docker build -t ${{ github.repository }}:${{ github.sha }} .

      - name: Trivy scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: '${{ github.repository }}:${{ github.sha }}'
          severity: CRITICAL,HIGH
          exit-code: 1               # Fail on CRITICAL or HIGH
          format: sarif
          output: trivy-results.sarif

      - name: Upload results to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: trivy-results.sarif
```

**What this does:**
- **Triggers** when Dockerfiles, dependency files, or compose files change
- **Lints** your Dockerfile with Hadolint (catches misconfigurations at build time)
- **Builds** your image from the Dockerfile
- **Scans** the built image with Trivy for CRITICAL and HIGH CVEs
- **Fails** the build if any CRITICAL or HIGH CVEs are found
- **Uploads** results to GitHub's Security tab (visible in the repo)

---

## Step 2: What Blocks vs. What Warns

| Check | Blocks Build | Warns Only |
|-------|-------------|------------|
| Hadolint ERROR rules | Yes | — |
| Hadolint WARNING rules | — | Yes |
| CRITICAL CVEs | Yes | — |
| HIGH CVEs | Yes (recommended) | Optional |
| MEDIUM CVEs | — | Yes |
| LOW CVEs | — | Ignored |

To make HIGH CVEs warn instead of block:

```yaml
# Change severity to only block on CRITICAL
severity: CRITICAL
```

---

## Step 3: Scan Before Push to Registry

If you push images to a container registry, scan before pushing:

```yaml
  build-and-push:
    name: Build, Scan, Push
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: docker build -t ghcr.io/${{ github.repository }}:${{ github.sha }} .

      - name: Scan (gate)
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'ghcr.io/${{ github.repository }}:${{ github.sha }}'
          severity: CRITICAL
          exit-code: 1

      # Only pushes if scan passes
      - name: Push to registry
        if: success()
        run: |
          echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
          docker push ghcr.io/${{ github.repository }}:${{ github.sha }}
```

**The key insight:** The scan step has `exit-code: 1`, so if Trivy finds a
CRITICAL CVE, the job fails and the push step never runs. The vulnerable image
never reaches your registry.

---

## Step 4: Multi-Stage Scanning

For projects with multiple Dockerfiles:

```yaml
  scan-all-images:
    name: Scan All Dockerfiles
    runs-on: ubuntu-latest
    strategy:
      matrix:
        dockerfile:
          - Dockerfile
          - Dockerfile.worker
          - services/api/Dockerfile
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: docker build -f ${{ matrix.dockerfile }} -t scan-target:${{ github.sha }} .

      - name: Scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'scan-target:${{ github.sha }}'
          severity: CRITICAL,HIGH
          exit-code: 1
```

---

## Step 5: Handle "No Fix Available" CVEs

Sometimes Trivy finds a CRITICAL CVE with no fix. Your options:

### Option A: Ignore specific CVEs (with justification)

Create `.trivyignore` in your repo:

```
# CVE-2024-1234: No fix available as of 2026-03-30
# Affects: libexpat 2.5.0 — XML parsing library
# Risk: Low — we don't parse untrusted XML
# Review: Monthly check for upstream fix
CVE-2024-1234
```

### Option B: Lower severity threshold

```yaml
# Only block on CRITICAL, let HIGH pass as warnings
severity: CRITICAL
```

### Option C: Use a different base image

```dockerfile
# If python:3.12-slim has unfixable CVEs, try Alpine
FROM python:3.12-alpine
```

**Always document** why you're ignoring a CVE. "No fix available" is a valid
reason. "I don't feel like fixing it" is not.

---

## Step 6: Nightly Registry Scan

Even after images pass CI, new CVEs get disclosed. Add a nightly scan:

```yaml
  nightly-scan:
    name: Nightly Registry Scan
    runs-on: ubuntu-latest
    # Only runs on schedule, not on push
    if: github.event_name == 'schedule'
    steps:
      - name: Scan production image
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'ghcr.io/your-org/your-app:latest'
          severity: CRITICAL
          exit-code: 1

on:
  schedule:
    - cron: '0 3 * * *'  # 3am UTC daily
```

This catches: "The image you deployed last week now has a CRITICAL CVE that
was disclosed yesterday."

---

## Step 7: Set Up Branch Protection

Same as code scanning — make the container security checks required:

```
GitHub → Settings → Branches → Branch protection rules

Required status checks:
  - Dockerfile Lint
  - Image CVE Scan
```

---

## The Full Container CI Pipeline

When everything is wired up:

```
Developer changes Dockerfile or dependencies
         ↓
    Hadolint lints Dockerfile
         ↓ (pass)
    Docker builds image
         ↓
    Trivy scans for CVEs
         ↓ (no CRITICAL/HIGH)
    Image pushed to registry
         ↓
    Deployed to cluster
         ↓
    Falco monitors runtime behavior
```

That's five layers of container security:
1. Dockerfile linting (build time)
2. Image scanning (CI)
3. Registry scanning (nightly)
4. Admission control (deploy time — see [02-cluster](../../02-cluster/))
5. Runtime detection (Falco — Playbook 04)

Enterprise tools bundle all five. You just built them from open source.

---

## Next Steps

- Back to the overview → [../README.md](../README.md)
- Cluster security (admission control, CIS benchmarks) → [../../02-cluster/](../../02-cluster/)
- Code scanning → [../../01-code/](../../01-code/)
