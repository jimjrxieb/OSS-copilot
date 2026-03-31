#!/usr/bin/env python3
"""
Step 1: Preprocess
==================
Parse, sanitize, chunk, label documents from 01-unprocessed → 03-preprocessed

What it does:
  1. Discovers all files in 01-unprocessed/ (JSONL, JSON, MD, YAML, Rego, TXT)
  2. Parses each format into normalized document objects
  3. Sanitizes: dedup (SHA256), PII redaction, structure validation
  4. Chunks: overlap chunking at ~512 tokens with sentence boundaries
  5. Labels: domain/type tagging via regex pattern matching
  6. Writes quality-reviewed JSONL to 03-preprocessed/
  7. MOVES processed files out of 01-unprocessed/ (nothing left behind)

Usage:
    python3 tools/preprocess.py                    # Process all documents
    python3 tools/preprocess.py --dry-run          # Preview without changes
    python3 tools/preprocess.py --keep             # Don't move source files
    python3 tools/preprocess.py --verbose          # Show per-file details
"""

import json
import re
import hashlib
import shutil
import argparse
import yaml
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional, Set


# ── Load config ──────────────────────────────────────────────

def load_config() -> dict:
    config_path = Path(__file__).parent.parent / "values.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}


CONFIG = load_config()
BASE_DIR = Path(__file__).parent.parent
UNPROCESSED_DIR = BASE_DIR / CONFIG.get("paths", {}).get("unprocessed", "01-unprocessed")
PREPROCESSED_DIR = BASE_DIR / CONFIG.get("paths", {}).get("preprocessed", "03-preprocessed")
ARCHIVE_DIR = UNPROCESSED_DIR / "_processed"

CHUNK_CFG = CONFIG.get("chunking", {})
TARGET_TOKENS = CHUNK_CFG.get("target_tokens", 512)
OVERLAP_TOKENS = CHUNK_CFG.get("overlap_tokens", 64)
TARGET_CHARS = TARGET_TOKENS * 4  # ~4 chars per token
OVERLAP_CHARS = OVERLAP_TOKENS * 4

QUALITY_CFG = CONFIG.get("quality", {})
MIN_CONTENT = QUALITY_CFG.get("min_content_length", 50)
MAX_CONTENT = QUALITY_CFG.get("max_content_length", 50000)

COLLECTIONS = CONFIG.get("collections", {})
ROUTES = COLLECTIONS.get("routes", [])
DEFAULT_COLLECTION = COLLECTIONS.get("default", "general")

SUPPORTED_EXTENSIONS = {".jsonl", ".json", ".md", ".yaml", ".yml", ".rego", ".txt"}


# ── Format parsers ───────────────────────────────────────────

def parse_jsonl(filepath: Path) -> List[Dict]:
    """Parse JSONL — one JSON object per line."""
    docs = []
    with open(filepath) as f:
        for line in f:
            if line.strip():
                try:
                    obj = json.loads(line)
                    content = obj.get("content", obj.get("text", json.dumps(obj)))
                    docs.append({"content": str(content), "source": filepath.name, "format": "jsonl"})
                except json.JSONDecodeError:
                    pass
    return docs


def parse_json(filepath: Path) -> List[Dict]:
    """Parse JSON — array of objects or single object."""
    try:
        data = json.load(open(filepath))
        items = data if isinstance(data, list) else [data]
        return [{"content": json.dumps(item, indent=2), "source": filepath.name, "format": "json"} for item in items]
    except (json.JSONDecodeError, Exception):
        return []


def parse_markdown(filepath: Path) -> List[Dict]:
    """Parse Markdown — split on ## headers."""
    text = filepath.read_text(errors="replace")
    sections = re.split(r'\n(?=##\s)', text)
    return [{"content": s.strip(), "source": filepath.name, "format": "markdown"}
            for s in sections if len(s.strip()) >= MIN_CONTENT]


def parse_yaml_file(filepath: Path) -> List[Dict]:
    """Parse YAML — K8s manifests, configs."""
    try:
        text = filepath.read_text(errors="replace")
        docs = list(yaml.safe_load_all(text))
        return [{"content": yaml.dump(doc, default_flow_style=False), "source": filepath.name, "format": "yaml"}
                for doc in docs if doc]
    except (yaml.YAMLError, Exception):
        return [{"content": filepath.read_text(errors="replace"), "source": filepath.name, "format": "yaml"}]


