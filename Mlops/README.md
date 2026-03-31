# MLOps — Open Source ML Lifecycle

> Fine-tune, evaluate, and serve local LLMs with open source tooling.
> This is the open source version of what SageMaker, Vertex AI, and
> Azure ML do — running on your own hardware.

---

## What This Is

A complete ML lifecycle for fine-tuning small language models (3B-8B) on
domain-specific data, building RAG pipelines with ChromaDB, and evaluating
model quality — all running locally on consumer GPUs or cloud instances.

No SageMaker. No Vertex AI. No API keys to OpenAI.
Just Unsloth, Ollama, ChromaDB, and your data.

---

## Architecture

```
data-lake/                    ← Raw data generation & curation
    ↓
local-pipeline/               ← 7-step fine-tuning pipeline
  01-raw-data-lake/              Drop JSONL here
  02-ETL-data/                   Cleaned, deduplicated, normalized
  03-chunked-untrained/          Split into training chunks (10k examples)
  04-trained-data/               LoRA checkpoints + merged models
  05-data-quality/               Curation & filtering tools
  06-eval-holdout/               5% holdout for evaluation
    ↓
rag-pipeline/                 ← 7-stage document ingestion
  01-unprocessed/                Drop documents here (MD, JSONL, YAML, Rego)
  02-prep-factory/               Parse, sanitize, chunk, label, validate, route
  03-preprocessed/               Quality-reviewed JSONL
  04-ingesting/                  Embed & store
  05-vector-store/               ChromaDB persistent store
    ↓
model-registry/               ← Versioned model artifacts
  champion/                      Currently serving
  challenger/                    Awaiting eval promotion
    ↓
eval/                         ← Benchmark framework
  benchmarks/                    Domain-specific test suites
  results/                       Timestamped eval runs
    ↓
experiments/                  ← Reproducible experiment tracking
  exp-NNN-name/                  params.yaml + metrics.json + notes.md
    ↓
tests/                        ← Quality gates
  test_data_quality.py           MANDATORY before training
  test_model_behavior.py         Smoke tests after training
  test_serving.py                Health checks after deploy
```

---

## The Two Pipelines

### Training Pipeline (local-pipeline/)

Fine-tune a base model on your domain data. 7 steps, closed loop.

```
01-raw-data-lake/ → etl → 02-ETL-data/ → chunk → 03-chunked/ → train → 04-trained/
                                                                            ↓
model-registry/ ← merge ← LoRA checkpoints    eval/ ← evaluate ← GGUF
                                                        ↓
                                               feedback loop → 01-raw-data-lake/
                                               (gap data for next training cycle)
```

| Step | Script | What It Does |
|------|--------|-------------|
| 1. ETL | `etl_pipeline.py` | Deduplicate, normalize to ChatML, auto-label |
| 2. Chunk | `chunk_data.py` | Split into 10k chunks + 5% eval holdout |
| 3. Train | `train.py` | LoRA fine-tune with Unsloth (4-bit quantized) |
| 4. Merge | `merge_model.py` | Merge LoRA adapter into base model |
| 5. Convert | `convert_gguf.py` | Quantize to GGUF for Ollama serving |
| 6. Evaluate | `eval_bridge.py` | Benchmark across domain categories |
| 7. Feedback | `feedback_loop.py` | Generate new training data for weak areas |

### RAG Pipeline (rag-pipeline/)

Ingest documents into a vector store for retrieval-augmented generation.

```
01-unprocessed/ → discover → parse → sanitize → chunk → label → validate → route
                                                                            ↓
05-vector-store/ ← embed & ingest ← 03-preprocessed/
```

| Stage | What It Does |
|-------|-------------|
| 1. Discover | Scan input directories, categorize by file type |
| 2. Parse | Format-specific parsing (JSONL, Markdown, YAML, Rego) |
| 3. Sanitize | Quality gates (dedup, PII redaction, structure validation) |
| 4. Chunk | Normalize to JSONL, overlap chunking (512 tokens, 12.5% overlap) |
| 5. Label | 3-tier labeling (regex → pattern match → optional LLM classify) |
| 6. Validate | Token count, format validation |
| 7. Route | Assign to ChromaDB collections by domain/type |
| 8. Ingest | Embed with nomic-embed-text (768-dim), store to ChromaDB |

---

## Key Technical Specs

| Component | Specification |
|-----------|---------------|
| **Base Models** | Llama 3.2-3B (fast), Llama 3.1-8B (reasoning) |
| **Fine-tuning** | LoRA via Unsloth (r=64, alpha=128, 4-bit) |
| **Serving** | Ollama (GGUF format, local inference) |
| **Embeddings** | nomic-embed-text (768 dimensions, via Ollama) |
| **Vector Store** | ChromaDB (persistent, local) |
| **Training Data** | ChatML format (system/user/assistant messages) |
| **Chunk Size** | Training: 10k examples. RAG: 512 tokens with overlap. |
| **Eval** | Domain benchmarks + task benchmarks + hallucination detection |
| **Hardware** | 24GB VRAM (training), 8GB VRAM (inference), CPU fallback |

---

## What This Replaces (Time Saved)

| Enterprise Service | What It Does | What You Run Instead |
|-------------------|-------------|---------------------|
| SageMaker Training | Managed fine-tuning jobs | Unsloth on local GPU |
| SageMaker Endpoints | Model serving | Ollama (one command) |
| Vertex AI Pipelines | Orchestrated ML workflows | Shell scripts + Python |
| Azure ML Workspaces | Experiment tracking | experiments/ folder convention |
| Pinecone/Weaviate | Managed vector DB | ChromaDB (local, free) |
| OpenAI API | LLM inference | Ollama + your fine-tuned model |
| Weights & Biases | Experiment tracking | params.yaml + metrics.json |

**Time saved:** Instead of 2-3 weeks configuring managed ML services,
you're training on local hardware in hours. The trade-off is no auto-scaling
and no managed infrastructure — but for fine-tuning 3B-8B models on
domain data, you don't need managed infrastructure.

---

## Data Flow Summary

```
YOUR DATA                        YOUR MODELS                    YOUR APPS
─────────                        ───────────                    ─────────
data-lake/                       model-registry/
  generators → raw JSONL           champion/model.gguf  ──→  Ollama serving
      ↓                            challenger/model.gguf       ↓
local-pipeline/                                            Your app queries
  01-raw → 02-ETL → 03-chunk                              Ollama API
  → 04-trained → merge → GGUF                               ↓
      ↓                                                  RAG augmented
eval/                            rag-pipeline/            responses
  benchmarks → results             01-unprocessed → ...      ↑
  feedback → raw (loop)            → 05-vector-store  ──→  ChromaDB
                                     (nomic-embed-text)    similarity
                                                           search
```

---

## Getting Started

1. **Put your training data** in `local-pipeline/01-raw-data-lake/` (JSONL, ChatML format)
2. **Put your documents** in `rag-pipeline/01-unprocessed/` (Markdown, JSONL, YAML)
3. **Follow the pipeline scripts** in order (ETL → chunk → train → merge → convert → eval)
4. **Run tests** before and after training (`tests/test_data_quality.py`)
5. **Track experiments** in `experiments/exp-NNN-name/` (params + metrics + notes)

Detailed playbooks for each step are in the pipeline directories.
