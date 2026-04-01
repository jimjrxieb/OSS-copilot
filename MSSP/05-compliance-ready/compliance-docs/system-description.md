# System Description — {{CLIENT_NAME}}

## 1. System Overview

{{APP_NAME}} is a {{SYSTEM_DESCRIPTION}} operated by {{CLIENT_NAME}}.

**System Type**: {{SYSTEM_TYPE}} (e.g., Major Application, General Support System)

**Cloud Service Model**: {{SERVICE_MODEL}} (SaaS / PaaS / IaaS)

**Cloud Deployment Model**: {{DEPLOYMENT_MODEL}} (Public / Private / Hybrid / Community)

## 2. System Function and Purpose

{{APP_NAME}} provides the following capabilities:

- {{CAPABILITY_1}}
- {{CAPABILITY_2}}
- {{CAPABILITY_3}}

**Federal Information Processed**: {{FEDERAL_DATA_DESCRIPTION}}

## 3. Users and Roles

| Role | Count | Access Level | Authentication |
|------|-------|-------------|----------------|
| System Administrator | {{ADMIN_COUNT}} | Full system access | MFA + VPN |
| Application User | {{USER_COUNT}} | Application features | MFA |
| Auditor | {{AUDITOR_COUNT}} | Read-only system view | MFA |
| CI/CD Service Account | {{SA_COUNT}} | Deployment pipeline | Token-based |

## 4. Technology Stack

| Layer | Component | Version | Purpose |
|-------|-----------|---------|---------|
| Frontend | {{FRONTEND_TECH}} | {{VERSION}} | User interface |
| Backend API | {{BACKEND_TECH}} | {{VERSION}} | Business logic |
| Database | {{DB_TECH}} | {{VERSION}} | Data persistence |
| Container Runtime | Kubernetes | {{K8S_VERSION}} | Container orchestration |
| Service Mesh | {{MESH_TECH}} | {{VERSION}} | mTLS, traffic management |
| Monitoring | Prometheus + Grafana | — | Metrics and alerting |
| Runtime Security | Falco | — | Syscall monitoring |
| CI/CD | GitHub Actions | — | Build, test, deploy pipeline |

## 5. Data Flow

```
User → Load Balancer (TLS) → Ingress Controller → Frontend Pod
                                                      │
                                                      ▼
                                                  API Pod (ClusterIP)
                                                      │
                                                      ▼
                                                  Database Pod (ClusterIP)
                                                      │
                                                      ▼
                                                  Encrypted PVC (EBS/KMS)
```

All inter-service traffic encrypted via mTLS. External traffic terminates TLS at ingress.

## 6. Network Architecture

| Zone | Components | Access |
|------|-----------|--------|
| Public | Load Balancer, Ingress | Internet-facing (HTTPS only) |
| Application | Frontend, API pods | Internal only (ClusterIP) |
| Data | Database, cache pods | Internal only, restricted by NetworkPolicy |
| Management | Monitoring, logging | Internal only, restricted by RBAC |

## 7. External Interconnections

| System | Owner | Direction | Data | Protocol | Authorization |
|--------|-------|-----------|------|----------|--------------|
| {{EXTERNAL_SYSTEM_1}} | {{OWNER}} | {{DIRECTION}} | {{DATA}} | HTTPS/TLS | {{AUTH_TYPE}} |

## 8. Ports, Protocols, and Services

| Port | Protocol | Service | Direction | Justification |
|------|----------|---------|-----------|--------------|
| 443 | HTTPS | Application ingress | Inbound | User access |
| 53 | DNS | Service discovery | Outbound | K8s internal |
| {{DB_PORT}} | TCP/TLS | Database | Internal | Data persistence |

---

*Replace all {{PLACEHOLDER}} values with client-specific information.*
