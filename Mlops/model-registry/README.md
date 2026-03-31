# Model Registry

> Versioned model artifacts. Champion/challenger promotion pattern.

---

## Structure

```
model-registry/
├── champion/                ← Currently serving in production
│   └── model_card.md           What it is, how it was trained, benchmarks
│
├── challenger/              ← Awaiting eval results to promote
│   └── model_card.md           Same format, compared against champion
│
└── versions/                ← Historical checkpoints
    ├── v1.0/
    │   ├── lora/               LoRA adapter weights
    │   ├── merged/             Full merged model (HuggingFace format)
    │   └── model.gguf          Quantized for Ollama serving
    └── v2.0/
        └── ...
```

---

## Promotion Gate

A challenger promotes to champion when:

| Criterion | Threshold |
|-----------|-----------|
| Domain accuracy (each category) | >= 50% |
| Weighted total accuracy | >= 60% |
| Hallucinated commands | 0 (zero tolerance) |
| Regression vs. champion | No category drops >5% |

---

## Model Card Template

```markdown
# Model Card — [Model Name]

## Overview
- Base model: [e.g., Llama-3.2-3B-Instruct]
- Fine-tuning: LoRA (r=64, alpha=128)
- Training data: [X] examples, [Y] domains
- Version: [vX.X]

## Intended Use
[What this model is for]

## Training Data
[Source, size, curation method]

## Evaluation Results
| Category | Accuracy |
|----------|----------|
| [domain] | [X%] |

## Limitations
[What it can't do, known failure modes]

## Ethical Considerations
[Bias, safety, deployment constraints]
```
