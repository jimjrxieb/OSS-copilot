# Testing Pipeline

> End-to-end pipeline validation. Runs a small dataset through
> every step to verify the pipeline works before real training.

---

## Purpose

Before running a full training cycle (hours), run the testing pipeline
(minutes) to verify:

1. ETL correctly parses your data format
2. Chunking produces valid training files
3. Training starts without errors (1 epoch, 100 examples)
4. Merge produces a loadable model
5. Eval framework runs and produces results

---

## Test Dataset

```
testing-pipeline/
├── test-data/
│   └── sample.jsonl         ← 100 example training set
├── run-test-pipeline.sh     ← Runs all 7 steps on test data
└── expected-output/         ← What correct output looks like
```

---

## Usage (placeholder)

```bash
cd Mlops/testing-pipeline
bash run-test-pipeline.sh

# Expected: all 7 steps complete without error
# Runtime: ~5 minutes on GPU, ~15 minutes on CPU
```
