#!/usr/bin/env python3
"""
Zero Trust Security Groups - Validation
Checks if security groups deny by default, no 0.0.0.0/0 on database ports
"""

import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent))
from cloud_patterns_scanner import CloudPatternsScanner


def main():
    """Validate Zero Trust Network pattern only"""
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║       ZERO TRUST NETWORK PATTERN - VALIDATION               ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print()

    project_root = Path(__file__).parent.parent.parent.parent
    output_dir = project_root / 'secops' / '2-findings' / 'raw'

    scanner = CloudPatternsScanner(
        scan_target=project_root,
        output_dir=output_dir,
        use_localstack=True
    )

    result = scanner.validate_zero_trust_network()

    print(f"Pattern: {result['pattern']}")
    print(f"Description: {result['description']}")
    print(f"Status: {result['status']}")
    print()

    if result['issues']:
        print(f"Issues Found: {result['issue_count']}")
        print()
        for i, issue in enumerate(result['issues'], 1):
            print(f"{i}. [{issue['severity']}] {issue['message']}")
            if 'resource' in issue:
                print(f"   Resource: {issue['resource']}")
            print(f"   Check: {issue['check']}")
            print(f"   Remediation: {issue['remediation']}")
            if 'compliance' in issue:
                print(f"   Compliance: {', '.join(issue['compliance'])}")
            if 'attack_vector' in issue:
                print(f"   Attack Vector: {issue['attack_vector']}")
            print()
    else:
        print("✅ All checks passed - pattern properly implemented")

    print("="*60)
    print(f"Result: {'FAIL' if result['issues'] else 'PASS'}")
    print("="*60)

    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