def parse_rego(filepath: Path) -> List[Dict]:
    """Parse Rego — extract package, rules, comments."""
    text = filepath.read_text(errors="replace")
    return [{"content": text, "source": filepath.name, "format": "rego"}]


def parse_text(filepath: Path) -> List[Dict]:
    """Parse plain text — paragraph splitting."""
    text = filepath.read_text(errors="replace")
    paragraphs = re.split(r'\n\n+', text)
    return [{"content": p.strip(), "source": filepath.name, "format": "text"}
            for p in paragraphs if len(p.strip()) >= MIN_CONTENT]


PARSERS = {
    ".jsonl": parse_jsonl,
    ".json": parse_json,
    ".md": parse_markdown,
    ".yaml": parse_yaml_file,
    ".yml": parse_yaml_file,
    ".rego": parse_rego,
    ".txt": parse_text,
}


# ── Sanitization ─────────────────────────────────────────────

PII_PATTERNS = [
    (re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), '[EMAIL]'),
    (re.compile(r'AKIA[0-9A-Z]{16}'), '[AWS_KEY]'),
    (re.compile(r'(?i)password\s*[=:]\s*\S+'), '[PASSWORD_REDACTED]'),
    (re.compile(r'(?i)api[_-]?key\s*[=:]\s*["\']?\S+'), '[API_KEY_REDACTED]'),
    (re.compile(r'sk-[a-zA-Z0-9]{20,}'), '[SECRET_KEY]'),
]


def sanitize_content(content: str) -> str:
    """Redact PII and clean content."""
    if not QUALITY_CFG.get("redact_pii", True):
        return content
    for pattern, replacement in PII_PATTERNS:
        content = pattern.sub(replacement, content)
    # Remove control characters
    content = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', content)
    return content.strip()


def content_hash(content: str) -> str:
    """SHA256 hash for deduplication."""
    return hashlib.sha256(content.encode()).hexdigest()[:16]


# ── Chunking ─────────────────────────────────────────────────

