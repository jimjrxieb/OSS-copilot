# 07 — Incident Response (IR)

> NIST 800-53: IR-4, IR-5 — Incident handling, incident monitoring.

---

## IR-4: Incident Handling

### Define Severity Levels

| Severity | Definition | Response Time | Example |
|----------|-----------|---------------|---------|
| **P1** | Active breach, data at risk | 15 min | Crypto mining, credential exfiltration |
| **P2** | Security control bypassed | 1 hour | Pod running as root, public S3 |
| **P3** | Policy violation, no active threat | 4 hours | Missing NetworkPolicy, stale credentials |
| **P4** | Informational, improvement needed | Next business day | Dependency CVE with no fix |

### Response Phases

1. **Detect** — Falco alert, Prometheus alert, GuardDuty finding, or manual report
2. **Triage** — Confirm real threat vs false positive, assign severity
3. **Contain** — Isolate the affected resource (NetworkPolicy, SG quarantine, disable key)
4. **Eradicate** — Remove the threat (patch, rotate credentials, rebuild container)
5. **Recover** — Restore normal operations (redeploy, verify clean)
6. **Lessons Learned** — Document what happened, update procedures

### Containment Playbooks

**Compromised container:**
```bash
# Isolate with NetworkPolicy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-compromised
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      app: <compromised-app>
  policyTypes: [Ingress, Egress]
EOF

# Scale down
kubectl scale deploy/<name> --replicas=0 -n <namespace>
```

**Leaked credentials:**
```bash
aws iam update-access-key --user-name $USER --access-key-id $KEY --status Inactive
aws secretsmanager rotate-secret --secret-id <secret-name>
```

---

## IR-5: Incident Monitoring

```bash
# Alert routing — Falco → Prometheus → AlertManager → Slack/PagerDuty
# This should already be configured from 03-runtime-security

# Verify alerts are flowing
kubectl logs -n monitoring -l app=alertmanager --tail=10
```

### Incident Tracker

Maintain a log of all incidents:

```markdown
| Date | Severity | Description | MTTR | Root Cause | Action |
|------|----------|-------------|------|------------|--------|
| YYYY-MM-DD | P2 | Pod running as root | 30m | Missing securityContext | Added Kyverno policy |
```

**Evidence:** Incident tracker, MTTR metrics, annual tabletop exercise.

---

## Annual Tabletop Exercise

FedRAMP requires an annual IR exercise. Simulate an incident and walk through the response:

1. Choose scenario (e.g., "credential exfiltration detected by GuardDuty")
2. Walk through each phase with the team
3. Document decisions, timing, gaps
4. Update procedures based on findings

---

## Next Step

Go to [08-documentation-package.md](08-documentation-package.md) to produce the compliance deliverable.
