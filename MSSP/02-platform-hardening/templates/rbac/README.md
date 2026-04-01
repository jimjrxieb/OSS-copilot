# RBAC Templates

Least-privilege RBAC templates for cluster hardening engagements.

## Templates

| Template | Scope | Use Case |
|----------|-------|----------|
| `developer.yaml` | Namespace (Role) | Dev teams — read most, write own workloads, exec/port-forward |
| `platform-eng.yaml` | Cluster (ClusterRole) | Platform/SRE — cluster-wide read, infra + policy write |
| `admin.yaml` | Cluster (ClusterRole) | Admins — full explicit access, no wildcards, audit-required |

## Customization

1. **Developer**: replace `NAMESPACE` and `TEAM_NAME`, then apply:
   ```bash
   sed 's/NAMESPACE/my-app/g; s/TEAM_NAME/backend/g' developer.yaml | kubectl apply -f -
   ```

2. **Platform Engineer**: update the `subjects` group name if your IdP uses a different convention.

3. **Admin**: replace `ADMIN_USER` with actual usernames. Add `gp-copilot/justification` annotation per subject.

## Auditing

```bash
# List who has cluster-admin
kubectl get clusterrolebindings -o json | jq '.items[] | select(.roleRef.name=="cluster-admin") | .subjects'

# Run the full RBAC audit
./tools/rbac-audit.sh

# Review gp-copilot managed bindings
kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=gp-copilot
```

## Design Decisions

- No wildcards (`"*"`) in verbs or resources — every permission is explicit and auditable.
- Admission webhooks are read-only even for admins — modifying these bypasses security controls.
- Developer role uses namespace-scoped Role, not ClusterRole, to enforce blast radius.
