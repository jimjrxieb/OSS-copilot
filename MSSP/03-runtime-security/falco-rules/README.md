# Custom Falco Rules

> Drop-in Falco rules for client-specific threat detection.

---

## Available Rule Sets

| Rule File | Purpose | Alerts/Day (typical) |
|-----------|---------|---------------------|
| `mitre-mappings.yaml` | MITRE ATT&CK enrichment | N/A (enrichment only) |
| `custom-allowlist.yaml` | Reduce false positives | -80% alerts |
| `crypto-mining.yaml` | Detect cryptomining | 0-2 |
| `data-exfiltration.yaml` | Detect data theft | 0-5 |
| `privilege-escalation.yaml` | Detect privesc attempts | 0-3 |
| `persistence.yaml` | Detect persistence mechanisms | 0-2 |

---

## Quick Start

### 1. Copy rules to Falco ConfigMap

```bash
# Create ConfigMap with custom rules
kubectl create configmap falco-custom-rules \
  --from-file=01-detection/falco-rules/ \
  --namespace falco

# Update Falco to use custom rules
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set-file customRules.mitre-mappings=01-detection/falco-rules/mitre-mappings.yaml \
  --set-file customRules.allowlist=01-detection/falco-rules/custom-allowlist.yaml
```

### 2. Verify rules loaded

```bash
kubectl exec -n falco daemonset/falco -- falco --list

# Should show custom rules:
# - Crypto Mining Detection
# - Data Exfiltration via Network
# - Privilege Escalation Attempt
# etc.
```

---

## Rule Details

### mitre-mappings.yaml

**Purpose:** Map Falco rules to MITRE ATT&CK framework

**Example:**
```yaml
- rule: Terminal shell in container
  tags:
    - mitre_tactic: TA0002  # Execution
    - mitre_technique: T1059.004  # Unix Shell
    - mitre_subtechnique: ""
```

**Usage:** Auto-enriches every alert with MITRE context

---

### custom-allowlist.yaml

**Purpose:** Reduce false positives by allowlisting known-good activity

**Common allowlists:**

1. **Dev namespaces**
   ```yaml
   - rule: Terminal shell in container
     append: true
     exceptions:
       - name: dev_namespace
         fields:
           - k8s.ns.name=development
           - k8s.ns.name=staging
   ```

2. **Monitoring agents**
   ```yaml
   - rule: Contact K8s API Server
     condition: >
       condition and not proc.name in (
         prometheus,
         grafana-agent,
         datadog-agent,
         newrelic-agent
       )
   ```

3. **Config management**
   ```yaml
   - rule: Write below /etc
     condition: >
       condition and not proc.name in (
         ansible,
         chef-client,
         puppet
       )
   ```

---

### crypto-mining.yaml

**Purpose:** Detect cryptocurrency mining activity

**Rules:**

1. **Known mining processes**
   ```yaml
   - rule: Crypto Mining Process
     desc: Detect known crypto mining binaries
     condition: >
       spawned_process and proc.name in (
         xmrig,
         minergate,
         cpuminer,
         ethminer,
         cgminer
       )
     output: "Crypto mining process detected (proc=%proc.name)"
     priority: CRITICAL
   ```

2. **Mining pool connections**
   ```yaml
   - rule: Connection to Mining Pool
     desc: Detect outbound connections to known mining pools
     condition: >
       outbound and fd.sip in (
         pool.supportxmr.com,
         xmr.pool.minergate.com,
         eth.f2pool.com
       )
     output: "Mining pool connection (dest=%fd.sip)"
     priority: CRITICAL
   ```

3. **High CPU usage with network**
   ```yaml
   - rule: Suspicious CPU and Network
     desc: High CPU + outbound network (possible mining)
     condition: >
       container and cpu.percent > 80 and outbound
     output: "High CPU with network activity (cpu=%cpu.percent)"
     priority: WARNING
   ```

---

### data-exfiltration.yaml

**Purpose:** Detect data theft attempts

**Rules:**

1. **Large outbound transfers**
   ```yaml
   - rule: Large Data Transfer
     desc: Detect large outbound data transfers
     condition: >
       outbound and fd.bytes_out > 100000000  # 100MB
     output: "Large data transfer detected (bytes=%fd.bytes_out dest=%fd.sip)"
     priority: HIGH
   ```

