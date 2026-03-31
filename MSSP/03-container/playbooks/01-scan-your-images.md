# Playbook 01: Scan Your Images

> Find known vulnerabilities in your container images before attackers do.
>
> **Time:** ~10 minutes
> **Prerequisites:** Trivy installed (`brew install trivy`)

---

## Why Image Scanning Matters

Every container image ships with an operating system and packages. Those packages
have vulnerabilities. New CVEs are disclosed daily. An image that was clean last
month might have 5 CRITICAL CVEs today — without you changing a single line of code.

Image scanning is the container equivalent of dependency scanning (01-code). But
instead of scanning `requirements.txt`, you're scanning the entire OS layer.

---

## Step 1: Install the Scanners

```bash
# Primary scanner (required)
brew install trivy

# Second opinion (recommended — different vulnerability database)
brew install grype
```

---

## Step 2: Scan an Image

### Scan a specific image:

```bash
# From the 03-container directory
./scan-images.sh nginx:1.25 python:3.12-slim my-app:latest
```

### Or scan directly with Trivy:

```bash
# Basic scan — shows all severities
trivy image nginx:1.25

# Focus on what matters — CRITICAL and HIGH only
trivy image --severity CRITICAL,HIGH nginx:1.25

# JSON output for processing
trivy image --format json --output results.json nginx:1.25
```

### Example output:

```
nginx:1.25 (debian 12.4)

Total: 127 (UNKNOWN: 0, LOW: 85, MEDIUM: 28, HIGH: 11, CRITICAL: 3)

┌──────────────────┬──────────────────┬──────────┬────────────────┬─────────────────┐
│     Library      │  Vulnerability   │ Severity │ Installed Ver  │   Fixed Version │
├──────────────────┼──────────────────┼──────────┼────────────────┼─────────────────┤
│ libssl3          │ CVE-2024-5535    │ CRITICAL │ 3.0.11-1       │ 3.0.13-1        │
│ curl             │ CVE-2024-2398    │ HIGH     │ 7.88.1-10+deb  │ 7.88.1-10+deb12 │
│ zlib1g           │ CVE-2023-45853   │ CRITICAL │ 1:1.2.13.dfsg  │ 1:1.2.13.dfsg-2 │
└──────────────────┴──────────────────┴──────────┴────────────────┴─────────────────┘
```

---

## Step 3: Understand the Results

### What the columns mean:

| Column | What It Tells You |
|--------|------------------|
| **Library** | The OS or application package with the vulnerability |
| **Vulnerability** | The CVE ID — search this on [nvd.nist.gov](https://nvd.nist.gov/) for details |
| **Severity** | CRITICAL > HIGH > MEDIUM > LOW |
| **Installed Version** | What's in your image right now |
| **Fixed Version** | What version fixes it (empty = no fix yet) |

### What the severities mean for containers:

| Severity | What It Means | Action |
|----------|--------------|--------|
| **CRITICAL** | Remote code execution, container escape, data theft | Update base image this week |
| **HIGH** | Privilege escalation, significant info disclosure | Update base image this sprint |
| **MEDIUM** | Requires specific conditions to exploit | Update when convenient |
| **LOW** | Theoretical or minimal impact | Ignore unless easy to fix |

### The 127-findings panic:

Don't freak out if you see 100+ findings. Most container images ship with a full
Debian or Ubuntu OS. That OS has hundreds of packages, and some always have known
CVEs.

**The fix is almost always:** update your base image.

```dockerfile
# Before: old base image with 127 CVEs
FROM nginx:1.25

# After: updated base image, most CVEs gone
FROM nginx:1.27
```

That one-line change might eliminate 90% of your findings.

---

## Step 4: Scan with Grype (Second Opinion)

```bash
# Grype uses a different vulnerability database
grype nginx:1.25

# Show only fixable vulnerabilities
grype nginx:1.25 --only-fixed
```

Trivy and Grype use different vulnerability databases (Trivy uses its own + NVD,
Grype uses Anchore's database). Running both catches things the other misses.

---

## Step 5: Scan All Your Images

### If you have a cluster:

```bash
# Scan every unique image in your cluster
./scan-images.sh
# (with no arguments, it auto-discovers images from kubectl)
```

### If you have local images:

```bash
# List your images and scan them
docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | while read img; do
    echo "=== Scanning: $img ==="
    trivy image --severity CRITICAL,HIGH --quiet "$img"
    echo ""
done
```

---

## Step 6: Save Your Baseline

```bash
# Save results for comparison later
BASELINE_DIR=".oss-copilot/container-baseline-$(date +%Y%m%d)"
mkdir -p "$BASELINE_DIR"

# Scan your key images and save results
for img in nginx:1.25 python:3.12-slim my-app:latest; do
    SAFE=$(echo "$img" | tr '/:' '_')
    trivy image --format json --output "$BASELINE_DIR/trivy-${SAFE}.json" "$img" 2>/dev/null
    echo "Saved: $BASELINE_DIR/trivy-${SAFE}.json"
done
```

---

## Quick Wins

Before diving into playbook 02, here are fixes you can do right now:

**1. Update your base image:**
```dockerfile
# Check for the latest version of your base
docker pull python:3.12-slim  # Will pull the latest patch
```

**2. Use Alpine or slim variants:**
```dockerfile
# Full image: ~900MB, ~300 packages, ~100 CVEs
FROM python:3.12

# Slim image: ~150MB, ~100 packages, ~30 CVEs
FROM python:3.12-slim

# Alpine image: ~50MB, ~20 packages, ~5 CVEs
FROM python:3.12-alpine
```

**3. Use multi-stage builds (no build tools in production):**
```dockerfile
# Build stage — has compilers, dev headers
FROM python:3.12 AS builder
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Production stage — minimal
FROM python:3.12-slim
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY . .
CMD ["python", "app.py"]
```

---

## Next Steps

- Harden your Dockerfiles → [02-harden-your-dockerfiles.md](02-harden-your-dockerfiles.md)
- Check running containers → [03-check-running-containers.md](03-check-running-containers.md)
