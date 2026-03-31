#!/usr/bin/env python3
"""
Step 3: Train
=============
LoRA fine-tune on chunks from 03-chunked-untrained → 04-trained-data

What it does:
  1. Finds the next untrained chunk in 03-chunked-untrained/
  2. Loads the base model (or continues from last checkpoint)
  3. LoRA fine-tunes on the chunk data
  4. Saves checkpoint to 04-trained-data/
  5. MOVES the trained chunk out of 03-chunked-untrained/ (nothing left behind)
  6. Updates manifest.json with trained status

Usage:
    python3 tools/train.py                     # Train next untrained chunk
    python3 tools/train.py --chunk 3           # Train specific chunk
    python3 tools/train.py --dry-run           # Preview without training
    python3 tools/train.py --all               # Train all untrained chunks sequentially

Requirements:
    pip install unsloth torch datasets transformers trl pyyaml
    GPU with 24GB VRAM recommended (CPU works but slow)
"""

import json
import shutil
import argparse
import gc
import yaml
from pathlib import Path
from datetime import datetime
from typing import Optional

# ── Load config ──────────────────────────────────────────────

def load_config() -> dict:
    config_path = Path(__file__).parent.parent / "values.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}


CONFIG = load_config()
BASE_DIR = Path(__file__).parent.parent
CHUNK_DIR = BASE_DIR / CONFIG.get("paths", {}).get("chunked_data", "03-chunked-untrained")
TRAINED_DIR = BASE_DIR / CONFIG.get("paths", {}).get("trained_data", "04-trained-data")
REGISTRY_DIR = BASE_DIR / CONFIG.get("paths", {}).get("model_registry", "../model-registry")

MODEL_CFG = CONFIG.get("model", {})
LORA_CFG = CONFIG.get("lora", {})
TRAIN_CFG = CONFIG.get("training", {})
PROJECT_CFG = CONFIG.get("project", {})


# ── Chunk management ─────────────────────────────────────────

def find_next_untrained_chunk() -> Optional[Path]:
    """Find the next chunk that hasn't been trained."""
    manifest_file = CHUNK_DIR / "manifest.json"
    if manifest_file.exists():
        manifest = json.load(open(manifest_file))
        for entry in manifest.get("chunks", []):
            if entry["status"] == "untrained":
                chunk_path = CHUNK_DIR / entry["file"]
                if chunk_path.exists():
                    return chunk_path
    # Fallback: find any .jsonl not yet in trained
    for chunk_file in sorted(CHUNK_DIR.glob("chunk_*.jsonl")):
        return chunk_file
    return None


def mark_chunk_trained(chunk_file: Path):
    """Update manifest and move trained chunk."""
    manifest_file = CHUNK_DIR / "manifest.json"
    if manifest_file.exists():
        manifest = json.load(open(manifest_file))
        for entry in manifest["chunks"]:
            if entry["file"] == chunk_file.name:
                entry["status"] = "trained"
                entry["trained_at"] = datetime.now().isoformat()
        with open(manifest_file, "w") as f:
            json.dump(manifest, f, indent=2)

    # MOVE chunk to trained directory
    TRAINED_DIR.mkdir(parents=True, exist_ok=True)
    dest = TRAINED_DIR / chunk_file.name
    shutil.move(str(chunk_file), str(dest))
    print(f"[TRAIN] Moved {chunk_file.name} → {TRAINED_DIR}/")


# ── Training ─────────────────────────────────────────────────

