# 08 — Incident Response

> When Falco fires a real alert, here's what to do: timeline, forensics, contain, report.

This is the playbook you run at 3am when Falco detects a shell spawn in a production container. Don't panic. Follow the steps.

In production, tools like CrowdStrike and Sysdig have automated response. This is the manual version — same procedures, you run the commands.

---

## Step 1: Reconstruct the Timeline

```bash
bash tools/incident-timeline.sh \
  --namespace <namespace> \
  --pod <pod-name> \
  --since 1h \
  --output $OUTPUT_DIR/incident/
```

**What it collects:**
- Falco alerts for this pod (last hour)
- Kubernetes events (pod creation, restarts, image pulls)
- Container logs
- Network connections (if available)

---

## Step 2: Capture Forensics

Before you touch anything — capture the evidence:

```bash
bash tools/capture-forensics.sh \
  --namespace <namespace> \
  --pod <pod-name> \
  --output $OUTPUT_DIR/incident/forensics/
```

**What it captures:**
- Running processes (`ps aux`)
- Open files (`ls /proc/*/fd`)
- Network connections (`ss -tlnp`)
- Environment variables
- Mounted volumes
- Container filesystem snapshot (if writable)

---

## Step 3: Contain

### Option A: Isolate (cut network, keep running for investigation)

```bash
bash tools/isolate-pod.sh --namespace <namespace> --pod <pod-name>
```

This applies a NetworkPolicy that blocks all ingress and egress to the pod. The pod stays running so you can investigate, but it can't talk to anything.

### Option B: Kill (stop the threat immediately)

```bash
bash tools/kill-pod.sh --namespace <namespace> --pod <pod-name>
```

Deletes the pod. If it's managed by a Deployment, a new (clean) pod replaces it.

**Decision guide:**
- Shell spawn + unknown process → **Isolate** first, investigate, then kill
- Crypto mining confirmed → **Kill** immediately
- Data exfiltration in progress → **Isolate** immediately (stop the bleed)
- Privilege escalation attempt → **Isolate**, check if successful

---

## Step 4: Investigate

With the pod isolated or killed:

```bash
# Review the timeline
cat $OUTPUT_DIR/incident/timeline.md

# Check what processes were running
cat $OUTPUT_DIR/incident/forensics/processes.txt

# Check network connections
cat $OUTPUT_DIR/incident/forensics/network.txt

# Check for persistence mechanisms
cat $OUTPUT_DIR/incident/forensics/filesystem.txt | grep -E "cron|authorized_keys|systemd"
```

**Key questions:**
- How did the attacker get in? (vulnerable dependency? exposed service? stolen credential?)
- What did they do? (recon? lateral movement? data exfil?)
- Did they persist? (crontab? modified binary? new user?)
- What's the blast radius? (one pod? one namespace? whole cluster?)

---

## Step 5: Generate Report

```bash
python3 tools/generate-report.py \
  --incident-dir $OUTPUT_DIR/incident/ \
  --format markdown \
  --output $OUTPUT_DIR/incident/report.md
```

---

## Incident Report Template

```markdown
# Incident Report — <DATE>

## Summary
- **Detection:** Falco rule "<rule-name>" fired at <time>
- **Affected:** <namespace>/<pod>
- **Severity:** <Critical/High/Medium>
- **Containment:** <Isolated/Killed> at <time>

## Timeline
| Time | Event |
|------|-------|
| HH:MM | Falco alert: <description> |
| HH:MM | Forensics captured |
| HH:MM | Pod isolated/killed |
| HH:MM | Investigation started |

## Root Cause
<What happened and how>

## Actions Taken
- [ ] Threat contained
- [ ] Evidence preserved
- [ ] Root cause identified
- [ ] Vulnerability patched
- [ ] Detection rule verified

## Lessons Learned
<What to improve>
```

---

## Next Step

Go to [09-detection-validation.md](09-detection-validation.md) to verify your detection rules actually fire.
