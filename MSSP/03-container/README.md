# 03-Container — Image, Dockerfile, and Runtime Security

> This is what Prisma Cloud CWPP and Sysdig Secure do.
> Here's Trivy + Hadolint + Falco doing 80% of it.

---

## Start Here

Container security has three layers — and most teams only do the first one:

1. **Image scanning** — Are there known CVEs in your container images?
2. **Dockerfile hardening** — Is your container built securely? (Non-root, minimal base, no secrets baked in)
3. **Runtime detection** — What's happening inside your containers right now?

Enterprise tools like Prisma Cloud ($100-400K/yr) and Sysdig Secure ($50-250K/yr)
bundle all three. Open source covers each layer with separate tools that, together,
give you 80% of the same coverage.

**Follow the playbooks in order. Each one builds on the last.**

| # | Playbook | What You'll Do | Time |
|---|----------|---------------|------|
| 00 | [Know Your Images](playbooks/00-know-your-images.md) | Inventory what's running and where it came from | 5 min |
| 01 | [Scan Your Images](playbooks/01-scan-your-images.md) | Find CVEs in your container images | 10 min |
| 02 | [Harden Your Dockerfiles](playbooks/02-harden-your-dockerfiles.md) | Fix the top 10 Dockerfile mistakes | 15 min |
| 03 | [Check Running Containers](playbooks/03-check-running-containers.md) | Audit what's actually running in your cluster | 10 min |
| 04 | [Deploy Falco](playbooks/04-deploy-falco.md) | Runtime threat detection — the open source Sysdig | 20 min |
| 05 | [Container Security in CI](playbooks/05-container-ci.md) | Block vulnerable images before they reach production | 10 min |

---

## The Tools

| Tool | What It Does | One-Liner Install | Enterprise Equivalent |
|------|-------------|-------------------|----------------------|
| **Trivy** | Finds CVEs in container images (OS + app packages) | `brew install trivy` | Prisma Cloud CWPP ($100K+/yr) |
| **Grype** | Same as Trivy, different vulnerability database | `brew install grype` | Snyk Container ($25K+/yr) |
| **Hadolint** | Lints Dockerfiles against 100+ best practice rules | `brew install hadolint` | Built into Prisma Cloud |
| **Falco** | Monitors container syscalls in real-time | `helm install` | Sysdig Secure ($50K+/yr) |
| **Docker Scout** | Image CVEs + base image recommendations | `docker scout` (built-in) | Snyk Container |

---

## Quick Start (Skip the Playbooks)

```bash
cd 03-container

# Scan container images for CVEs
./scan-images.sh nginx:1.25 my-app:latest

# Lint your Dockerfiles
./scan-dockerfile.sh /path/to/Dockerfile

# Audit running containers (needs kubectl)
./scan-runtime.sh
```

---

## What These Tools Actually Catch

**Real examples:**

```
Trivy     →  nginx:1.25 has CVE-2024-7347 (CRITICAL) — HTTP/2 request smuggling
             Fixed in nginx:1.25.5

Hadolint  →  DL3002: Last USER should not be root
             DL3007: Using latest is prone to errors (pin to specific version)
             DL3015: Avoid additional packages with apt-get (use --no-install-recommends)

Falco     →  Shell spawned in container (someone exec'd into a production pod)
             Sensitive file opened for reading (/etc/shadow)
             Binary not part of base image was executed (cryptominer?)
```

---

## The Three Layers Explained

```
BUILD TIME                    DEPLOY TIME                   RUN TIME
─────────────────────────    ────────────────────────      ────────────────────────
Dockerfile → Image            Image → Container             Container → Behavior

Hadolint checks:              Trivy/Grype check:            Falco watches:
  Is it non-root?               Any known CVEs?               Shell spawned?
  Base image pinned?            Outdated packages?            File tampering?
  No secrets baked in?          License issues?               Container escape?
  Minimal packages?                                           Crypto mining?

FIX HERE                      SCAN HERE                     DETECT HERE
(cheapest)                    (before deploy)               (in production)
```

Fixing at build time is 10x cheaper than detecting at runtime.
That's why the playbooks start with Dockerfiles, not Falco.

---

## What Enterprise Does Better (the Honest 20%)

| Gap | What Enterprise Does | Why It Matters |
|-----|---------------------|----------------|
| **Runtime blocking** | Prisma/Sysdig auto-kill malicious processes | Falco alerts — you write the response |
| **Drift detection** | Compare running container vs built image | Detects post-deploy tampering |
| **Behavioral ML** | Sysdig learns "normal" per container | Catches zero-days Falco rules can't express |
| **Registry scanning** | Continuous scanning of your registry | Trivy scans what you point at, when you point at it |
| **Forensics** | Full syscall recording for incident investigation | Falco logs events but doesn't record full traces |

**When to buy enterprise:**
- You need automatic runtime blocking (kill malicious containers)
- You run >500 containers and need continuous registry scanning
- Compliance requires drift detection evidence (image-to-runtime comparison)
- You need ML-based behavioral analysis for zero-day detection

**When open source is enough:**
- Teams running <500 containers
- Pre-production environments where alerting > blocking
- Image scanning in CI/CD (Trivy = Prisma for CVE coverage)
- Basic runtime detection (Falco covers 70% of Sysdig's detection rules)

---

## How This Connects to GP-Copilot

This directory is the open source version of
GP-CONSULTING/03-RUNTIME-SECURITY in the [GP-Copilot](https://github.com/jimjrxieb/GP-copilot) repo — the
full runtime security package with 65 Falco rules, 11 watchers, 8 responders,
Splunk integration, and service mesh deployment.

| You're Here (OSS-Copilot) | Full Framework (GP-Copilot) |
|---------------------------|----------------------------|
| 3 scanners (Trivy, Grype, Hadolint) | 6 scanners + custom NPC wrappers |
| Basic Falco deployment | 65 custom Falco rules + auto-response |
| Manual Dockerfile fixes | 6 automated fixer scripts |
| CI image scanning | Full supply chain (sign, SBOM, verify) |
| Alert-only runtime | Alert + respond + correlate via Splunk |

OSS-Copilot gives you the scanning and basic detection for free.
The full framework adds automated response, correlation, and 24/7 monitoring.
