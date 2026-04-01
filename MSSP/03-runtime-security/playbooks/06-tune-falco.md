# 06 — Tune Falco

> Reduce noise so alerts mean something. Target: under 50 alerts per day.

Falco out of the box is noisy. Every `kubectl exec`, every health check, every DNS lookup can fire a rule. This playbook shows you how to find the noisy rules and tune them without losing detection coverage.

---

## What You Need

- Application deployed and running (playbook 05)
- Falco running for at least a few hours with real traffic

---

## Step 1: Find the Noisy Rules

```bash
bash tools/tune-falco.sh --show-top
```

This shows the top 20 rules by alert count. Common noisy rules:
- `Terminal shell in container` — fires on every `kubectl exec`
- `Read sensitive file untrusted` — fires on health check processes reading `/etc/passwd`
- `Contact K8S API Server From Container` — fires on legitimate operator pods

---

## Step 2: Apply the Base Allowlist

```bash
bash tools/tune-falco.sh --add-allowlist falco-rules/allowlist.yaml
```

The base allowlist suppresses known-good patterns:
- Health check processes reading `/proc/` files
- Kyverno, ArgoCD, and monitoring agents doing expected K8s API calls
- Init containers doing expected setup work

---

## Step 3: Add Client-Specific Exceptions

For your application's unique patterns:

```bash
# See what a specific rule is firing on
bash tools/tune-falco.sh --rule "Terminal shell in container" --details

# Add an exception for a known-good container
bash tools/tune-falco.sh --add-exception \
  --rule "Terminal shell in container" \
  --container "debug-sidecar" \
  --reason "Debug sidecar runs health check scripts"
```

---

## Step 4: Load Threat Detection Rules

After reducing noise, load the high-value detection rules:

```bash
bash tools/tune-falco.sh --list-rules

# Load specific rule sets
kubectl create configmap falco-threat-rules \
  --from-file=falco-rules/crypto-mining.yaml \
  --from-file=falco-rules/data-exfiltration.yaml \
  --from-file=falco-rules/privilege-escalation.yaml \
  --from-file=falco-rules/persistence.yaml \
  --namespace falco \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart daemonset/falco -n falco
```

---

## Step 5: Verify Alert Volume

```bash
# Count alerts in the last hour
kubectl logs -n falco -l app.kubernetes.io/name=falco --since=1h | \
  grep -c "Warning\|Error\|Critical"

# Target: < 50/day = < 2/hour
# If still noisy, go back to step 3 and add more exceptions
```

---

## The MITRE ATT&CK Mapping

The `falco-rules/mitre-mappings.yaml` maps each rule to a MITRE ATT&CK technique. This is useful for compliance reporting and understanding what your detection covers:

| Tactic | Technique | Rule |
|--------|-----------|------|
| Execution | T1059 | Shell in container |
| Persistence | T1053 | Crontab modification |
| Privilege Escalation | T1611 | Container escape |
| Defense Evasion | T1070 | Log deletion |
| Credential Access | T1552 | Sensitive file read |
| Impact | T1496 | Crypto mining |

---

## Next Step

Go to [07-siem-integration.md](07-siem-integration.md) to forward alerts to your SIEM.
