# SageMaker Pipeline

> AWS-managed training for when local GPU isn't enough.
> Same data, same LoRA config, same eval. Training runs on AWS.

---

## When to Use SageMaker vs. Local

| Scenario | Use Local | Use SageMaker |
|----------|-----------|---------------|
| 3B model, <50k examples | Yes — fits in 24GB VRAM | Overkill |
| 8B model, >100k examples | Slow on consumer GPU | Yes — ml.g5.xlarge |
| Multi-GPU training | Not supported locally | Yes — distributed |
| No local GPU | Not possible | Yes — on-demand GPU |
| Air-gapped / data-sensitive | Yes — nothing leaves your machine | Depends on VPC |
| AWS ML cert prep | — | Yes — hands-on practice |

---

## Architecture

```
local-pipeline/03-chunked-untrained/
    ↓ tools/upload-data.sh          (push chunk to S3)
s3://your-bucket/training-data/
    ↓ tools/submit-job.sh           (SageMaker Training Job)
    │   └── HuggingFace DLC + Unsloth (GPU container)
    │   └── Spot instances (60-90% cheaper)
    │   └── Per-second billing
s3://your-bucket/model-artifacts/
    ↓ tools/download-model.sh       (pull artifacts to local)
model-registry/vX.X/merged/
    ↓ local-pipeline convert + eval (same tools as local)
```

---

## Playbooks (Step-by-Step Guides)

| # | Playbook | What You'll Do | Time |
|---|----------|---------------|------|
| 01 | [Setup IAM & S3](playbooks/01-setup-iam-s3.md) | Create role, bucket, permissions | 15 min |
| 02 | [Submit Training Job](playbooks/02-submit-training-job.md) | Upload data, launch GPU training | 10 min |
| 03 | [Monitor & Download](playbooks/03-monitor-download.md) | Watch job, pull artifacts, eval | 10 min |
| 04 | [Deploy Endpoint](playbooks/04-deploy-endpoint.md) | Serve model via SageMaker endpoint | 15 min |
| 05 | [Cost Optimization](playbooks/05-cost-optimization.md) | Spot, auto-shutdown, right-sizing | 10 min |

---

## Cost

| Instance | GPU | VRAM | On-Demand | Spot (~70% off) | Time for 5k chunk |
|----------|-----|------|-----------|-----------------|-------------------|
| `ml.g4dn.xlarge` | T4 | 16GB | $0.74/hr | ~$0.25/hr | ~30 min |
| `ml.g5.xlarge` | A10G | 24GB | $1.41/hr | ~$0.50/hr | ~20 min |
| `ml.g5.2xlarge` | A10G | 24GB | $1.52/hr | ~$0.55/hr | ~15 min |
| `ml.p3.2xlarge` | V100 | 16GB | $3.83/hr | ~$1.20/hr | ~12 min |

**Total cost per chunk with spot: $0.10-$0.25.**
Full 5-chunk training: **$1-3 total.**

---

## Tools

| Tool | What It Does |
|------|-------------|
| `tools/setup-sagemaker.sh` | Create IAM role, S3 bucket, verify permissions |
| `tools/upload-data.sh` | Push training chunk to S3 |
| `tools/submit-job.sh` | Launch SageMaker training job (spot or on-demand) |
| `tools/monitor-job.sh` | Watch job status, stream CloudWatch logs |
| `tools/download-model.sh` | Pull model artifacts from S3 to local |
| `tools/deploy-endpoint.sh` | Create SageMaker real-time endpoint |
| `tools/cleanup.sh` | Delete endpoint, remove S3 data, cleanup IAM |

All tools read from `values.yaml` — same pattern as local-pipeline.
