# Data Lake — Raw Data Generation & Curation

> Where training data is born. Generators, synthetic pipelines, and
> quality validation before data enters the training pipeline.

---

## Purpose

The data lake is the factory floor. Raw data from multiple sources gets
generated, validated, and curated here before moving to
`local-pipeline/01-raw-data-lake/` for training or
`rag-pipeline/01-unprocessed/` for RAG ingestion.

```
SOURCES                          GENERATORS                    OUTPUTS
───────                          ──────────                    ───────
Operational logs                 generate_*.py scripts         → JSONL for training
Scanner findings                 synthetic pipeline            → Markdown for RAG
Documentation                   domain generators             → YAML for RAG
Incident reports                 (CKS, CKA, AWS, etc.)
```

---

## Data Flow

```
data-lake/
├── generators/              ← Scripts that create training JSONL
│   ├── generate_cks.py         CKS exam domain scenarios
│   ├── generate_cka.py         CKA admin operations
│   ├── generate_aws.py         AWS security scenarios
│   ├── generate_falco.py       Runtime detection scenarios
│   └── generate_nist.py        Compliance control examples
│
├── synthetic/               ← Automated log → training converter
│   └── pipeline.py             Reads operational logs, generates JSONL
│
├── curated/                 ← Quality-reviewed datasets
│   └── manifest.json           SHA256 + example count per dataset
│
└── outputs/                 ← Ready for pipeline consumption
    ├── → local-pipeline/01-raw-data-lake/
    └── → rag-pipeline/01-unprocessed/
```

---

## Quality Gates

Every dataset must pass before entering the training pipeline:

- [ ] Valid JSONL (every line parses as JSON)
- [ ] ChatML format (messages array with role + content)
- [ ] Content length >20 characters per message
- [ ] No [NEEDS CORRECTION] markers
- [ ] No duplicate entries (MD5 deduplication)
- [ ] Domain labels assigned
- [ ] SHA256 checksum recorded in manifest