def chunk_text(content: str) -> List[str]:
    """Split content into overlapping chunks at sentence boundaries."""
    if len(content) <= TARGET_CHARS:
        return [content]

    chunks = []
    start = 0

    while start < len(content):
        end = start + TARGET_CHARS

        # Try to break at a sentence boundary
        if end < len(content):
            for boundary in ['. ', '! ', '? ', '\n\n', '\n']:
                last_boundary = content.rfind(boundary, start + TARGET_CHARS // 2, end)
                if last_boundary > start:
                    end = last_boundary + len(boundary)
                    break

        chunks.append(content[start:end].strip())

        # Overlap
        start = end - OVERLAP_CHARS
        if start >= len(content):
            break

    return [c for c in chunks if len(c) >= MIN_CONTENT]


# ── Labeling ─────────────────────────────────────────────────

def route_to_collection(content: str) -> str:
    """Route document to a collection based on content patterns."""
    text_lower = content.lower()
    for route in ROUTES:
        if re.search(route.get("pattern", ""), text_lower):
            return route["collection"]
    return DEFAULT_COLLECTION


def estimate_tokens(text: str) -> int:
    """Rough token estimate (~4 chars per token)."""
    return len(text) // 4


# ── Main pipeline ────────────────────────────────────────────

def run_preprocess(dry_run: bool = False, keep: bool = False, verbose: bool = False):
    """Run the full preprocessing pipeline."""

    # Discover files
    source_files = []
    for ext in SUPPORTED_EXTENSIONS:
        source_files.extend(UNPROCESSED_DIR.glob(f"**/*{ext}"))
    source_files = [f for f in source_files if "_processed" not in str(f)]
    source_files = sorted(source_files)

    if not source_files:
        print(f"[PREPROCESS] No files found in {UNPROCESSED_DIR}/")
        print(f"             Drop documents there and run again.")
        return

    print(f"[PREPROCESS] Found {len(source_files)} file(s) in {UNPROCESSED_DIR}/")

    # Process all files
    all_documents: List[Dict] = []
    seen_hashes: Set[str] = set()
    stats = {"files": 0, "parsed": 0, "sanitized": 0, "chunked": 0, "deduped": 0, "routed": 0}

    for filepath in source_files:
        stats["files"] += 1
        ext = filepath.suffix.lower()
        parser = PARSERS.get(ext)

        if not parser:
            if verbose:
                print(f"  Skipped: {filepath.name} (unsupported format)")
            continue

        if verbose:
            print(f"  Processing: {filepath.name} ({ext})")

        # Parse
        raw_docs = parser(filepath)
        stats["parsed"] += len(raw_docs)

        for doc in raw_docs:
            content = doc["content"]

            # Length gate
            if len(content) < MIN_CONTENT or len(content) > MAX_CONTENT:
                continue

            # Sanitize
            content = sanitize_content(content)
            stats["sanitized"] += 1

            # Chunk
            chunks = chunk_text(content)
            stats["chunked"] += len(chunks)

            for i, chunk in enumerate(chunks):
                # Dedup
                h = content_hash(chunk)
                if h in seen_hashes:
                    stats["deduped"] += 1
                    continue
                seen_hashes.add(h)

                # Label + route
                collection = route_to_collection(chunk)
                stats["routed"] += 1

                all_documents.append({
                    "id": f"{content_hash(doc['source'])}_{i:04d}",
                    "content": chunk,
                    "metadata": {
                        "source": doc["source"],
                        "format": doc["format"],
                        "collection": collection,
                        "tokens": estimate_tokens(chunk),
                        "chunk_index": i,
                        "preprocessed_at": datetime.now().isoformat(),
                    }
                })

    print(f"\n[PREPROCESS] Results:")
    print(f"  Files:      {stats['files']}")
    print(f"  Parsed:     {stats['parsed']} documents")
    print(f"  Sanitized:  {stats['sanitized']}")
    print(f"  Chunked:    {stats['chunked']} chunks")
    print(f"  Deduped:    {stats['deduped']} (removed)")
    print(f"  Output:     {len(all_documents)} documents")

    # Collection breakdown
    collections = {}
    for doc in all_documents:
        col = doc["metadata"]["collection"]
        collections[col] = collections.get(col, 0) + 1
    print(f"\n  Collections:")
    for col, count in sorted(collections.items()):
        print(f"    {col}: {count}")

    if dry_run:
        print(f"\n[DRY RUN] Would write {len(all_documents)} documents to {PREPROCESSED_DIR}/")
        print(f"[DRY RUN] Would move {len(source_files)} files to {ARCHIVE_DIR}/")
        return

    if not all_documents:
        print("[PREPROCESS] No documents to write.")
        return

    # Write output
    PREPROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = PREPROCESSED_DIR / f"preprocessed_{timestamp}.jsonl"

    with open(output_file, "w") as f:
        for doc in all_documents:
            f.write(json.dumps(doc) + "\n")

    # Write manifest
    manifest = {
        "created": datetime.now().isoformat(),
        "source_files": len(source_files),
        "total_documents": len(all_documents),
        "collections": collections,
        "output_file": output_file.name,
    }
    manifest_file = PREPROCESSED_DIR / f"manifest_{timestamp}.json"
    with open(manifest_file, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"\n[PREPROCESS] Wrote: {output_file.name} ({len(all_documents)} documents)")
    print(f"[PREPROCESS] Wrote: {manifest_file.name}")

    # MOVE source files
    if not keep:
        ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
        for filepath in source_files:
            dest = ARCHIVE_DIR / filepath.name
            shutil.move(str(filepath), str(dest))
        print(f"[PREPROCESS] Moved {len(source_files)} source files to {ARCHIVE_DIR}/")
        print(f"[PREPROCESS] 01-unprocessed/ is now empty (as it should be)")
    else:
        print(f"[PREPROCESS] --keep flag: source files left in place")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Step 1: Preprocess documents for RAG")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing or moving")
    parser.add_argument("--keep", action="store_true", help="Don't move source files (debug only)")
    parser.add_argument("--verbose", action="store_true", help="Show per-file processing details")
    args = parser.parse_args()

    run_preprocess(dry_run=args.dry_run, keep=args.keep, verbose=args.verbose)
