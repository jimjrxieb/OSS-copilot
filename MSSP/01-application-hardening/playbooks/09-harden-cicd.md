# 09 — Harden CI/CD Pipeline

> Secure the pipeline itself — SHA-pin actions, least-privilege permissions, image signing.

Playbook 06 deployed the scanning pipeline. This playbook hardens it. A CI pipeline that can be tampered with is worse than no pipeline at all — it gives you false confidence.

---

## The Build Chain

```
Developer pushes code
       |
  GitHub Actions
  1. Scan code (gitleaks, semgrep, trivy, checkov)
  2. Build container image
  3. Scan the built image (trivy image)
  4. Sign the image (cosign)
  5. Generate SBOM
  6. Push to registry
  7. Update manifest (GitOps trigger)
       |
  ArgoCD syncs to cluster (02-platform-hardening takes over here)
       |
  Admission control validates (signed? allowed registry? policy pass?)
       |
  Runtime monitoring watches (03-runtime-security takes over here)
```

---

## Step 1: Pin All Actions to SHA

Tags can be changed by the action maintainer. SHA cannot. Same principle as image digest pinning.

```yaml
# BAD — tag can be mutated
- uses: actions/checkout@v4

# GOOD — pinned to exact commit
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

**Find unpinned actions:**
```bash
grep -rn "uses:" .github/workflows/ | grep -v "@[a-f0-9]\{40\}" | grep -v "\./"
```

---

## Step 2: Set Least-Privilege Permissions

```yaml
# Workflow level — restrict all jobs by default
permissions:
  contents: read

# Job level — only what each job needs
jobs:
  scan:
    permissions:
      contents: read
      security-events: write  # only if uploading SARIF

  build:
    permissions:
      contents: read
      packages: write  # only if pushing to GHCR
```

---

## Step 3: Block Dangerous Patterns

```yaml
# NEVER: pull_request_target + checkout = script injection
# External PR authors can run arbitrary code with repo secrets
on:
  pull_request_target:  # DANGEROUS
steps:
  - uses: actions/checkout@...
    with:
      ref: ${{ github.event.pull_request.head.sha }}  # ATTACKER CODE

# NEVER: interpolate event data in run blocks
- run: echo "PR title: ${{ github.event.pull_request.title }}"  # INJECTION

# DO THIS INSTEAD: use environment variables
- run: echo "PR title: $PR_TITLE"
  env:
    PR_TITLE: ${{ github.event.pull_request.title }}
```

---

## Step 4: Add Image Build + Scan

After code scanning passes, build the image and scan it before pushing:

```yaml
  build-and-scan:
    needs: [security-scan]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683

      - name: Build image
        run: docker build -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} .

      - name: Scan built image
        uses: aquasecurity/trivy-action@062f2592684a31eb3aa050cc61bb585dc798aaca
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-image.sarif'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'
```

---

## Step 5: Sign the Image (Cosign)

Image signing proves the image was built by your CI, not tampered with. In production, the admission controller verifies this signature.

```yaml
      - name: Install cosign
        uses: sigstore/cosign-installer@dc72c7d5c4d10cd6bcb8cf6e3fd625a9e5e537da

      - name: Sign image
        run: |
          cosign sign --yes \
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
        env:
          COSIGN_EXPERIMENTAL: 1  # keyless signing via GitHub OIDC
```

Keyless signing uses GitHub Actions' OIDC token. No private keys to manage. The signature proves this image was built by this workflow, in this repo, on this commit.

---

## Step 6: Generate SBOM

```yaml
      - name: Generate SBOM
        uses: anchore/sbom-action@v0
        with:
          image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: cyclonedx-json
          output-file: sbom.cdx.json

      - name: Attach SBOM to image
        run: cosign attach sbom --sbom sbom.cdx.json \
          ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
```

---

## Step 7: Protect Workflow Files

```bash
# Add CODEOWNERS
cat >> .github/CODEOWNERS << 'EOF'

# Workflow files require security team review
.github/workflows/ @security-team
.github/CODEOWNERS @security-team
EOF
```

Set up branch protection: require Code Owner review for workflow changes.

---

## Step 8: Verify

```bash
# All actions SHA-pinned?
grep -rn "uses:" .github/workflows/ | grep -v "@[a-f0-9]\{40\}" | grep -v "\./"
# Expected: 0 results

# Permissions set?
grep -l "permissions:" .github/workflows/*.yml
# Expected: all workflow files

# No pull_request_target?
grep -l "pull_request_target" .github/workflows/*.yml
# Expected: 0 results
```

---

## Next Step

Go to [10-deploy-dev.md](10-deploy-dev.md) to deploy to the dev environment.
