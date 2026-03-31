# Playbook 04: Deploy Falco

> Runtime threat detection. Falco watches what your containers do in real-time —
> shell spawns, file access, network connections, privilege escalation.
>
> **Time:** ~20 minutes
> **Prerequisites:** Helm installed, kubectl access to a cluster

---

## What Falco Is

Falco is the open source version of Sysdig Secure. It sits on every node in your
cluster and monitors system calls — every file read, every network connection,
every process spawn inside every container.

When something suspicious happens (someone runs `bash` inside a production
container, a process reads `/etc/shadow`, a container makes an unexpected
outbound connection), Falco generates an alert.

**Falco doesn't block anything.** It detects and alerts. If you need automatic
blocking, that's where Sysdig Secure ($50K+/yr) or Prisma Cloud comes in.
For most teams, detection + alerting is enough.

---

## Step 1: Install Falco

```bash
# Add the Falco Helm repo
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# Install Falco in observe-only mode (safe — alerts only, blocks nothing)
helm install falco falcosecurity/falco \
    --namespace falco-system \
    --create-namespace \
    --set falcosidekick.enabled=true \
    --set falcosidekick.webui.enabled=true
```

**What just happened:**
- Falco DaemonSet deployed (one pod per node)
- falcosidekick deployed (routes alerts to Slack, email, webhook, etc.)
- Web UI available for viewing alerts

```bash
# Verify it's running
kubectl get pods -n falco-system
# You should see falco pods (one per node) in Running state

# Check Falco logs
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=20
```

---

## Step 2: Understand What Falco Detects

Falco ships with ~100 default rules. Here are the ones that matter most:

| Rule | What It Detects | Why It Matters |
|------|----------------|----------------|
| **Terminal shell in container** | Someone ran bash/sh inside a container | Containers should be immutable — no one should be exec'ing in |
| **Read sensitive file** | Process read /etc/shadow, /etc/passwd | Credential harvesting attempt |
| **Write below binary dir** | File written to /bin, /sbin, /usr/bin | Malware installation |
| **Launch privileged container** | Container started with privileged: true | Potential container escape |
| **Contact K8s API server** | Container accessed the K8s API | Lateral movement attempt |
| **Outbound connection to C2** | Container connected to suspicious IP/port | Command & control communication |
| **Package management process** | apt-get, yum, pip ran inside a container | Should happen at build time, not runtime |
| **Mkdir binary dirs** | Directory created in /bin, /usr/bin | Attacker setting up persistence |

---

## Step 3: Test That Falco Works

Trigger a test alert by exec'ing into a container:

```bash
# Find a running pod
kubectl get pods -n default

# Exec into it (this should trigger a Falco alert)
kubectl exec -it <pod-name> -n default -- /bin/sh
# Type 'exit' to leave

# Check Falco logs for the alert
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=10 | grep "Terminal shell"
```

You should see something like:

```
Warning: Terminal shell in container
  (user=root container=my-app pod=my-app-abc123 namespace=default
   shell=sh parent=runc cmdline=sh)
```

That's Falco working. It detected that someone opened a shell inside a running
container.

---

## Step 4: Route Alerts Somewhere Useful

Falco logs to stdout by default. That's fine for testing, but in production you
need alerts going somewhere a human will actually see them.

### Option A: Slack (Easiest)

```bash
# Upgrade Falco with Slack alerting
helm upgrade falco falcosecurity/falco \
    --namespace falco-system \
    --set falcosidekick.enabled=true \
    --set falcosidekick.config.slack.webhookurl="https://hooks.slack.com/services/YOUR/WEBHOOK/URL" \
    --set falcosidekick.config.slack.channel="#security-alerts" \
    --set falcosidekick.config.slack.minimumpriority="warning"
```

### Option B: Webhook (Flexible)

```bash
helm upgrade falco falcosecurity/falco \
    --namespace falco-system \
    --set falcosidekick.enabled=true \
    --set falcosidekick.config.webhook.address="https://your-endpoint.com/falco"
```

### Option C: Stdout + kubectl logs (Getting Started)

Just watch the logs:

```bash
# Stream Falco alerts in real-time
kubectl logs -n falco-system -l app.kubernetes.io/name=falco -f | grep -E "Warning|Error|Critical"
```

---

## Step 5: View the Falco Web UI

If you installed with `falcosidekick.webui.enabled=true`:

```bash
# Port-forward to access the web UI
kubectl port-forward -n falco-system svc/falco-falcosidekick-ui 2802:2802

# Open in browser
# http://localhost:2802
```

The UI shows:
- Alert timeline (when things happened)
- Severity breakdown (how bad)
- Source breakdown (which containers/pods)
- Rule breakdown (what was detected)

---

## Step 6: Tune Falco (Reduce Noise)

Default Falco rules are noisy. Some legitimate activities trigger alerts:

```bash
# See what's alerting
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=100 | \
    grep -oP '(?<=Rule: ).*' | sort | uniq -c | sort -rn | head -10
```

### Common noise sources and fixes:

**"Terminal shell in container" for init containers:**
Legitimate — init containers often run shell scripts. Create an exception:

```yaml
# Create falco-custom-rules.yaml
customRules:
  rules-custom.yaml: |-
    - rule: Terminal shell in container
      append: true
      condition: and not (k8s.ns.name="kube-system")
```

**"Read sensitive file" for monitoring tools:**
Prometheus, Grafana agents, and log collectors legitimately read system files.

**"Package management process" for dev namespaces:**
If developers run package installs in dev containers, that's expected (but
should still be fixed in their Dockerfiles).

```bash
# Apply custom rules
helm upgrade falco falcosecurity/falco \
    --namespace falco-system \
    -f falco-custom-rules.yaml
```

**The tuning principle:** Start with all rules on. Let it run for a week.
Identify what's noise vs. signal. Exclude the noise. What's left is real.

---

## What Falco Doesn't Do

| Feature | Falco (Free) | Sysdig Secure ($50K+) |
|---------|-------------|----------------------|
| Detect suspicious activity | Yes | Yes |
| Alert (Slack, webhook, log) | Yes | Yes |
| Auto-block malicious processes | No | Yes |
| ML-based behavioral profiling | No | Yes |
| Container forensics/recording | No | Yes |
| Drift detection (image vs runtime) | No | Yes |
| Compliance dashboards | No | Yes |

Falco is the alarm system. Sysdig Secure is the alarm system + security guard
+ cameras + locks.

For most teams, the alarm system is enough. You'll hear it go off, and you'll
respond. If you need automatic response at scale, that's when Sysdig earns
its license cost.

---

## Next Steps

- Add container scanning to CI → [05-container-ci.md](05-container-ci.md)
- Back to overview → [../README.md](../README.md)
