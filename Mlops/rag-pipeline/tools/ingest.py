#!/usr/bin/env python3
"""
Step 2: Ingest to ChromaDB
===========================
Embed preprocessed documents and store in ChromaDB from 03-preprocessed → 05-vector-store

What it does:
  1. Reads all .jsonl files from 03-preprocessed/
  2. Embeds each document using nomic-embed-text via Ollama (768 dimensions)
  3. Stores embeddings + metadata in ChromaDB (persistent, local)
  4. Uses deterministic IDs for upsert deduplication (re-run safe)
  5. Quarantines failed embeddings (never inserts zero vectors)
  6. MOVES processed files out of 03-preprocessed/ (nothing left behind)

Usage:
    python3 tools/ingest.py                    # Ingest all preprocessed data
    python3 tools/ingest.py --dry-run          # Preview without changes
    python3 tools/ingest.py --keep             # Don't move source files
    python3 tools/ingest.py --collection general  # Ingest only one collection

Requirements:
    pip install chromadb pyyaml
    Ollama running with nomic-embed-text: ollama pull nomic-embed-text
"""

import json
import hashlib
import shutil
import argparse
import time
import yaml
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional


# ── Load config ──────────────────────────────────────────────

def load_config() -> dict:
    config_path = Path(__file__).parent.parent / "values.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}


CONFIG = load_config()
BASE_DIR = Path(__file__).parent.parent
PREPROCESSED_DIR = BASE_DIR / CONFIG.get("paths", {}).get("preprocessed", "03-preprocessed")
VECTOR_STORE_DIR = BASE_DIR / CONFIG.get("paths", {}).get("vector_store", "05-vector-store")
CHROMA_DIR = VECTOR_STORE_DIR / "chroma"
ARCHIVE_DIR = PREPROCESSED_DIR / "_ingested"
QUARANTINE_FILE = VECTOR_STORE_DIR / "embedding_quarantine.jsonl"

EMBED_CFG = CONFIG.get("embedding", {})
EMBED_MODEL = EMBED_CFG.get("model", "nomic-embed-text:latest")
EMBED_DIMS = EMBED_CFG.get("dimensions", 768)
OLLAMA_ENDPOINT = EMBED_CFG.get("endpoint", "http://localhost:11434")

BATCH_SIZE = 50  # Documents per embedding batch


# ── Ollama embedding ─────────────────────────────────────────

def get_embeddings(texts: List[str], retries: int = 2) -> List[Optional[List[float]]]:
    """Get embeddings from Ollama. Returns None for failed items."""
    try:
        import requests
    except ImportError:
        print("[ERROR] requests not installed. Run: pip install requests")
        return [None] * len(texts)

    url = f"{OLLAMA_ENDPOINT}/api/embed"
    results = []

    for text in texts:
        embedding = None
        for attempt in range(retries + 1):
            try:
                resp = requests.post(url, json={"model": EMBED_MODEL, "input": text}, timeout=30)
                if resp.status_code == 200:
                    data = resp.json()
                    emb = data.get("embeddings", [[]])[0]
                    if emb and len(emb) == EMBED_DIMS and any(v != 0 for v in emb):
                        embedding = emb
                        break
                if attempt < retries:
                    time.sleep(1)
            except Exception as e:
                if attempt < retries:
                    time.sleep(1)
                else:
                    pass  # Quarantine this document
        results.append(embedding)

    return results


def doc_id(content: str, source: str, chunk_idx: int) -> str:
    """Deterministic ID for upsert deduplication."""
    raw = f"{content}|{source}|{chunk_idx}"
    return hashlib.md5(raw.encode()).hexdigest()[:16]


# ── ChromaDB ─────────────────────────────────────────────────

def get_chromadb_client():
    """Get or create ChromaDB persistent client."""
    try:
        import chromadb
    except ImportError:
        print("[ERROR] chromadb not installed. Run: pip install chromadb")
        return None

    CHROMA_DIR.mkdir(parents=True, exist_ok=True)
    return chromadb.PersistentClient(path=str(CHROMA_DIR))


def flatten_metadata(metadata: dict) -> dict:
    """Flatten nested dicts/lists for ChromaDB compatibility."""
    flat = {}
    for k, v in metadata.items():
        if isinstance(v, (dict, list)):
            flat[k] = json.dumps(v)
        elif v is None:
            flat[k] = ""
        else:
            flat[k] = v
    return flat


# ── Main pipeline ────────────────────────────────────────────

