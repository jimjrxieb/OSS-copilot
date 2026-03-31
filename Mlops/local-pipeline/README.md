# Local Training Pipeline

> 7-step fine-tuning pipeline. Raw JSONL in, GGUF model out.
> Runs on a single GPU (24GB VRAM) or CPU with patience.

---

## Data Flow

```
01-raw-data-lake/         ← DROP YOUR DATA HERE (JSONL, ChatML format)
    ↓ etl_pipeline.py        (deduplicate, normalize, auto-label)
02-ETL-data/              ← Cleaned, normalized JSONL
    ↓ chunk_data.py           (split into 10k chunks + 5% eval holdout)
03-chunked-untrained/     ← Training-ready chunks
    ↓ train.py                (LoRA fine-tune with Unsloth, 4-bit)
04-trained-data/          ← LoRA checkpoints per chunk
    ↓ merge_model.py          (merge LoRA adapter into base model)
../model-registry/        ← Full merged model (HuggingFace format)
    ↓ convert_gguf.py         (quantize to GGUF for Ollama)
../model-registry/        ← model.gguf ready for Ollama
    ↓ eval_bridge.py          (benchmark across domain categories)
../eval/results/          ← Accuracy per category + hallucination check
    ↓ feedback_loop.py        (generate new training data for weak areas)
01-raw-data-lake/         ← Gap data feeds back into step 1 (loop closes)
```

---

## Scripts (to be implemented)

| # | Script | Input | Output | Status |
|---|--------|-------|--------|--------|
| 1 | `etl_pipeline.py` | 01-raw-data-lake/*.jsonl | 02-ETL-data/combined.jsonl | Placeholder |
| 2 | `chunk_data.py` | 02-ETL-data/*.jsonl | 03-chunked-untrained/chunk_NNN.jsonl | Placeholder |
| 3 | `train.py` | 03-chunked-untrained/chunk_NNN.jsonl | 04-trained-data/vX.X/ | Placeholder |
| 4 | `merge_model.py` | 04-trained-data/vX.X/lora/ | model-registry/vX.X/merged/ | Placeholder |
| 5 | `convert_gguf.py` | model-registry/vX.X/merged/ | model-registry/vX.X/model.gguf | Placeholder |
| 6 | `eval_bridge.py` | model-registry/vX.X/merged/ | eval/results/run_YYYYMMDD/ | Placeholder |
| 7 | `feedback_loop.py` | eval/results/run_YYYYMMDD/ | 01-raw-data-lake/eval-gaps/ | Placeholder |

---

## Training Config (reference)

```yaml
# config.yaml
base_model: "unsloth/Llama-3.2-3B-Instruct"  # or 8B for reasoning model
lora:
  r: 64
  alpha: 128
  target_modules: ["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]
  dropout: 0.0
training:
  batch_size: 4
  gradient_accumulation: 8       # effective batch = 32
  learning_rate: 2e-5
  scheduler: cosine
  epochs_per_chunk: 2
  max_seq_length: 2048
  quantization: "4bit"
chunk_size: 10000                # examples per chunk
eval_holdout: 0.05               # 5% reserved for evaluation
```

---

## Data Format (ChatML)

All training data must be in ChatML JSONL format:

```json
{"messages": [
  {"role": "system", "content": "You are a security engineer."},
  {"role": "user", "content": "How do I fix a privileged container?"},
  {"role": "assistant", "content": "Add securityContext with runAsNonRoot: true..."}
]}
```

---

## Directory Details

### 01-raw-data-lake/
Drop raw JSONL files here. Multiple formats accepted by ETL:
- ChatML (messages array) — used as-is
- Alpaca (instruction/input/output) — converted to ChatML
- Q&A (question/answer) — converted to ChatML

### 02-ETL-data/
ETL output. One combined JSONL per run. Deduplicated, normalized,
with auto-labels (category, domain).

### 03-chunked-untrained/
Training-ready chunks. Each file is exactly 10k examples (configurable).
`manifest.json` tracks chunk lineage and status.

### 04-trained-data/
LoRA checkpoints organized by model version. Each version has one
subdirectory per trained chunk with adapter weights and training logs.

### 05-data-quality/
Curation tools: profiling, filtering, semantic deduplication.
Run these BEFORE training to verify data quality.

### 06-eval-holdout/
5% of chunked data reserved for evaluation. Never trained on.
Used by `eval_bridge.py` to check for overfitting.
