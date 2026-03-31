# Experiments

> Track every training run with params, metrics, and notes.
> Reproducible by convention, not by platform.

---

## Convention

```
experiments/
└── exp-NNN-description/
    ├── params.yaml           ← Hyperparameters, data source, base model
    ├── metrics.json          ← Eval results (accuracy per category)
    └── notes.md              ← Why this experiment, what happened, what's next
```

---

## Example

```
experiments/
├── exp-001-bulk-training/
│   ├── params.yaml           # 284k examples, no curation
│   ├── metrics.json          # 28.5% overall — failed
│   └── notes.md              # Data was 85% garbage. Quality > quantity.
│
├── exp-002-curated-corpus/
│   ├── params.yaml           # 42,276 curated examples, 6-gate pipeline
│   ├── metrics.json          # In progress
│   └── notes.md              # Hypothesis: curated data + fresh LoRA
│
└── exp-003-8b-reasoning/
    ├── params.yaml           # 8B model, RAG-augmented
    ├── metrics.json          # Deployed, eval framework mismatch
    └── notes.md              # Qualitatively good, needs proper benchmarks
```

---

## params.yaml Template

```yaml
experiment: exp-NNN
date: YYYY-MM-DD
base_model: "unsloth/Llama-3.2-3B-Instruct"
training_data:
  source: "local-pipeline/03-chunked-untrained/"
  examples: 42276
  curation: "6-gate pipeline (curate_corpus.py)"
  sha256: "abc123..."
lora:
  r: 64
  alpha: 128
training:
  epochs: 2
  batch_size: 4
  learning_rate: 2e-5
hypothesis: "Quality data + fresh LoRA from base beats bulk training"
```