2. **Sensitive file access + network**
   ```yaml
   - rule: Sensitive File Exfiltration
     desc: Sensitive file read followed by network activity
     condition: >
       open_read and (
         fd.name glob /etc/passwd* or
         fd.name glob /etc/shadow* or
         fd.name glob /root/.ssh/* or
         fd.name glob /home/*/.ssh/*
       ) and outbound
     output: "Sensitive file accessed before network (file=%fd.name)"
     priority: CRITICAL
   ```

3. **Data staging**
   ```yaml
   - rule: Data Staging
     desc: Writing to /tmp or /dev/shm before exfil
     condition: >
       open_write and (
         fd.name glob /tmp/* or
         fd.name glob /dev/shm/*
       ) and fd.size > 50000000  # 50MB
     output: "Large file staged in temp dir (file=%fd.name size=%fd.size)"
     priority: WARNING
   ```

---

### privilege-escalation.yaml

**Purpose:** Detect privilege escalation attempts

**Rules:**

1. **Setuid bit changes**
   ```yaml
   - rule: Setuid Bit Modification
     desc: Detect chmod +s (setuid)
     condition: >
       spawned_process and proc.name=chmod and
       proc.args contains "+s"
     output: "Setuid bit set (file=%proc.args)"
     priority: CRITICAL
   ```

2. **Sudo usage**
   ```yaml
   - rule: Sudo Execution
     desc: Detect sudo usage (potential privesc)
     condition: >
       spawned_process and proc.name=sudo
     output: "Sudo executed (user=%user.name cmd=%proc.cmdline)"
     priority: WARNING
   ```

3. **Kernel module loading**
   ```yaml
   - rule: Kernel Module Load
     desc: Detect kernel module insertion
     condition: >
       spawned_process and proc.name in (insmod, modprobe)
     output: "Kernel module loaded (module=%proc.args)"
     priority: CRITICAL
   ```

---

### persistence.yaml

**Purpose:** Detect persistence mechanisms

**Rules:**

1. **Cron job creation**
   ```yaml
   - rule: Cron Job Created
     desc: Detect new cron jobs (persistence)
     condition: >
       open_write and (
         fd.name glob /etc/cron* or
         fd.name glob /var/spool/cron/*
       )
     output: "Cron job created (file=%fd.name user=%user.name)"
     priority: HIGH
   ```

2. **Systemd service creation**
   ```yaml
   - rule: Systemd Service Created
     desc: Detect new systemd services
     condition: >
       open_write and fd.name glob /etc/systemd/system/*
     output: "Systemd service created (file=%fd.name)"
     priority: HIGH
   ```

3. **SSH key addition**
   ```yaml
   - rule: SSH Key Added
     desc: Detect new SSH authorized_keys
     condition: >
       open_write and fd.name glob */authorized_keys
     output: "SSH key added (user=%user.name file=%fd.name)"
     priority: HIGH
   ```

---

## Tuning Guide

### Step 1: Deploy with defaults

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --set-file customRules.default=01-detection/falco-rules/crypto-mining.yaml
```

### Step 2: Monitor for 24 hours

```bash
# Count alerts by rule
kubectl logs -n falco daemonset/falco --tail=10000 | \
  jq -r '.rule' | sort | uniq -c | sort -rn
```

### Step 3: Add allowlists

```bash
# Edit custom-allowlist.yaml
vim 01-detection/falco-rules/custom-allowlist.yaml

# Apply
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set-file customRules.allowlist=01-detection/falco-rules/custom-allowlist.yaml
```

### Step 4: Repeat until <50 alerts/day

---

## Testing Rules

Generate test alerts:

```bash
# Install Falco event generator
kubectl run falco-event-generator \
  --image=falcosecurity/event-generator \
  --rm -it -- run

# Or specific test
kubectl run falco-event-generator \
  --image=falcosecurity/event-generator \
  --rm -it -- run syscall

# Should trigger:
# - Terminal shell in container
# - Write below /etc
# - Read sensitive file
```

---

## Integration with jsa-infrasec

Falco alerts automatically flow to jsa-infrasec:

```
Falco Alert → jsa-infrasec → JADE → Response
```

jsa-infrasec enriches with:
- MITRE ATT&CK mapping (from tags)
- Rank classification (E-S)
- Blast radius analysis
- Recommended response

---

*Part of the Iron Legion - CKS | CKA | CCSP Certified Standards*
