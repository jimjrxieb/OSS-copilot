# Playbook 00: Know Your Images

> Before you scan, know what you're scanning. What images are you running?
> Where did they come from? Who built them?
>
> **Time:** 5 minutes
> **Prerequisites:** Docker installed, or kubectl access to a cluster

---

## Why This Matters

Most teams can't answer "what container images are running in production?"
They know the app name, but not the image tag, not the base image, not whether
it's 6 months out of date. You can't secure what you haven't inventoried.

This is the container version of [01-code/playbooks/00-understand-your-repo.md](../../01-code/playbooks/00-understand-your-repo.md) —
look before you scan.

---

## Step 1: Find Your Dockerfiles

```bash
cd /path/to/your/project

# Find all Dockerfiles
find . -name "Dockerfile*" -not -path "./.git/*"
```

For each Dockerfile, check:

```bash
# What base image does it use?
head -5 Dockerfile
# Look for: FROM python:3.12-slim  or  FROM node:20-alpine  or  FROM ubuntu:22.04
```

**What you're looking for:**
- Is the base image pinned to a specific version? (`python:3.12-slim` = good, `python:latest` = bad)
- Is it a minimal base? (`-slim` or `-alpine` = good, full `ubuntu` = usually too big)
- Is it an official image? (Docker Hub verified publishers = good, random user's image = risky)

---

## Step 2: List Running Images (If You Have a Cluster)

```bash
# What images are running right now?
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -k3

# How many unique images?
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u | wc -l

# Which images use :latest (bad)?
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | grep -E ':latest$|[^:]$'
```

**Red flags:**
- Images tagged `:latest` — you don't know what version you're running
- Images with no tag at all — same problem, defaults to `:latest`
- Images from unknown registries — who built this?
- Images that are months or years old — likely have unpatched CVEs

---

## Step 3: Check Your Local Images

```bash
# What images are on this machine?
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"

# How old are they?
docker images --format "{{.Repository}}:{{.Tag}} — {{.CreatedSince}}" | head -20
```

**Anything older than 3 months** probably has unpatched CVEs in its OS packages,
even if your application code hasn't changed.

---

## Step 4: Make Your Image Inventory

Before scanning, write down what you're working with:

```
My Container Images:
────────────────────
Dockerfiles found:         ___
Running in cluster:        ___  images (unique)
Using :latest tag:         ___  (fix these first)
Base images:
  - __________________ (e.g., python:3.12-slim)
  - __________________ (e.g., node:20-alpine)
  - __________________ (e.g., nginx:1.25)
Oldest image in use:       ___
```

---

## Step 5: Understand the Supply Chain

Your container image is built on layers. Each layer can have vulnerabilities:

```
YOUR CODE          ← You wrote this (scan with 01-code tools)
────────────────
APP DEPENDENCIES   ← pip/npm/go packages (scan with Trivy/Grype)
────────────────
BASE IMAGE OS      ← Ubuntu/Alpine/Debian packages (scan with Trivy/Grype)
────────────────
BASE IMAGE ITSELF  ← python:3.12, node:20, nginx:1.25 (who maintains this?)
```

When Trivy reports 50 CVEs in your image, most of them are in the base image
OS packages — not your code. Updating the base image fixes them.

```bash
# Check how many packages are in your image
docker run --rm your-image dpkg -l 2>/dev/null | wc -l    # Debian/Ubuntu
docker run --rm your-image apk list 2>/dev/null | wc -l   # Alpine
```

**Fewer packages = fewer CVEs.** That's why `-slim` and `-alpine` variants exist.

---

## Next Steps

Now you know what images you're working with. Time to scan them.

Go to: [01-scan-your-images.md](01-scan-your-images.md)
