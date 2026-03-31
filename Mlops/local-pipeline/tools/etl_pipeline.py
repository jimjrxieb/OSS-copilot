#!/usr/bin/env python3
"""
Step 1: ETL Pipeline
====================
Extract, Transform, Load data from 01-raw-data → 02-ETL-data

What it does:
  1. Reads ALL .jsonl files from 01-raw-data/
  2. Validates each example (must have messages array with role + content)
  3. Normalizes format (Alpaca, Q&A → ChatML)
  4. Deduplicates via MD5 hash of content
  5. Adds metadata (source file, category, domain, timestamp)
  6. Writes combined output to 02-ETL-data/
  7. MOVES processed files out of 01-raw-data/ (nothing left behind)

Usage:
    python3 tools/etl_pipeline.py                  # Process all, move files after
    python3 tools/etl_pipeline.py --dry-run        # Preview without changes
    python3 tools/etl_pipeline.py --keep           # Don't move source files (debugging only)
"""

import json
import hashlib
import shutil
import argparse
import yaml
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Set, Optional


# ── Load config ──────────────────────────────────────────────

def load_config() -> dict:
    config_path = Path(__file__).parent.parent / "values.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}


CONFIG = load_config()
BASE_DIR = Path(__file__).parent.parent
RAW_DIR = BASE_DIR / CONFIG.get("paths", {}).get("raw_data", "01-raw-data")
ETL_DIR = BASE_DIR / CONFIG.get("paths", {}).get("etl_data", "02-ETL-data")
ARCHIVE_DIR = RAW_DIR / "_processed"
SYSTEM_PROMPT = CONFIG.get("system_prompt", "You are a helpful assistant.")


# ── Format detection & conversion ────────────────────────────

def is_chatml(example: dict) -> bool:
    """Check if example is already ChatML format."""
    messages = example.get("messages", [])
    if not isinstance(messages, list) or len(messages) < 2:
        return False
    return all(
        isinstance(m, dict) and "role" in m and "content" in m
        for m in messages
    )


def alpaca_to_chatml(example: dict) -> Optional[dict]:
    """Convert Alpaca format (instruction/input/output) to ChatML."""
    instruction = example.get("instruction", "")
    input_text = example.get("input", "")
    output = example.get("output", "")
    if not instruction or not output:
        return None
    user_content = f"{instruction}\n{input_text}".strip() if input_text else instruction
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_content},
            {"role": "assistant", "content": output},
        ]
    }


def qa_to_chatml(example: dict) -> Optional[dict]:
    """Convert Q&A format (question/answer) to ChatML."""
    question = example.get("question", example.get("prompt", ""))
    answer = example.get("answer", example.get("response", example.get("completion", "")))
    if not question or not answer:
        return None
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": question},
            {"role": "assistant", "content": answer},
        ]
    }


def normalize_example(example: dict) -> Optional[dict]:
    """Convert any supported format to ChatML."""
    if is_chatml(example):
        return example
    if "instruction" in example:
        return alpaca_to_chatml(example)
    if "question" in example or "prompt" in example:
        return qa_to_chatml(example)
    return None


# ── Validation ───────────────────────────────────────────────

def validate_example(example: dict) -> bool:
    """Validate a ChatML example meets quality standards."""
    messages = example.get("messages", [])
    if len(messages) < 2:
        return False
    for msg in messages:
        if not isinstance(msg.get("content"), str):
            return False
        if len(msg["content"].strip()) < 20:
            return False
    if "[NEEDS CORRECTION]" in json.dumps(example):
        return False
    return True


def content_hash(example: dict) -> str:
    """MD5 hash for deduplication."""
    content = json.dumps(example.get("messages", []), sort_keys=True)
    return hashlib.md5(content.encode()).hexdigest()


# ── Domain inference ─────────────────────────────────────────

DOMAIN_KEYWORDS = {
    "kubernetes": ["kubectl", "pod", "deployment", "namespace", "kube", "k8s", "helm"],
    "security": ["cve", "vulnerability", "exploit", "hardening", "security"],
    "opa": ["rego", "conftest", "gatekeeper", "opa", "policy"],
    "aws": ["aws", "ec2", "s3", "iam", "lambda", "eks", "cloudtrail"],
    "cicd": ["github actions", "pipeline", "ci/cd", "workflow", "deploy"],
    "docker": ["dockerfile", "container", "docker", "image"],
    "terraform": ["terraform", "tfvars", "provider", "resource"],
}


