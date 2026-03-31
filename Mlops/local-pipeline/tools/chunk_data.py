#!/usr/bin/env python3
"""
Step 2: Chunk Data
==================
Split ETL output from 02-ETL-data → 03-chunked-untrained

What it does:
  1. Reads ALL .jsonl files from 02-ETL-data/
  2. Validates every example (messages array, content length, no garbage)
  3. Optionally shuffles (default: on)
  4. Reserves holdout eval set (default 5%) → testing-pipeline/eval-holdout/
  5. Splits remaining into chunk files (default 5k examples each)
  6. Writes manifest.json tracking chunk lineage
  7. MOVES processed files out of 02-ETL-data/ (nothing left behind)

Usage:
    python3 tools/chunk_data.py                    # Chunk all, default 5k
    python3 tools/chunk_data.py --chunk-size 10000 # 10k chunks
    python3 tools/chunk_data.py --dry-run          # Preview without changes
    python3 tools/chunk_data.py --keep             # Don't move source files
    python3 tools/chunk_data.py --no-shuffle       # Don't shuffle
    python3 tools/chunk_data.py --holdout-pct 10   # 10% holdout
"""

import json
import hashlib
import random
import shutil
import argparse
import yaml
from pathlib import Path
from datetime import datetime
from typing import List, Dict


# ── Load config ──────────────────────────────────────────────

def load_config() -> dict:
    config_path = Path(__file__).parent.parent / "values.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}


CONFIG = load_config()
BASE_DIR = Path(__file__).parent.parent
ETL_DIR = BASE_DIR / CONFIG.get("paths", {}).get("etl_data", "02-ETL-data")
CHUNK_DIR = BASE_DIR / CONFIG.get("paths", {}).get("chunked_data", "03-chunked-untrained")
HOLDOUT_DIR = BASE_DIR / CONFIG.get("paths", {}).get("eval_holdout", "../testing-pipeline/eval-holdout")
ARCHIVE_DIR = ETL_DIR / "_processed"

CHUNK_CFG = CONFIG.get("chunking", {})
DEFAULT_CHUNK_SIZE = CHUNK_CFG.get("chunk_size", 5000)
DEFAULT_HOLDOUT_PCT = CHUNK_CFG.get("holdout_pct", 5)
HOLDOUT_SEED = CHUNK_CFG.get("holdout_seed", 42)
DEFAULT_SHUFFLE = CHUNK_CFG.get("shuffle", True)


# ── Validation ───────────────────────────────────────────────

def validate_example(example: dict) -> bool:
    """Validate example has required ChatML structure."""
    messages = example.get("messages", [])
    if not isinstance(messages, list) or len(messages) < 2:
        return False
    for msg in messages:
        if not isinstance(msg.get("content"), str):
            return False
        if len(msg["content"].strip()) < 20:
            return False
    if "[NEEDS CORRECTION]" in json.dumps(example):
        return False
    return True


# ── Chunking ─────────────────────────────────────────────────

def auto_detect_next_chunk(chunk_dir: Path) -> int:
    """Find the next chunk number by scanning existing files."""
    existing = sorted(chunk_dir.glob("chunk_*.jsonl"))
    if not existing:
        return 1
    last = existing[-1].stem  # chunk_0005_5k
    try:
        num = int(last.split("_")[1])
        return num + 1
    except (IndexError, ValueError):
        return len(existing) + 1


