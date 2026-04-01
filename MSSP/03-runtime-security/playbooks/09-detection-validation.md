# 09 — Detection Validation

> Trigger known attack patterns and verify Falco detects them. Trust but verify.

You deployed Falco, tuned the rules, and set up alerting. But does it actually work? This playbook triggers safe, controlled attack simulations and checks that Falco fires the expected alerts.

Run this in dev/staging only. These are real attack patterns executed in test pods.

---

## What You Need

- Falco deployed and tuned (playbooks 01 + 06)
- A test namespace with a disposable pod

---

## Setup: Create a Test Pod

```bash
kubectl create namespace detection-test
kubectl run attacker --image=alpine --restart=Never -n detection-test -- sleep 3600
kubectl wait --for=condition=ready pod/attacker -n detection-test --timeout=60s
```

---

## Test 1: Shell Spawn in Container

```bash
kubectl exec -n detection-test attacker -- /bin/sh -c "whoami"
```

**Expected Falco alert:** `Terminal shell in container` or `Shell spawned in container`

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --since=1m | grep -i "shell"
```

---

## Test 2: Crypto Mining DNS Lookup

```bash
kubectl exec -n detection-test attacker -- nslookup pool.minexmr.com 2>/dev/null || true
```

**Expected Falco alert:** `Detect crypto mining DNS lookup`

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --since=1m | grep -i "crypto\|mining"
```

---

## Test 3: Sensitive File Access

```bash
kubectl exec -n detection-test attacker -- cat /etc/shadow 2>/dev/null || true
```

**Expected Falco alert:** `Read sensitive file untrusted`

---

## Test 4: Data Exfiltration (Outbound Transfer)

```bash
kubectl exec -n detection-test attacker -- wget -q -O /dev/null http://example.com 2>/dev/null || true
```

**Expected Falco alert:** depends on rules — may trigger `Outbound connection to untrusted IP`

---

## Test 5: Persistence Attempt

```bash
kubectl exec -n detection-test attacker -- sh -c "echo '* * * * * echo pwned' > /tmp/crontab.test" 2>/dev/null || true
```

**Expected Falco alert:** `Crontab modification detected` or `Write to persistence location`

---

## Test 6: K8s API Access

```bash
kubectl exec -n detection-test attacker -- sh -c \
  "wget -qO- https://kubernetes.default.svc/api/v1/namespaces --header 'Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null)' -T 3 2>/dev/null" || true
```

**Expected Falco alert:** `Contact K8s API server from container` (if SA token is mounted)

---

## Score Your Detection

| Test | Expected Alert | Detected? |
|------|---------------|-----------|
| Shell spawn | Terminal shell in container | [ ] |
| Crypto mining DNS | Detect crypto mining | [ ] |
| Sensitive file read | Read sensitive file | [ ] |
| Data exfiltration | Outbound connection | [ ] |
| Persistence attempt | Crontab modification | [ ] |
| K8s API access | Contact K8s API | [ ] |

**Target: 5/6 or better.** If a test doesn't fire, check the Falco rules and allowlist.

---

## Cleanup

```bash
kubectl delete namespace detection-test
```

---

## What's Next

Runtime security is done. Your detection stack is deployed, tuned, validated, and alerting.

Next packages:
- **04-cloud-security** — AWS controls, Terraform, IAM, GuardDuty
- **05-compliance-ready** — NIST mapping, FedRAMP evidence, POA&M