def infer_domain(example: dict) -> str:
    """Infer domain from content keywords."""
    text = json.dumps(example.get("messages", [])).lower()
    scores = {}
    for domain, keywords in DOMAIN_KEYWORDS.items():
        scores[domain] = sum(1 for kw in keywords if kw in text)
    best = max(scores, key=scores.get)
    return best if scores[best] > 0 else "general"


# ── Main pipeline ────────────────────────────────────────────

def run_etl(dry_run: bool = False, keep: bool = False):
    """Run the full ETL pipeline."""

    # Find all source files
    source_files = sorted(RAW_DIR.glob("**/*.jsonl"))
    source_files += sorted(RAW_DIR.glob("**/*.json"))
    # Exclude _processed archive
    source_files = [f for f in source_files if "_processed" not in str(f)]

    if not source_files:
        print(f"[ETL] No files found in {RAW_DIR}/")
        print(f"      Drop your .jsonl files there and run again.")
        return

    print(f"[ETL] Found {len(source_files)} source file(s) in {RAW_DIR}/")

    # Process all files
    all_examples: List[dict] = []
    seen_hashes: Set[str] = set()
    stats = {"total_read": 0, "normalized": 0, "valid": 0, "deduped": 0, "skipped": 0}

    for filepath in source_files:
        print(f"  Processing: {filepath.name}")
        try:
            with open(filepath) as f:
                if filepath.suffix == ".json":
                    data = json.load(f)
                    lines = data if isinstance(data, list) else [data]
                else:
                    lines = [json.loads(line) for line in f if line.strip()]
        except (json.JSONDecodeError, Exception) as e:
            print(f"    ERROR: {e}")
            continue

        for raw in lines:
            stats["total_read"] += 1

            # Normalize to ChatML
            example = normalize_example(raw)
            if not example:
                stats["skipped"] += 1
                continue
            stats["normalized"] += 1

            # Validate
            if not validate_example(example):
                stats["skipped"] += 1
                continue
            stats["valid"] += 1

            # Deduplicate
            h = content_hash(example)
            if h in seen_hashes:
                stats["deduped"] += 1
                continue
            seen_hashes.add(h)

            # Add metadata
            example["metadata"] = {
                "source": filepath.name,
                "domain": infer_domain(example),
                "etl_timestamp": datetime.now().isoformat(),
            }

            all_examples.append(example)

    print(f"\n[ETL] Results:")
    print(f"  Read:       {stats['total_read']}")
    print(f"  Normalized: {stats['normalized']}")
    print(f"  Valid:      {stats['valid']}")
    print(f"  Deduped:    {stats['deduped']} (removed)")
    print(f"  Skipped:    {stats['skipped']}")
    print(f"  Output:     {len(all_examples)} examples")

    if dry_run:
        print(f"\n[DRY RUN] Would write {len(all_examples)} examples to {ETL_DIR}/")
        print(f"[DRY RUN] Would move {len(source_files)} files to {ARCHIVE_DIR}/")
        return

    if not all_examples:
        print("[ETL] No valid examples to write.")
        return

    # Write output
    ETL_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = ETL_DIR / f"etl_combined_{timestamp}.jsonl"

    with open(output_file, "w") as f:
        for example in all_examples:
            f.write(json.dumps(example) + "\n")

    print(f"\n[ETL] Wrote: {output_file} ({len(all_examples)} examples)")

    # MOVE source files (nothing left behind)
    if not keep:
        ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
        for filepath in source_files:
            dest = ARCHIVE_DIR / filepath.name
            shutil.move(str(filepath), str(dest))
        print(f"[ETL] Moved {len(source_files)} source files to {ARCHIVE_DIR}/")
        print(f"[ETL] 01-raw-data/ is now empty (as it should be)")
    else:
        print(f"[ETL] --keep flag: source files left in place")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Step 1: ETL Pipeline")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing or moving")
    parser.add_argument("--keep", action="store_true", help="Don't move source files (debug only)")
    args = parser.parse_args()

    run_etl(dry_run=args.dry_run, keep=args.keep)
