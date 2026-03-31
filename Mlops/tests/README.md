# Tests — Quality Gates

> Run before and after every pipeline step.
> Data quality is non-negotiable.

---

## Test Suite

| Test | When to Run | What It Checks |
|------|------------|---------------|
| `test_data_quality.py` | Before training (MANDATORY) | Valid JSONL, ChatML format, no duplicates, content length |
| `test_model_behavior.py` | After training | Smoke tests — does it answer domain questions correctly? |
| `test_serving.py` | After deploy to Ollama | Health check — is the model responding? |
| `test_schemas.py` | After ETL | Data matches JSON schema contracts |

---

## Running Tests

```bash
cd Mlops/tests

# Data quality (run before every training session)
python3 -m pytest test_data_quality.py -v

# Model behavior (run after merge)
python3 -m pytest test_model_behavior.py -v

# Serving health (run after Ollama register)
python3 -m pytest test_serving.py -v

# All tests
python3 -m pytest . -v
```

---

## Data Quality Checklist (MANDATORY)

Before any training data enters `03-chunked-untrained/`:

- [ ] Every line is valid JSON
- [ ] Every example has `messages` array
- [ ] Every message has `role` and `content`
- [ ] `role` is one of: system, user, assistant
- [ ] `content` length > 20 characters
- [ ] No `[NEEDS CORRECTION]` markers
- [ ] No duplicate entries (MD5 of content)
- [ ] Domain labels present