def run_chunk(chunk_size: int, dry_run: bool = False, keep: bool = False,
              shuffle: bool = True, holdout_pct: int = DEFAULT_HOLDOUT_PCT):
    """Run the chunking pipeline."""

    # Find all ETL output files
    source_files = sorted(ETL_DIR.glob("*.jsonl"))
    source_files = [f for f in source_files if "_processed" not in str(f)]

    if not source_files:
        print(f"[CHUNK] No .jsonl files found in {ETL_DIR}/")
        print(f"        Run etl_pipeline.py first.")
        return

    print(f"[CHUNK] Found {len(source_files)} file(s) in {ETL_DIR}/")

    # Load all examples
    all_examples: List[dict] = []
    skipped = 0

    for filepath in source_files:
        with open(filepath) as f:
            for line in f:
                if line.strip():
                    try:
                        example = json.loads(line)
                        if validate_example(example):
                            all_examples.append(example)
                        else:
                            skipped += 1
                    except json.JSONDecodeError:
                        skipped += 1

    print(f"  Loaded: {len(all_examples)} valid examples ({skipped} skipped)")

    if not all_examples:
        print("[CHUNK] No valid examples to chunk.")
        return

    # Shuffle
    if shuffle:
        random.seed(HOLDOUT_SEED)
        random.shuffle(all_examples)
        print(f"  Shuffled: yes (seed={HOLDOUT_SEED})")

    # Reserve holdout for eval
    holdout_count = int(len(all_examples) * holdout_pct / 100)
    holdout_set = all_examples[:holdout_count]
    training_set = all_examples[holdout_count:]

    print(f"  Holdout: {len(holdout_set)} examples ({holdout_pct}%) → testing-pipeline/eval-holdout/")
    print(f"  Training: {len(training_set)} examples → chunks of {chunk_size}")

    # Calculate chunks
    num_chunks = (len(training_set) + chunk_size - 1) // chunk_size
    start_chunk = auto_detect_next_chunk(CHUNK_DIR)

    print(f"  Chunks: {num_chunks} (starting at chunk_{start_chunk:04d})")

    if dry_run:
        print(f"\n[DRY RUN] Would write {num_chunks} chunks + holdout")
        print(f"[DRY RUN] Would move {len(source_files)} files to {ARCHIVE_DIR}/")
        return

    # Write holdout
    holdout_path = Path(HOLDOUT_DIR)
    holdout_path.mkdir(parents=True, exist_ok=True)
    holdout_file = holdout_path / "eval_holdout.jsonl"
    with open(holdout_file, "w") as f:
        for example in holdout_set:
            f.write(json.dumps(example) + "\n")
    print(f"\n  Wrote holdout: {holdout_file}")

    # Write chunks
    CHUNK_DIR.mkdir(parents=True, exist_ok=True)
    manifest_entries = []

    for i in range(num_chunks):
        chunk_num = start_chunk + i
        chunk_slice = training_set[i * chunk_size : (i + 1) * chunk_size]
        chunk_file = CHUNK_DIR / f"chunk_{chunk_num:04d}_{len(chunk_slice)//1000}k.jsonl"

        with open(chunk_file, "w") as f:
            for example in chunk_slice:
                f.write(json.dumps(example) + "\n")

        manifest_entries.append({
            "chunk": chunk_num,
            "file": chunk_file.name,
            "examples": len(chunk_slice),
            "status": "untrained",
        })
        print(f"  Wrote: {chunk_file.name} ({len(chunk_slice)} examples)")

    # Write manifest
    manifest = {
        "created": datetime.now().isoformat(),
        "total_examples": len(training_set),
        "chunk_size": chunk_size,
        "holdout_examples": len(holdout_set),
        "holdout_pct": holdout_pct,
        "chunks": manifest_entries,
    }
    manifest_file = CHUNK_DIR / "manifest.json"
    with open(manifest_file, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"  Wrote: {manifest_file.name}")

    # MOVE source files (nothing left behind)
    if not keep:
        ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
        for filepath in source_files:
            dest = ARCHIVE_DIR / filepath.name
            shutil.move(str(filepath), str(dest))
        print(f"\n[CHUNK] Moved {len(source_files)} source files to {ARCHIVE_DIR}/")
        print(f"[CHUNK] 02-ETL-data/ is now empty (as it should be)")
    else:
        print(f"\n[CHUNK] --keep flag: source files left in place")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Step 2: Chunk Data")
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE,
                        help=f"Examples per chunk (default: {DEFAULT_CHUNK_SIZE})")
    parser.add_argument("--holdout-pct", type=int, default=DEFAULT_HOLDOUT_PCT,
                        help=f"Percent reserved for eval (default: {DEFAULT_HOLDOUT_PCT})")
    parser.add_argument("--no-shuffle", action="store_true", help="Don't shuffle before chunking")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing or moving")
    parser.add_argument("--keep", action="store_true", help="Don't move source files (debug only)")
    args = parser.parse_args()

    run_chunk(
        chunk_size=args.chunk_size,
        dry_run=args.dry_run,
        keep=args.keep,
        shuffle=not args.no_shuffle,
        holdout_pct=args.holdout_pct,
    )
