# 03 — Runtime Security Playbooks

> Deploy runtime detection before the app goes live. Deploy the app. Monitor and respond after.

This package has three phases:

1. **Pre-deploy** (00-04) — Install Falco, monitoring, logging. Verify containers are hardened. All before the first application pod starts.
2. **Deploy** (05) — Deploy the application through ArgoCD with security gates on sync.
3. **Post-deploy** (06-09) — Tune detection, forward alerts, handle incidents, validate coverage.

Enterprise tools (Sysdig Secure, CrowdStrike Falcon, Datadog Security) take over in production. This is your staging runtime stack.

---

## Follow the Playbooks in Order

| Phase | # | Playbook | What You Do | Time |
|-------|---|----------|-------------|------|
| **Pre-deploy** | 00 | [Install Prerequisites](00-install-prerequisites.md) | Get tools ready | 5 min |
| **Pre-deploy** | 01 | [Deploy Falco](01-deploy-falco.md) | Runtime syscall monitoring | 15 min |
| **Pre-deploy** | 02 | [Deploy Monitoring](02-deploy-monitoring.md) | Prometheus alerts + Grafana dashboards | 10 min |
| **Pre-deploy** | 03 | [Deploy Logging](03-deploy-logging.md) | Fluent Bit + Loki | 10 min |
| **Pre-deploy** | 04 | [Verify Containers](04-verify-container-hardening.md) | Final security gate | 10 min |
| **Deploy** | 05 | [Deploy Application](05-deploy-application.md) | ArgoCD with security hooks | 20 min |
| **Post-deploy** | 06 | [Tune Falco](06-tune-falco.md) | Reduce noise to < 50 alerts/day | 30 min |
| **Post-deploy** | 07 | [SIEM Integration](07-siem-integration.md) | Forward alerts to Splunk/Elastic/Wazuh | 15 min |
| **Post-deploy** | 08 | [Incident Response](08-incident-response.md) | Timeline, forensics, contain, report | As needed |
| **Post-deploy** | 09 | [Detection Validation](09-detection-validation.md) | Trigger attacks, verify Falco detects | 15 min |

---

## Setup

```bash
export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
kubectl cluster-info
```

---

## The Tools

| Tool | What It Does | Install |
|------|-------------|---------|
| **Falco** | Kernel-level syscall monitoring | Helm chart |
| **Falco Exporter** | Prometheus metrics from Falco | Helm chart |
| **Prometheus** | Alert rules and metrics | Pre-existing or Helm |
| **Grafana** | Dashboards and visualization | Pre-existing or Helm |
| **Fluent Bit** | Log collection (DaemonSet) | Helm chart |
| **Loki** | Log storage and querying | Helm chart |
| **ArgoCD** | GitOps application delivery | Pre-existing |

---

## What's in This Directory

```
03-runtime-security/
  playbooks/          <- You are here
  tools/              <- Scripts the playbooks call
  falco-rules/        <- Custom Falco detection rules
  monitoring/         <- Prometheus alerts + Grafana dashboards
  templates/          <- ArgoCD hooks, Falco Helm values, observability configs
```

---

## How This Connects to Production

| This Package (Dev/Staging) | Production |
|---------------------------|------------|
| Falco (eBPF syscall monitoring) | Sysdig Secure, CrowdStrike Falcon |
| Prometheus + Grafana | Datadog, New Relic |
| Fluent Bit + Loki | Splunk, Elastic, Datadog Logs |
| Manual incident response | CrowdStrike IR, automated SOAR |
| ArgoCD security hooks | Same ArgoCD + enterprise admission |

Same detection patterns, same response procedures. The enterprise tools add ML anomaly detection, automated response, and global threat intelligence. This gives you the foundation they build on.
