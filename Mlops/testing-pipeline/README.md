# Testing Pipeline — Eval, Experiments, and Validation

> Everything that tests your model lives here.
> Pipeline validation, domain benchmarks, experiment tracking.

---

## Structure

```
testing-pipeline/
├── test-data/               ← Small dataset for pipeline validation
│   └── sample.jsonl            100 examples — verify pipeline works before real training
│
├── benchmarks/              ← Domain-specific eval suites
│   ├── cloud/                  AWS, IAM, VPC scenarios
│   ├── kubernetes/             CKS, CKA, pod security
│   ├── devsecops/              SAST, SCA, CI/CD
│   ├── compliance/             CIS, NIST, SOC 2
│   ├── incident-response/      Triage, containment
│   └── tasks/                  Code gen, policy gen, fix gen
│
├── results/                 ← Timestamped eval runs
│   └── run_YYYYMMDD_HHMMSS/
│       ├── full_results.json      Per-question accuracy
│       ├── category_summary.json  Accuracy per domain
│       └── hallucinations.json    Detected fabrications
│
└── experiments/             ← Reproducible experiment tracking
    └── exp-NNN-description/
        ├── params.yaml         Hyperparameters, data source, base model
        ├── metrics.json        Eval results (accuracy per category)
        └── notes.md            Why, what happened, what's next
```

---

## Three Functions

### 1. Pipeline Validation (test-data/)

Before running a full training cycle (hours), run the test pipeline
(minutes) to verify every step works:

```bash
cd Mlops/testing-pipeline
bash run-test-pipeline.sh

# Verifies: ETL → chunk → train (1 epoch, 100 examples) → merge → eval
# Runtime: ~5 minutes on GPU, ~15 minutes on CPU
```

### 2. Model Evaluation (benchmarks/ → results/)

Benchmark your trained model across domain categories:

```bash
python3 eval_bridge.py --model-path ../model-registry/champion/merged/
```

**Benchmark format:**
```json
{
  "category": "kubernetes",
  "subcategory": "pod-security",
  "question": "How do you enforce non-root containers in Kubernetes?",
  "expected_keywords": ["runAsNonRoot", "securityContext", "true"],
  "difficulty": "intermediate"
}
```

**Hallucination detection** — the eval framework checks for:
- Fabricated CVE IDs (CVE-9999-*)
- Fabricated CIS benchmark numbers (CIS 99.*)
- Invented kubectl commands
- Non-existent tool names
- Made-up NIST control IDs

**Promotion gate** — a challenger model promotes to champion when:

| Criterion | Threshold |
|-----------|-----------|
| Domain accuracy (each category) | >= 50% |
| Weighted total accuracy | >= 60% |
| Hallucinated commands | 0 (zero tolerance) |
| Regression vs. champion | No category drops >5% |

### 3. Experiment Tracking (experiments/)

Every training run gets a folder with params, metrics, and notes:

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

**params.yaml template:**
```yaml
experiment: exp-NNN
date: YYYY-MM-DD
base_model: "unsloth/Llama-3.2-3B-Instruct"
training_data:
  source: "local-pipeline/03-chunked-untrained/"
  examples: 42276
  curation: "6-gate pipeline"
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

Reproducible by convention, not by platform. No Weights & Biases needed.
