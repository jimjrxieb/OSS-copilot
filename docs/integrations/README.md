# Enterprise Integrations

> Two ways to connect open source scanning to enterprise tools.
> Both make the enterprise tool more valuable.

---

## The Two Workflows

### Workflow A — Forward Findings to Enterprise Tool

Send your open source scan results into the enterprise platform's dashboard.
One pane of glass. Compliance evidence in one place.

```
Trivy/Prowler/Checkov scan
        ↓
  Format as SARIF / ASFF / JSON
        ↓
  Push to Prisma Cloud / Security Hub / Splunk
        ↓
  Enterprise tool shows findings in its dashboard
```

**Good for:** Clients who already have enterprise tools and want consolidated
reporting. Compliance teams who need everything in one place.

### Workflow B — Fix First, Let Enterprise Tool Rescan

Fix the noise before the enterprise tool runs its own scan. The enterprise
tool sees a cleaner environment and focuses on what only it can catch.

```
Without OSS-Copilot first:              With OSS-Copilot first:
  Wiz scans → 2,847 findings             OSS scans → fixes routine findings
  Team overwhelmed                        Wiz scans → 400 findings
  Critical findings buried                All critical, all signal
  License feels wasted                    License earns its keep
```

**Good for:** Reducing enterprise tool noise, making the license more valuable,
showing ROI to leadership. This is the more powerful play.

---

## Integration Guides

| Enterprise Tool | Integration | Native Format | Guide |
|----------------|-------------|---------------|-------|
| **AWS Security Hub** | Prowler pushes directly | ASFF (native) | [security-hub.md](security-hub.md) |
| **Prisma Cloud** | Checkov outputs Prisma format | SARIF | [prisma-cloud.md](prisma-cloud.md) |
| **Splunk** | Any scanner via HTTP Event Collector | JSON | [splunk.md](splunk.md) |
| **Wiz** | Fix first workflow (read-only platform) | N/A | [wiz.md](wiz.md) |
| **CrowdStrike** | Via Splunk intermediary | JSON → HEC | [crowdstrike.md](crowdstrike.md) |

---

## The Interview Answer This Unlocks

> "I integrate open source scanning into enterprise platforms two ways.
> First, I forward findings via SARIF or ASFF — Prowler natively pushes
> to AWS Security Hub, Checkov outputs Prisma-compatible SARIF. Second,
> and more powerfully, I fix the routine and deterministic findings before the enterprise
> tool runs its own scan. Wiz and Prisma see a cleaner environment, surface
> less noise, and focus on what only they can catch. Both approaches make
> the enterprise tool more valuable — one feeds it data, the other reduces
> its workload."
