# 02 — Audit Logging (AU)

> NIST 800-53: AU-2, AU-3, AU-6, AU-12 — What to log, what to include, how to review, where to generate.

---

## AU-2 / AU-12: Audit Events

### Kubernetes
```bash
# Verify EKS control plane logging (all 5 types)
aws eks describe-cluster --name $CLUSTER \
  --query 'cluster.logging.clusterLogging[0].{Enabled:enabled,Types:types}'
# Expected: enabled=true, types=[api, audit, authenticator, controllerManager, scheduler]
```

### AWS
```bash
# Verify CloudTrail is logging
aws cloudtrail get-trail-status --name org-trail --query '{Logging:IsLogging,LatestDelivery:LatestDeliveryTime}'

# Verify VPC Flow Logs
aws ec2 describe-flow-logs --query 'FlowLogs[*].[FlowLogId,ResourceId,LogGroupName]' --output table
```

**Evidence:** All 5 EKS log types enabled, CloudTrail active, VPC Flow Logs active.

---

## AU-3: Content of Audit Records

Every log entry must include: timestamp, user identity, source IP, action, resource, outcome.

```bash
# Verify K8s audit log format
aws logs filter-log-events --log-group-name /aws/eks/$CLUSTER/cluster \
  --filter-pattern '{ $.verb = "create" }' --limit 1 | \
  jq '.events[0].message | fromjson | {user:.user.username, verb:.verb, resource:.objectRef.resource, timestamp:.requestReceivedTimestamp}'
```

---

## AU-6: Audit Review

Weekly review checklist:
- [ ] Falco alerts (Critical/High) reviewed and resolved
- [ ] Failed auth attempts investigated
- [ ] Unusual API calls reviewed
- [ ] GuardDuty findings triaged
- [ ] CloudTrail anomalies checked

**Evidence:** Weekly review log with reviewer name, date, findings, and actions taken.

---

## Log Retention

| Source | Retention | Storage |
|--------|-----------|---------|
| EKS control plane | 1 year | CloudWatch |
| Application logs | 90 days | Loki / CloudWatch |
| CloudTrail | 1 year | S3 (Standard → IA → Glacier) |
| VPC Flow Logs | 90 days | CloudWatch |
| Falco alerts | 90 days | Loki / SIEM |

---

## Next Step

Go to [03-configuration-management.md](03-configuration-management.md).
