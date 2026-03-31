# Evaluation Framework

> Benchmark your model across domains and tasks.
> Detect hallucinations. Compare against the champion.

---

## Structure

```
eval/
├── benchmarks/              ← Test suites by domain
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
└── eval_bridge.py           ← Main evaluation script (placeholder)
```

---

## Benchmark Format

```json
{
  "category": "kubernetes",
  "subcategory": "pod-security",
  "question": "How do you enforce non-root containers in Kubernetes?",
  "expected_keywords": ["runAsNonRoot", "securityContext", "true"],
  "difficulty": "intermediate"
}
```

---

## Hallucination Detection

The eval framework checks for:
- Fabricated CVE IDs (CVE-9999-*)
- Fabricated CIS benchmark numbers (CIS 99.*)
- Invented kubectl commands
- Non-existent tool names
- Made-up NIST control IDs
