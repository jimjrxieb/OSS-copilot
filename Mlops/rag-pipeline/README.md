# RAG Pipeline

> 7-stage document ingestion. Raw documents in, ChromaDB vector store out.
> Query your own knowledge base with any LLM via similarity search.

---

## Data Flow

```
01-unprocessed/           ← DROP YOUR DOCUMENTS HERE (MD, JSONL, YAML, TXT, Rego)
    ↓ Stage 1: discover       (scan directories, categorize by file type)
    ↓ Stage 2: parse           (format-specific parsing)
    ↓ Stage 3: sanitize        (quality gates: dedup, PII redaction, structure check)
    ↓ Stage 4: chunk           (normalize to JSONL, overlap chunking 512 tokens)
    ↓ Stage 5: label           (domain/type/difficulty tagging)
    ↓ Stage 6: validate        (token count, format validation)
    ↓ Stage 7: route           (assign to collections by domain)
02-prep-factory/          ← Processing stages live here
    ↓
03-preprocessed/          ← Quality-reviewed JSONL ready for embedding
    ↓ ingest_to_chromadb.py    (embed with nomic-embed-text, store to ChromaDB)
04-ingesting/             ← Ingestion scripts and configs
    ↓
05-vector-store/          ← ChromaDB persistent store (query from here)
    └── chroma/               SQLite-backed vector database
```

---

## Scripts (to be implemented)

| Stage | Script | What It Does | Status |
|-------|--------|-------------|--------|
| 1 | `discover.py` | Scan input dirs, categorize files | Placeholder |
| 2 | `parse.py` | Format-specific parsing (MD, JSONL, YAML, Rego) | Placeholder |
| 3 | `sanitize.py` | Dedup, PII redaction, structure validation | Placeholder |
| 4 | `chunk.py` | Normalize to JSONL, overlap chunking (512 tokens) | Placeholder |
| 5 | `label.py` | Domain/type tagging (regex → pattern → optional LLM) | Placeholder |
| 6 | `validate.py` | Token count, format checks | Placeholder |
| 7 | `route.py` | Assign to ChromaDB collections | Placeholder |
| 8 | `ingest.py` | Embed and store to ChromaDB | Placeholder |

---

## Embedding Config (reference)

```yaml
# rag-config.yaml
embedding:
  model: "nomic-embed-text:latest"     # via Ollama
  dimensions: 768
  provider: "ollama"
  endpoint: "http://localhost:11434"

vector_store:
  type: "chromadb"
  persist_directory: "05-vector-store/chroma/"
  distance_metric: "l2"               # squared L2

chunking:
  target_tokens: 512                   # ~2048 characters
  overlap_tokens: 64                   # 12.5% overlap
  boundary: "sentence"                 # split on . ! ?

collections:
  - name: "general"                    # default knowledge
  - name: "domain-sme"                # domain-specific expert docs
  - name: "operational"               # runbooks, incident logs
  - name: "policies"                  # OPA, Kyverno, compliance
```

---

## Supported Input Formats

| Format | Extension | How It's Parsed |
|--------|-----------|----------------|
| JSONL | `.jsonl` | Line-by-line JSON objects |
| JSON | `.json` | Array of objects or nested structure |
| Markdown | `.md` | Header-aware splitting (## boundaries) |
| YAML | `.yaml`, `.yml` | K8s manifests, configs — structure-aware |
| Rego | `.rego` | Package/rule/comment extraction |
| Text | `.txt` | Paragraph splitting |

---

## Directory Details

### 01-unprocessed/
Drop raw documents here. Organize by category:
```
01-unprocessed/
├── security-docs/         ← Security documentation, guides
├── runbooks/              ← Operational runbooks, playbooks
├── policies/              ← OPA Rego, Kyverno YAML, compliance
├── incidents/             ← Incident reports, post-mortems
├── sessions/              ← Chat transcripts, meeting notes
└── reference/             ← Reference architecture, standards
```

### 02-prep-factory/
The 7-stage processing pipeline. Each stage is a separate script
that reads from the previous stage's output.

### 03-preprocessed/
Quality-reviewed JSONL files. Every document has been deduplicated,
sanitized, chunked, labeled, and validated before reaching this stage.

### 04-ingesting/
Embedding and ChromaDB ingestion scripts. Handles:
- Deterministic document IDs (upsert deduplication)
- Embedding retry with quarantine for failures
- Flat metadata for ChromaDB compatibility

### 05-vector-store/
ChromaDB persistent store. Query it from any application:

```python
import chromadb

client = chromadb.PersistentClient(path="05-vector-store/chroma/")
collection = client.get_collection("general")

results = collection.query(
    query_texts=["How do I fix a privileged container?"],
    n_results=5
)
```
