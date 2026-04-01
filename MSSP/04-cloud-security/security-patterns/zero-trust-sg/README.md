# Zero-Trust Security Groups Pattern

## Overview
Security Group chaining pattern - never use 0.0.0.0/0 for internal traffic.

## Flashcard Mapping
**Goal:** Zero-trust internal access
**Practice:** SG referencing SG (no 0.0.0.0/0)
**Tool:** Security Groups

## Architecture
- Security groups reference other security groups (not CIDR blocks)
- Least-privilege network access
- No 0.0.0.0/0 rules on internal resources

## Compliance
- CIS AWS Foundations: 5.2, 5.3
- PCI-DSS: 1.2.1
- NIST: AC-3, AC-4

## Cost
Free (no additional AWS charges)
