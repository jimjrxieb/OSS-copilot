# SageMaker Pipeline

> AWS-managed training for when local GPU isn't enough.
> Same data flow as local-pipeline, but runs on SageMaker.

---

## When to Use SageMaker vs. Local

| Scenario | Use Local | Use SageMaker |
|----------|-----------|---------------|
| 3B model, <50k examples | Yes — fits in 24GB VRAM | Overkill |
| 8B model, >100k examples | Maybe — slow on consumer GPU | Yes — faster with ml.g5 |
| Multi-GPU training | Not supported locally | Yes — distributed training |
| No local GPU | Not possible | Yes — cloud GPU on demand |
| Air-gapped / data-sensitive | Yes — nothing leaves your machine | Depends on VPC config |

---

## Pipeline (placeholder)

```
local-pipeline/03-chunked-untrained/
    ↓ upload to S3
s3://your-bucket/training-data/
    ↓ SageMaker Training Job
s3://your-bucket/model-artifacts/
    ↓ download merged model
model-registry/vX.X/merged/
    ↓ convert_gguf.py (local)
model-registry/vX.X/model.gguf
    ↓ eval_bridge.py (local)
eval/results/
```

Same data, same format, same eval. Just the training step runs on AWS.
