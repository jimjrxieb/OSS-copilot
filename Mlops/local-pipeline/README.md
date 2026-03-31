# Local Training Pipeline

> 3 tools. 4 stages. Data moves forward, never sits behind.

---

## How It Works

```
01-raw-data/         ← DROP YOUR JSONL HERE
    ↓ tools/etl_pipeline.py      (validate, normalize, dedup, MOVE)
02-ETL-data/         ← Cleaned, ready to chunk
    ↓ tools/chunk_data.py         (split into 5k chunks, MOVE)
03-chunked-untrained/ ← Training-ready chunks
    ↓ tools/train.py              (LoRA fine-tune, MOVE)
04-trained-data/     ← Done. Checkpoints here.
```

**Data MOVES at every step.** After ETL runs, `01-raw-data/` is empty.
After chunking, `02-ETL-data/` is empty. After training, the chunk moves
to `04-trained-data/`. No duplicates. No retraining on stale data.

---

## Quick Start

```bash
# 1. Configure once
vi values.yaml                        # Set your model, paths, chunk size

# 2. Drop training data
cp my-data.jsonl 01-raw-data/

# 3. Run the pipeline
python3 tools/etl_pipeline.py         # Validate + normalize → 02-ETL-data/
python3 tools/chunk_data.py           # Split into chunks → 03-chunked-untrained/
python3 tools/train.py                # Fine-tune → 04-trained-data/

# Preview any step without changes
python3 tools/etl_pipeline.py --dry-run
python3 tools/chunk_data.py --dry-run
python3 tools/train.py --dry-run
```

---

## Configuration

Everything reads from `values.yaml`. Update once, all tools use it.

```yaml
# Key settings (see values.yaml for full reference)
model:
  base_model: "unsloth/Llama-3.2-3B-Instruct"
chunking:
  chunk_size: 5000           # Examples per chunk
  holdout_pct: 5             # Reserved for eval
lora:
  r: 64
  alpha: 128
training:
  epochs_per_chunk: 2
  batch_size: 4
  learning_rate: 2.0e-5
```

---

## The Tools

### Step 1: `tools/etl_pipeline.py`

| What It Does | Details |
|-------------|---------|
| Reads | All `.jsonl` and `.json` from `01-raw-data/` |
| Normalizes | ChatML, Alpaca, Q&A → all become ChatML format |
| Validates | Messages array, content >20 chars, no `[NEEDS CORRECTION]` |
| Deduplicates | MD5 hash of message content |
| Labels | Auto-infers domain (kubernetes, aws, security, etc.) |
| Writes | Combined JSONL to `02-ETL-data/` |
| **Moves** | Source files to `01-raw-data/_processed/` |

```bash
python3 tools/etl_pipeline.py              # Run
python3 tools/etl_pipeline.py --dry-run    # Preview
python3 tools/etl_pipeline.py --keep       # Don't move (debug only)
```

### Step 2: `tools/chunk_data.py`

| What It Does | Details |
|-------------|---------|
| Reads | All `.jsonl` from `02-ETL-data/` |
| Validates | Every example re-checked |
| Shuffles | Default on (seed=42 for reproducibility) |
| Holdout | 5% reserved for eval → `testing-pipeline/eval-holdout/` |
| Chunks | Splits into files of 5k examples (configurable) |
| Manifest | Writes `manifest.json` tracking chunk lineage and status |
| **Moves** | Source files to `02-ETL-data/_processed/` |

```bash
python3 tools/chunk_data.py                    # Default 5k chunks
python3 tools/chunk_data.py --chunk-size 10000 # 10k chunks
python3 tools/chunk_data.py --holdout-pct 10   # 10% holdout
python3 tools/chunk_data.py --no-shuffle       # Preserve order
python3 tools/chunk_data.py --dry-run          # Preview
```

### Step 3: `tools/train.py`

| What It Does | Details |
|-------------|---------|
| Finds | Next untrained chunk from `manifest.json` |
| Loads | Base model with 4-bit quantization (Unsloth) |
| Applies | LoRA adapter (r=64, alpha=128, 7 target modules) |
| Trains | Per-chunk fine-tuning (2 epochs default) |
| Saves | Checkpoint to `04-trained-data/{version}/{chunk}/` |
| Logs | `training_log.json` with timing, config, chunk info |
| **Moves** | Trained chunk from `03-chunked-untrained/` to `04-trained-data/` |

```bash
python3 tools/train.py                # Train next untrained chunk
python3 tools/train.py --chunk 3      # Train specific chunk
python3 tools/train.py --all          # Train all untrained chunks
python3 tools/train.py --dry-run      # Preview
```

---

## Data Format

All training data must be ChatML JSONL:

```json
{"messages": [
  {"role": "system", "content": "You are a security engineer."},
  {"role": "user", "content": "How do I fix a privileged container?"},
  {"role": "assistant", "content": "Add securityContext with runAsNonRoot: true..."}
]}
```

ETL also accepts Alpaca and Q&A formats — they get converted automatically.

---

## After Training

The trained checkpoint in `04-trained-data/` needs to be:
1. **Merged** into the base model (merge LoRA weights)
2. **Converted** to GGUF for Ollama serving
3. **Evaluated** against benchmarks in `testing-pipeline/`
4. **Promoted** to `model-registry/champion/` if it passes

These steps are documented in the respective directories.

---

## What Happens to Each Directory

| Directory | Before pipeline | After ETL | After chunk | After train |
|-----------|----------------|-----------|-------------|-------------|
| `01-raw-data/` | Your JSONL files | **Empty** (moved to `_processed/`) | Empty | Empty |
| `02-ETL-data/` | Empty | Combined JSONL | **Empty** (moved) | Empty |
| `03-chunked-untrained/` | Empty | Empty | Chunk files + manifest | **Empty** (moved) |
| `04-trained-data/` | Empty | Empty | Empty | Checkpoints + logs |

Nothing gets left behind. Ever.
