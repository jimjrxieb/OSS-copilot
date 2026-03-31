# Data Schemas — Data Contracts

> JSON schemas defining every structured format in the pipeline.
> If data doesn't match the schema, it doesn't enter the pipeline.

---

## Schemas

| Schema | What It Defines | Used By |
|--------|----------------|---------|
| `training_example.json` | ChatML training format (messages array) | local-pipeline ETL + chunk |
| `eval_question.json` | Benchmark question format | eval framework |
| `eval_result.json` | Benchmark result format | eval framework |
| `finding.json` | Scanner finding (Trivy, Kubescape, etc.) | MSSP scanners |
| `generation_manifest.json` | Data generation run tracking | data-lake generators |

---

## Training Example Schema

```json
{
  "type": "object",
  "required": ["messages"],
  "properties": {
    "messages": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["role", "content"],
        "properties": {
          "role": {"enum": ["system", "user", "assistant"]},
          "content": {"type": "string", "minLength": 1}
        }
      },
      "minItems": 2
    }
  }
}
```
