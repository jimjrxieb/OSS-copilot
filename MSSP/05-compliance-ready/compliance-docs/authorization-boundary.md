# Authorization Boundary — {{CLIENT_NAME}}

## 1. Boundary Definition

The authorization boundary for {{APP_NAME}} encompasses all components necessary to deliver the cloud service offering, including:

**Within Boundary:**
- Application containers (frontend, backend API, workers)
- Database and cache services
- Kubernetes cluster (control plane + worker nodes)
- Container registry (ECR/GCR)
- CI/CD pipeline (GitHub Actions)
- Monitoring stack (Prometheus, Grafana, Falco)
- Logging infrastructure (ELK/Loki, CloudWatch)
- Load balancer and ingress controller
- Service mesh (Istio/Linkerd)
- Secrets management (AWS SSM / Sealed Secrets)
- Encryption keys (KMS)

**Outside Boundary (Inherited Controls):**
- Cloud infrastructure provider (AWS/GCP/Azure) — IaaS controls inherited
- DNS provider — network infrastructure inherited
- Identity Provider (Okta/Azure AD) — authentication infrastructure inherited
- CDN provider (CloudFront) — if applicable

## 2. Boundary Diagram

```
┌─────────────────── AUTHORIZATION BOUNDARY ───────────────────┐
│                                                                │
│  ┌──────────────────── Kubernetes Cluster ──────────────────┐ │
│  │                                                           │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │
│  │  │  Frontend    │  │  API        │  │  Database    │     │ │
│  │  │  Namespace   │  │  Namespace  │  │  Namespace   │     │ │
│  │  │             │  │             │  │             │     │ │
│  │  │  ┌────────┐ │  │  ┌────────┐ │  │  ┌────────┐ │     │ │
│  │  │  │ Web UI │ │  │  │ API    │ │  │  │ DB     │ │     │ │
│  │  │  │ Pods   │ │──│  │ Pods   │ │──│  │ Pods   │ │     │ │
│  │  │  └────────┘ │  │  └────────┘ │  │  └────────┘ │     │ │
│  │  └─────────────┘  └─────────────┘  └──────┬──────┘     │ │
│  │                                            │             │ │
│  │  ┌──────────────┐  ┌──────────────┐       │             │ │
│  │  │  Monitoring   │  │  Logging     │  ┌────┴────┐       │ │
│  │  │  Prometheus   │  │  Falco       │  │Encrypted│       │ │
│  │  │  Grafana      │  │  ELK/Loki   │  │  PVC    │       │ │
│  │  └──────────────┘  └──────────────┘  └─────────┘       │ │
│  │                                                           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐  │
│  │  CI/CD Pipeline │  │  Container     │  │  Secrets       │  │
│  │  GitHub Actions │  │  Registry (ECR)│  │  Manager (SSM) │  │
│  └────────────────┘  └────────────────┘  └────────────────┘  │
│                                                                │
│  ┌────────────────┐  ┌────────────────┐                      │
│  │  KMS Keys      │  │  Load Balancer │                      │
│  │  (Encryption)  │  │  (ALB/NLB)     │                      │
│  └────────────────┘  └────────────────┘                      │
│                                                                │
└────────────────────────────────────────────────────────────────┘
         │                    │                    │
    ┌────┴─────┐        ┌────┴─────┐        ┌────┴─────┐
    │   AWS    │        │  DNS     │        │  IdP     │
    │  (IaaS) │        │ Provider │        │ (Okta)   │
    └──────────┘        └──────────┘        └──────────┘
      INHERITED           INHERITED           INHERITED
```

## 3. Data Flow Across Boundary

| Flow | Source | Destination | Crosses Boundary? | Protection |
|------|--------|------------|-------------------|------------|
| User access | Internet | Load Balancer | Yes (inbound) | TLS 1.2+ |
| API calls | Frontend pod | API pod | No (internal) | mTLS |
| DB queries | API pod | Database pod | No (internal) | TLS + NetworkPolicy |
| Log shipping | Falco/apps | CloudWatch/S3 | Yes (outbound) | TLS + IAM |
| Image pull | K8s node | ECR | No (within boundary) | TLS + IAM |
| DNS resolution | K8s pod | DNS provider | Yes (outbound) | Standard DNS |

## 4. Inherited Controls

| Provider | Inherited Controls | FedRAMP Status |
|----------|-------------------|----------------|
| AWS (IaaS) | PE-* (Physical), PS-* (Personnel) | FedRAMP Authorized |
| {{IDP_PROVIDER}} | IA-2 (partial), IA-8 | {{IDP_FEDRAMP_STATUS}} |

## 5. Ports, Protocols, and Services at Boundary

| Direction | Port | Protocol | Service | Justification |
|-----------|------|----------|---------|--------------|
| Inbound | 443 | HTTPS | Application access | User-facing service |
| Outbound | 443 | HTTPS | AWS API calls | Infrastructure management |
| Outbound | 443 | HTTPS | Container registry | Image pulls |
| Outbound | 53 | DNS | Name resolution | Service discovery |
| Outbound | 443 | HTTPS | Log shipping | Audit log retention |

All other ports denied by default (SecurityGroup + NetworkPolicy).

---

*Replace all {{PLACEHOLDER}} values with client-specific information.*
*Update the boundary diagram to match your actual deployment architecture.*
