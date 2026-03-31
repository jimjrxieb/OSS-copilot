# Data Lake — Where MSSP Findings Become Training Data

> This is where a junior data scientist lives. Scanner output comes in,
> clean training data goes out. Notebooks, generators, schemas, curation.

---

## What Flows Into Here

Every scanner in `MSSP/` produces JSON output. That output is raw material
for training and RAG. The data lake is the bridge between the security
scanning pipeline and the ML pipeline.

```
MSSP/01-code/       → Gitleaks, Semgrep, Trivy, Grype JSON
MSSP/02-cluster/    → Polaris, Checkov, Conftest, kube-bench JSON
MSSP/03-container/  → Trivy image, Hadolint, Falco JSON
MSSP/04-cloud/      → Prowler, Checkov IaC JSON
MSSP/05-compliance/ → NIST mapping, gap analysis JSON
        ↓
data-lake/intake/   ← ALL findings land here
        ↓
data-lake/notebooks/ ← Junior data scientist explores, cleans, transforms
        ↓
data-lake/curated/   ← Quality-reviewed datasets ready for pipeline
        ↓
local-pipeline/01-raw-data-lake/  ← Training data
rag-pipeline/01-unprocessed/       ← RAG documents
```

---

## Structure

```
data-lake/
├── intake/                  ← Raw findings from MSSP scanners
│   ├── mssp-findings/          Scanner JSON (gitleaks, semgrep, trivy, etc.)
│   ├── scan-logs/              Scanner execution logs
│   └── incident-reports/       Post-incident analysis docs
│
├── notebooks/               ← Jupyter notebooks for exploration & transformation
│   ├── explore-findings.ipynb     EDA on scanner output
│   ├── clean-training-data.ipynb  Transform findings → ChatML JSONL
│   └── rag-prep.ipynb             Transform docs → RAG-ready chunks
│
├── generators/              ← Scripts that create synthetic training data
│   ├── generate_cks.py         CKS exam domain scenarios
│   ├── generate_cka.py         CKA admin operations
│   ├── generate_aws.py         AWS security scenarios
│   └── generate_from_findings.py   Convert real findings → training examples
│
├── curated/                 ← Quality-reviewed, ready for pipeline
│   └── manifest.json           SHA256 + example count per dataset
│
├── data-schemas/            ← JSON contracts for every data format
│   └── README.md               Schema definitions
│
└── example-output/          ← Real scan results (Portfolio) showing the full workflow
    ├── README.md               Executive summary
    ├── 01-code/                Gitleaks, Semgrep, Trivy, Grype JSON
    └── 02-cluster/             Polaris, Checkov, Conftest JSON
```

---

## The Workflow

### 1. Intake — Scanner output arrives

```bash
# After running MSSP scanners, copy findings to the lake
cp MSSP/example-output/01-code/*.json Mlops/data-lake/intake/mssp-findings/
cp MSSP/example-output/02-cluster/*.json Mlops/data-lake/intake/mssp-findings/
```

### 2. Explore — Junior data scientist investigates

```bash
cd Mlops/data-lake/notebooks
jupyter notebook explore-findings.ipynb
```

Questions to answer:
- How many findings per scanner?
- What's the severity distribution?
- What patterns repeat across projects?
- Which findings make good training examples?

### 3. Transform — Findings become training data

A Semgrep finding like this:
```json
{
  "check_id": "python.lang.security.audit.dangerous-system-call",
  "path": "app.py",
  "start": {"line": 42},
  "extra": {"severity": "WARNING", "message": "Detected subprocess call with shell=True"}
}
```

Becomes a ChatML training example:
```json
{"messages": [
  {"role": "system", "content": "You are a security engineer reviewing code findings."},
  {"role": "user", "content": "Semgrep found 'dangerous-system-call' in app.py line 42. The code uses subprocess with shell=True. How do I fix this?"},
  {"role": "assistant", "content": "Replace subprocess.call(cmd, shell=True) with subprocess.run(cmd.split(), shell=False). The shell=True flag allows shell injection..."}
]}
```

### 4. Curate — Quality gate before pipeline

```bash
# Validate the transformed data
cd Mlops/tests
python3 -m pytest test_data_quality.py -v

# Move to pipeline input
cp Mlops/data-lake/curated/findings-training.jsonl Mlops/local-pipeline/01-raw-data-lake/
```

### 5. Repeat — Every engagement feeds the lake

```
Engagement 1 → scan → findings → training data → better model
Engagement 2 → scan → findings → training data → even better model
Engagement N → scan → findings → training data → domain expert model
```

Each engagement makes the model smarter. The data lake is the flywheel.

---

## Example Output

`example-output/` contains real scan results from running OSS-Copilot against
Portfolio. This shows the complete workflow:

- [example-output/README.md](example-output/README.md) — Executive summary
- [example-output/01-code/SUMMARY.md](example-output/01-code/SUMMARY.md) — Code scan analysis
- [example-output/02-cluster/SUMMARY.md](example-output/02-cluster/SUMMARY.md) — Cluster audit analysis

These are both the deliverable for the client AND the raw material for
training the next version of your model.

---

## Quality Gates

Every dataset must pass before leaving the data lake:

- [ ] Valid JSONL (every line parses as JSON)
- [ ] ChatML format (messages array with role + content)
- [ ] Content length >20 characters per message
- [ ] No `[NEEDS CORRECTION]` markers
- [ ] No duplicate entries (MD5 deduplication)
- [ ] Domain labels assigned
- [ ] SHA256 checksum recorded in manifest

---

## Who Works Here

**Junior data scientist** — This is your workspace. You:
- Explore scanner output in notebooks
- Write generators that create synthetic training data
- Transform real findings into training examples
- Validate data quality before it enters the pipeline
- Track dataset versions in manifest files

You don't need to understand the full ML pipeline. You need to understand
the security findings and how to turn them into good training examples.
