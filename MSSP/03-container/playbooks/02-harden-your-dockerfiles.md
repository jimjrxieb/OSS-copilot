# Playbook 02: Harden Your Dockerfiles

> The cheapest place to fix container security is at build time.
> Every fix here prevents a finding in production.
>
> **Time:** ~15 minutes
> **Prerequisites:** Hadolint installed (`brew install hadolint`)

---

## Why Dockerfile Hardening Matters

A Dockerfile is a recipe for building your container. If the recipe is bad,
every container built from it inherits the problems. Fix the Dockerfile once,
and every deployment after that is secure by default.

This is **shift-left** in action — fixing at the source instead of detecting
in production.

---

## Step 1: Lint Your Dockerfiles

```bash
# From the 03-container directory
./scan-dockerfile.sh /path/to/your/project

# Or directly with Hadolint
hadolint Dockerfile
```

### Example output:

```
Dockerfile:1 DL3007 warning: Using latest is prone to errors
Dockerfile:3 DL3008 warning: Pin versions in apt-get install
Dockerfile:3 DL3015 info: Avoid additional packages with apt-get
Dockerfile:12 DL3002 warning: Last USER should not be root
```

---

## Step 2: The Top 10 Dockerfile Fixes

These are the most common issues Hadolint finds, what they mean, and exactly
how to fix them. They're ordered by impact.

### 1. Run as Non-Root (DL3002) — CRITICAL

**The problem:** By default, containers run as root. If an attacker breaks into
your container, they have root access.

```dockerfile
# BAD: no USER instruction — runs as root
FROM python:3.12-slim
COPY . .
CMD ["python", "app.py"]

# GOOD: create and use a non-root user
FROM python:3.12-slim
RUN groupadd -r appuser && useradd -r -g appuser appuser
COPY --chown=appuser:appuser . .
USER appuser
CMD ["python", "app.py"]
```

**For Alpine images:**
```dockerfile
RUN addgroup -S appuser && adduser -S appuser -G appuser
USER appuser
```

### 2. Pin Base Image Versions (DL3007) — HIGH

**The problem:** `:latest` means you don't know what version you're building on.
A rebuild next week might use a completely different base.

```dockerfile
# BAD: what version is this?
FROM python:latest
FROM node:lts

# GOOD: pinned to specific version
FROM python:3.12.3-slim
FROM node:20.11.1-alpine

# BEST: pinned to digest (immutable — can't be overwritten)
FROM python:3.12.3-slim@sha256:abc123...
```

### 3. Pin Package Versions (DL3008) — MEDIUM

```dockerfile
# BAD: installs whatever version is current
RUN apt-get install -y curl

# GOOD: pinned version, reproducible builds
RUN apt-get install -y curl=7.88.1-10+deb12u5

# ACCEPTABLE: at minimum, avoid recommends
RUN apt-get install -y --no-install-recommends curl
```

### 4. Clean Up Package Manager Cache (DL3009) — MEDIUM

```dockerfile
# BAD: apt cache stays in the image (adds ~30MB)
RUN apt-get update && apt-get install -y curl

# GOOD: clean up in the same layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*
```

### 5. Add a HEALTHCHECK — MEDIUM

```dockerfile
# Without HEALTHCHECK, the orchestrator doesn't know if your app is actually working
# It only knows the process is running — not that it's healthy

# Add this before CMD
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
```

### 6. Use COPY Instead of ADD (DL3020) — LOW

```dockerfile
# BAD: ADD can auto-extract tarballs and fetch URLs (unexpected behavior)
ADD . /app

# GOOD: COPY does exactly what it says
COPY . /app
```

### 7. Use Exec Form for CMD (DL3025) — LOW

```dockerfile
# BAD: shell form — runs via /bin/sh, doesn't forward signals properly
CMD python app.py

# GOOD: exec form — PID 1, handles SIGTERM for graceful shutdown
CMD ["python", "app.py"]
```

### 8. Set WORKDIR (DL3000) — LOW

```dockerfile
# BAD: relative paths, unclear where things land
COPY . .

# GOOD: explicit working directory
WORKDIR /app
COPY . .
```

### 9. Don't Store Secrets in the Image — CRITICAL

```dockerfile
# BAD: secret baked into the image forever
ENV DATABASE_URL="postgres://user:password@db:5432/mydb"
COPY .env /app/.env

# GOOD: pass secrets at runtime
# (don't set them in the Dockerfile at all)
CMD ["python", "app.py"]
# Then run with: docker run -e DATABASE_URL="..." my-app
```

### 10. Add a .dockerignore — MEDIUM

Create `.dockerignore` in the same directory as your Dockerfile:

```
.git
.env
*.env
node_modules
__pycache__
.terraform
*.pem
*.key
```

This prevents secrets, credentials, and junk from accidentally being copied
into the image.

---

## Step 3: The Secure Dockerfile Template

Here's a complete, hardened Dockerfile you can start from:

```dockerfile
# Use specific version, minimal base
FROM python:3.12.3-slim

# Don't run as root
RUN groupadd -r appuser && useradd -r -g appuser -d /app appuser

# Set working directory
WORKDIR /app

# Install dependencies first (Docker layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY --chown=appuser:appuser . .

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Use exec form
CMD ["python", "app.py"]
```

---

## Step 4: Verify Your Fixes

After making changes, run Hadolint again:

```bash
# Should show fewer (ideally zero) warnings
hadolint Dockerfile

# Rebuild and test
docker build -t my-app:hardened .
docker run --rm my-app:hardened

# Verify it runs as non-root
docker run --rm my-app:hardened id
# Should show: uid=1000(appuser) gid=1000(appuser)

# Verify image size decreased
docker images my-app
```

---

## Step 5: Before vs. After

Track your Dockerfile improvements:

```bash
# Count Hadolint findings before and after
echo "Before: $(hadolint Dockerfile.old 2>&1 | wc -l) findings"
echo "After:  $(hadolint Dockerfile 2>&1 | wc -l) findings"

# Compare image sizes
docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep my-app
```

---

## Common Gotchas

**"My app can't write files after adding USER"**
- Your app probably writes to a directory owned by root
- Fix: `RUN mkdir /app/data && chown appuser:appuser /app/data`
- Or mount a volume: `docker run -v /data:/app/data my-app`

**"My app needs to bind to port 80"**
- Non-root users can't bind to ports below 1024
- Fix: Use port 8080 instead and map it: `docker run -p 80:8080 my-app`

**"pip install fails with permission denied"**
- Install packages BEFORE switching to USER
- The `USER` instruction should be near the bottom, after all `RUN` commands

---

## Next Steps

- Audit running containers in your cluster → [03-check-running-containers.md](03-check-running-containers.md)
- Deploy runtime detection → [04-deploy-falco.md](04-deploy-falco.md)
