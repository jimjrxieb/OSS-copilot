# RAG Pipeline

> 2 tools. 3 stages. Documents in, vector store out.
> Data moves forward, never sits behind.

---

## How It Works

```
01-unprocessed/      ← DROP YOUR DOCUMENTS HERE (MD, JSONL, YAML, Rego, TXT)
    ↓ tools/preprocess.py     (parse, sanitize, chunk, label, route, MOVE)
03-preprocessed/     ← Quality-reviewed JSONL, ready for embedding
    ↓ tools/ingest.py          (embed with Ollama, store to ChromaDB, MOVE)
05-vector-store/     ← Done. ChromaDB lives here. Query it.
    └── chroma/          SQLite-backed vector database
```

**Data MOVES at every step.** After preprocessing, `01-unprocessed/` is empty.
After ingestion, `03-preprocessed/` is empty. No stale documents. No double ingestion.

---

## Quick Start

```bash
# 1. Configure once
vi values.yaml                        # Set embedding model, collections, paths

# 2. Make sure Ollama is running with the embedding model
ollama pull nomic-embed-text

# 3. Drop documents
cp my-docs/*.md 01-unprocessed/
cp my-policies/*.rego 01-unprocessed/

# 4. Run the pipeline
python3 tools/preprocess.py           # Parse + sanitize + chunk → 03-preprocessed/
python3 tools/ingest.py               # Embed + store → 05-vector-store/

# 5. Query your knowledge base
python3 -c "
import chromadb
client = chromadb.PersistentClient(path='05-vector-store/chroma/')
col = client.get_collection('general')
results = col.query(query_texts=['How do I fix a privileged container?'], n_results=3)
for doc in results['documents'][0]:
    print(doc[:200])
    print('---')
"
```

---

## Configuration

Everything reads from `values.yaml`. Update once, both tools use it.

```yaml
# Key settings (see values.yaml for full reference)
embedding:
  model: "nomic-embed-text:latest"     # Via Ollama (768 dimensions)
  endpoint: "http://localhost:11434"

chunking:
  target_tokens: 512                   # ~2048 chars per chunk
  overlap_tokens: 64                   # 12.5% overlap

collections:
  default: "general"
  routes:
    - pattern: "kubernetes|k8s|kubectl"
      collection: "kubernetes"
    - pattern: "aws|iam|s3|ec2"
      collection: "cloud"
    - pattern: "rego|opa|conftest|policy"
      collection: "policies"
```

---

## The Tools

### Step 1: `tools/preprocess.py`

| What It Does | Details |
|-------------|---------|
| Discovers | All files in `01-unprocessed/` (JSONL, JSON, MD, YAML, Rego, TXT) |
| Parses | Format-specific: Markdown splits on headers, YAML extracts manifests, Rego extracts rules |
| Sanitizes | SHA256 dedup, PII redaction (emails, API keys, passwords), length gates |
| Chunks | Overlap chunking at ~512 tokens, splits on sentence boundaries |
| Labels | Routes to collections via regex patterns from `values.yaml` |
| Writes | JSONL + manifest to `03-preprocessed/` |
| **Moves** | Source files to `01-unprocessed/_processed/` |

```bash
python3 tools/preprocess.py              # Run
python3 tools/preprocess.py --dry-run    # Preview
python3 tools/preprocess.py --verbose    # Per-file details
python3 tools/preprocess.py --keep       # Don't move (debug only)
```

### Step 2: `tools/ingest.py`

| What It Does | Details |
|-------------|---------|
| Reads | All `preprocessed_*.jsonl` from `03-preprocessed/` |
| Groups | Documents by collection (from preprocessing labels) |
| Embeds | Via Ollama (`nomic-embed-text`, 768 dimensions) |
| Stores | ChromaDB with deterministic IDs (re-run safe, upsert dedup) |
| Quarantines | Failed embeddings → `embedding_quarantine.jsonl` (never inserts zero vectors) |
| **Moves** | Processed files to `03-preprocessed/_ingested/` |

```bash
python3 tools/ingest.py                  # Ingest all
python3 tools/ingest.py --dry-run        # Preview
python3 tools/ingest.py --collection kubernetes  # One collection only
python3 tools/ingest.py --keep           # Don't move (debug only)
```

---

## Supported Input Formats

| Format | Extension | How It's Parsed |
|--------|-----------|----------------|
| JSONL | `.jsonl` | Line-by-line JSON objects |
| JSON | `.json` | Array of objects or single object |
| Markdown | `.md` | Header-aware splitting (`##` boundaries) |
| YAML | `.yaml`, `.yml` | K8s manifests, configs — multi-doc support |
| Rego | `.rego` | Full file as single document |
| Text | `.txt` | Paragraph splitting |

---

## Querying the Vector Store

After ingestion, query ChromaDB from any Python application:

```python
import chromadb

client = chromadb.PersistentClient(path="05-vector-store/chroma/")

# List collections
for col in client.list_collections():
    print(f"{col.name}: {col.count()} documents")

# Query
collection = client.get_collection("kubernetes")
results = collection.query(
    query_texts=["How do I add a NetworkPolicy?"],
    n_results=5,
)

for doc, meta, dist in zip(results["documents"][0], results["metadatas"][0], results["distances"][0]):
    print(f"[{meta['source']}] (distance: {dist:.4f})")
    print(f"  {doc[:150]}...")
    print()
```

---

## What Happens to Each Directory

| Directory | Before pipeline | After preprocess | After ingest |
|-----------|----------------|-----------------|-------------|
| `01-unprocessed/` | Your documents | **Empty** (moved to `_processed/`) | Empty |
| `03-preprocessed/` | Empty | JSONL + manifest | **Empty** (moved to `_ingested/`) |
| `05-vector-store/` | Empty (or existing DB) | No change | ChromaDB updated |

Nothing gets left behind. Ever.
