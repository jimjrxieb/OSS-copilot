# CrowdStrike Falcon Integration

> CrowdStrike doesn't accept external findings directly.
> Use Splunk as the intermediary, or fix first so Falcon sees a clean runtime.

---

## What CrowdStrike Expects

CrowdStrike Falcon is an endpoint/runtime detection platform. It deploys an
agent (Falcon sensor) on hosts and containers. It doesn't have an external
findings ingestion API like Security Hub or Prisma Cloud.

**Two integration paths:**
1. Forward findings to Splunk → CrowdStrike reads from Splunk (via Falcon Data Replicator or Splunk add-on)
2. Fix first → Falcon sees cleaner runtime behavior

---

## Path 1: Via Splunk (Intermediary)

If the client runs both Splunk and CrowdStrike (common in enterprise SOCs):

```
OSS-Copilot scans → JSON → Splunk HEC → Splunk index
                                              ↑
CrowdStrike Falcon Sensor → Falcon events → Splunk index
                                              ↓
                              Splunk correlates both sources
                              SOC sees unified view
```

### Setup

1. Send OSS-Copilot findings to Splunk (see [splunk.md](splunk.md))
2. Install the CrowdStrike Falcon add-on for Splunk
3. Both data sources land in Splunk — correlated by hostname, container ID, or IP

### Correlation Queries

```spl
# OSS-Copilot found a CVE + CrowdStrike detected exploitation
sourcetype="oss-copilot:trivy" Severity="CRITICAL"
| join PkgName [
    search sourcetype="crowdstrike:events" ExploitTarget=*
]
| table _time, PkgName, VulnerabilityID, ExploitTarget, ComputerName

# Containers that failed both static scan and runtime detection
sourcetype="oss-copilot:*" OR sourcetype="crowdstrike:events"
| stats count by container_id, sourcetype
| where count > 1
```

---

## Path 2: Fix First (Cleaner Runtime)

CrowdStrike Falcon monitors runtime behavior — processes, file access, network
connections. If your containers are hardened before deployment:

```
Without fixing first:
  Falcon alerts on container running as root     (noisy)
  Falcon alerts on writable filesystem           (noisy)
  Falcon alerts on excessive capabilities        (noisy)
  Falcon alerts on actual malicious process      (buried in noise)

After OSS-Copilot fixes:
  Containers run as non-root                     (no alert)
  Filesystems are read-only                      (no alert)
  Capabilities dropped                           (no alert)
  Falcon alerts on actual malicious process      (immediately visible)
```

Hardening containers with OSS-Copilot reduces Falcon's alert volume so the
SOC can focus on genuine threats.

---

## When to Use Each Path

| Scenario | Via Splunk | Fix First |
|----------|-----------|-----------|
| SOC runs Splunk + CrowdStrike | Yes — unified view | Both |
| Client evaluating CrowdStrike | No | Yes — cleaner baseline |
| Incident response | Yes — correlate CVE with exploit | Yes |
| Reducing Falcon alert fatigue | No | Yes — fewer noisy alerts |