def run_ingest(dry_run: bool = False, keep: bool = False,
               collection_filter: Optional[str] = None):
    """Run the ingestion pipeline."""

    # Find preprocessed files
    source_files = sorted(PREPROCESSED_DIR.glob("preprocessed_*.jsonl"))

    if not source_files:
        print(f"[INGEST] No preprocessed files found in {PREPROCESSED_DIR}/")
        print(f"         Run preprocess.py first.")
        return

    print(f"[INGEST] Found {len(source_files)} file(s) in {PREPROCESSED_DIR}/")

    # Load all documents
    all_docs: List[Dict] = []
    for filepath in source_files:
        with open(filepath) as f:
            for line in f:
                if line.strip():
                    try:
                        doc = json.loads(line)
                        col = doc.get("metadata", {}).get("collection", "general")
                        if collection_filter and col != collection_filter:
                            continue
                        all_docs.append(doc)
                    except json.JSONDecodeError:
                        pass

    print(f"  Documents to ingest: {len(all_docs)}")

    # Group by collection
    by_collection: Dict[str, List[Dict]] = {}
    for doc in all_docs:
        col = doc.get("metadata", {}).get("collection", "general")
        by_collection.setdefault(col, []).append(doc)

    print(f"  Collections:")
    for col, docs in sorted(by_collection.items()):
        print(f"    {col}: {len(docs)} documents")

    if dry_run:
        print(f"\n[DRY RUN] Would embed {len(all_docs)} documents")
        print(f"[DRY RUN] Would store to {CHROMA_DIR}/")
        print(f"[DRY RUN] Would move {len(source_files)} files to {ARCHIVE_DIR}/")
        return

    # Check Ollama is running
    try:
        import requests
        resp = requests.get(f"{OLLAMA_ENDPOINT}/api/tags", timeout=5)
        if resp.status_code != 200:
            print(f"[ERROR] Ollama not responding at {OLLAMA_ENDPOINT}")
            return
    except Exception:
        print(f"[ERROR] Cannot connect to Ollama at {OLLAMA_ENDPOINT}")
        print(f"        Start Ollama: ollama serve")
        print(f"        Pull model:   ollama pull {EMBED_MODEL}")
        return

    # Initialize ChromaDB
    client = get_chromadb_client()
    if not client:
        return

    total_ingested = 0
    total_quarantined = 0

    for collection_name, docs in by_collection.items():
        print(f"\n[INGEST] Collection: {collection_name} ({len(docs)} documents)")

        collection = client.get_or_create_collection(
            name=collection_name,
            metadata={"hnsw:space": "l2"}
        )

        # Process in batches
        for batch_start in range(0, len(docs), BATCH_SIZE):
            batch = docs[batch_start:batch_start + BATCH_SIZE]

            # Prepare texts and IDs
            texts = [d["content"] for d in batch]
            ids = [doc_id(d["content"], d.get("metadata", {}).get("source", ""), d.get("metadata", {}).get("chunk_index", 0)) for d in batch]
            metadatas = [flatten_metadata(d.get("metadata", {})) for d in batch]

            # Embed
            embeddings = get_embeddings(texts)

            # Separate successful from quarantined
            good_ids, good_embeddings, good_metadatas, good_texts = [], [], [], []
            for i, emb in enumerate(embeddings):
                if emb is not None:
                    good_ids.append(ids[i])
                    good_embeddings.append(emb)
                    good_metadatas.append(metadatas[i])
                    good_texts.append(texts[i])
                else:
                    total_quarantined += 1
                    with open(QUARANTINE_FILE, "a") as qf:
                        qf.write(json.dumps({"id": ids[i], "source": metadatas[i].get("source", ""), "reason": "embedding_failed"}) + "\n")

            # Upsert to ChromaDB
            if good_ids:
                collection.upsert(
                    ids=good_ids,
                    embeddings=good_embeddings,
                    metadatas=good_metadatas,
                    documents=good_texts,
                )
                total_ingested += len(good_ids)

            print(f"  Batch {batch_start//BATCH_SIZE + 1}: {len(good_ids)} ingested, {len(batch) - len(good_ids)} quarantined")

    print(f"\n[INGEST] Complete:")
    print(f"  Ingested:     {total_ingested} documents")
    print(f"  Quarantined:  {total_quarantined} (failed embeddings → {QUARANTINE_FILE})")
    print(f"  ChromaDB:     {CHROMA_DIR}/")

    # MOVE source files
    if not keep:
        ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
        for filepath in source_files:
            dest = ARCHIVE_DIR / filepath.name
            shutil.move(str(filepath), str(dest))
        # Also move manifests
        for manifest in PREPROCESSED_DIR.glob("manifest_*.json"):
            shutil.move(str(manifest), str(ARCHIVE_DIR / manifest.name))
        print(f"[INGEST] Moved source files to {ARCHIVE_DIR}/")
        print(f"[INGEST] 03-preprocessed/ is now empty (as it should be)")
    else:
        print(f"[INGEST] --keep flag: source files left in place")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Step 2: Ingest to ChromaDB")
    parser.add_argument("--dry-run", action="store_true", help="Preview without embedding or moving")
    parser.add_argument("--keep", action="store_true", help="Don't move source files (debug only)")
    parser.add_argument("--collection", type=str, help="Only ingest one collection")
    args = parser.parse_args()

    run_ingest(dry_run=args.dry_run, keep=args.keep, collection_filter=args.collection)