def train_chunk(chunk_path: Path, dry_run: bool = False):
    """Fine-tune on a single chunk."""

    print(f"\n{'='*60}")
    print(f"[TRAIN] Step 3: Fine-Tune")
    print(f"{'='*60}")
    print(f"  Chunk:      {chunk_path.name}")
    print(f"  Base model: {MODEL_CFG.get('base_model', 'unsloth/Llama-3.2-3B-Instruct')}")
    print(f"  LoRA:       r={LORA_CFG.get('r', 64)} alpha={LORA_CFG.get('alpha', 128)}")
    print(f"  Epochs:     {TRAIN_CFG.get('epochs_per_chunk', 2)}")
    print(f"  Batch:      {TRAIN_CFG.get('batch_size', 4)} x {TRAIN_CFG.get('gradient_accumulation_steps', 8)} = {TRAIN_CFG.get('batch_size', 4) * TRAIN_CFG.get('gradient_accumulation_steps', 8)} effective")
    print(f"  LR:         {TRAIN_CFG.get('learning_rate', 2e-5)}")
    print(f"  Version:    {PROJECT_CFG.get('version', 'v1.0')}")

    # Count examples
    with open(chunk_path) as f:
        example_count = sum(1 for line in f if line.strip())
    print(f"  Examples:   {example_count}")

    if dry_run:
        print(f"\n[DRY RUN] Would train on {example_count} examples")
        print(f"[DRY RUN] Would save checkpoint to {TRAINED_DIR}/")
        print(f"[DRY RUN] Would move chunk to {TRAINED_DIR}/")
        return

    # Check for training dependencies
    try:
        import torch
        from datasets import Dataset
        from unsloth import FastLanguageModel
        from trl import SFTTrainer
        from transformers import TrainingArguments
    except ImportError as e:
        print(f"\n[ERROR] Missing training dependency: {e}")
        print(f"        Install: pip install unsloth torch datasets transformers trl")
        return

    # Load model
    base_model = MODEL_CFG.get("base_model", "unsloth/Llama-3.2-3B-Instruct")
    max_seq = MODEL_CFG.get("max_seq_length", 2048)
    load_4bit = MODEL_CFG.get("load_in_4bit", True)

    print(f"\n[TRAIN] Loading model: {base_model}")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=base_model,
        max_seq_length=max_seq,
        load_in_4bit=load_4bit,
    )

    # Apply LoRA
    model = FastLanguageModel.get_peft_model(
        model,
        r=LORA_CFG.get("r", 64),
        lora_alpha=LORA_CFG.get("alpha", 128),
        lora_dropout=LORA_CFG.get("dropout", 0),
        target_modules=LORA_CFG.get("target_modules", [
            "q_proj", "k_proj", "v_proj", "o_proj",
            "gate_proj", "up_proj", "down_proj"
        ]),
    )

    # Load training data
    print(f"[TRAIN] Loading data: {chunk_path.name}")
    examples = []
    with open(chunk_path) as f:
        for line in f:
            if line.strip():
                try:
                    examples.append(json.loads(line))
                except json.JSONDecodeError:
                    pass

    # Format for training
    def format_example(example):
        messages = example.get("messages", [])
        text = tokenizer.apply_chat_template(messages, tokenize=False)
        return {"text": text}

    dataset = Dataset.from_list([format_example(ex) for ex in examples])
    print(f"[TRAIN] Dataset: {len(dataset)} examples")

    # Training arguments
    version = PROJECT_CFG.get("version", "v1.0")
    output_dir = TRAINED_DIR / version / chunk_path.stem

    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=TRAIN_CFG.get("epochs_per_chunk", 2),
        per_device_train_batch_size=TRAIN_CFG.get("batch_size", 4),
        gradient_accumulation_steps=TRAIN_CFG.get("gradient_accumulation_steps", 8),
        learning_rate=TRAIN_CFG.get("learning_rate", 2e-5),
        warmup_ratio=TRAIN_CFG.get("warmup_ratio", 0.03),
        lr_scheduler_type=TRAIN_CFG.get("lr_scheduler", "cosine"),
        weight_decay=TRAIN_CFG.get("weight_decay", 0.01),
        logging_steps=TRAIN_CFG.get("logging_steps", 10),
        save_steps=TRAIN_CFG.get("save_steps", 500),
        bf16=True,
        optim="adamw_8bit",
        seed=42,
    )

    # Train
    trainer = SFTTrainer(
        model=model,
        train_dataset=dataset,
        args=training_args,
        dataset_text_field="text",
        max_seq_length=max_seq,
    )

    print(f"\n[TRAIN] Starting training...")
    start_time = datetime.now()
    trainer.train()
    elapsed = datetime.now() - start_time

    # Save
    print(f"\n[TRAIN] Saving checkpoint to {output_dir}/")
    model.save_pretrained(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))

    # Record training log
    log = {
        "chunk": chunk_path.name,
        "examples": len(dataset),
        "version": version,
        "base_model": base_model,
        "lora_r": LORA_CFG.get("r", 64),
        "lora_alpha": LORA_CFG.get("alpha", 128),
        "epochs": TRAIN_CFG.get("epochs_per_chunk", 2),
        "elapsed_seconds": elapsed.total_seconds(),
        "completed_at": datetime.now().isoformat(),
    }
    log_file = output_dir / "training_log.json"
    with open(log_file, "w") as f:
        json.dump(log, f, indent=2)

    print(f"[TRAIN] Done in {elapsed}")
    print(f"[TRAIN] Checkpoint: {output_dir}/")

    # Cleanup VRAM
    del model, trainer
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()

    # Mark chunk as trained and MOVE it
    mark_chunk_trained(chunk_path)
    print(f"[TRAIN] 03-chunked-untrained/ chunk moved to 04-trained-data/")


# ── CLI ──────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Step 3: Train")
    parser.add_argument("--chunk", type=int, help="Train specific chunk number")
    parser.add_argument("--all", action="store_true", help="Train all untrained chunks")
    parser.add_argument("--dry-run", action="store_true", help="Preview without training")
    args = parser.parse_args()

    if args.chunk:
        # Find specific chunk
        matches = list(CHUNK_DIR.glob(f"chunk_{args.chunk:04d}_*.jsonl"))
        if matches:
            train_chunk(matches[0], dry_run=args.dry_run)
        else:
            print(f"[ERROR] Chunk {args.chunk} not found in {CHUNK_DIR}/")
    elif args.all:
        # Train all untrained chunks
        while True:
            chunk = find_next_untrained_chunk()
            if not chunk:
                print("[TRAIN] All chunks trained.")
                break
            train_chunk(chunk, dry_run=args.dry_run)
    else:
        # Train next untrained chunk
        chunk = find_next_untrained_chunk()
        if chunk:
            train_chunk(chunk, dry_run=args.dry_run)
        else:
            print("[TRAIN] No untrained chunks found in 03-chunked-untrained/")
            print("        Run chunk_data.py first.")
