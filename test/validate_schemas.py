#!/usr/bin/env python3
"""Validate all config.json, meta.json, tokens.json and ast.json files against their JSON schemas.

Usage:
  python test/validate_schemas.py

Exit code:
  0 — all files valid
  1 — one or more files invalid (details printed to stderr)
"""

import glob
import json
import os
import sys
import traceback

try:
    from jsonschema import validate, ValidationError
except ImportError:
    print("error: 'jsonschema' package not installed. Run: pip install jsonschema",
          file=sys.stderr)
    sys.exit(1)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEMA_DIR = os.path.join(SCRIPT_DIR, "schemas")


def load_schema(name):
    path = os.path.join(SCHEMA_DIR, name)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def validate_file(filepath, schema, label):
    """Validate a single JSON file against a schema. Returns (path, error|None)."""
    try:
        with open(filepath, encoding="utf-8") as f:
            data = json.load(f)
        validate(instance=data, schema=schema)
        return (filepath, None)
    except json.JSONDecodeError as e:
        return (filepath, f"invalid JSON: {e}")
    except ValidationError as e:
        # Short, readable error: field path + message
        path = " → ".join(str(p) for p in e.absolute_path) if e.absolute_path else "(root)"
        return (filepath, f"{path}: {e.message.split(chr(10))[0]}")
    except Exception as e:
        return (filepath, traceback.format_exc())


def main():
    config_schema = load_schema("config.schema.json")
    meta_schema = load_schema("meta.schema.json")

    # 1. Validate config.json
    config_path = os.path.join(SCRIPT_DIR, "config.json")
    results = [validate_file(config_path, config_schema, "config.json")]

    # 2. Validate all meta.json files under test/
    test_root = SCRIPT_DIR  # SCRIPT_DIR is test/
    meta_pattern = os.path.join(test_root, "**", "meta.json")
    for path in sorted(glob.glob(meta_pattern, recursive=True)):
        results.append(validate_file(path, meta_schema, "meta.json"))

    tokens_schema = load_schema("tokens.schema.json")

    # 3. Validate all tokens.json files under test/
    tokens_pattern = os.path.join(test_root, "**", "tokens.json")
    for path in sorted(glob.glob(tokens_pattern, recursive=True)):
        results.append(validate_file(path, tokens_schema, "tokens.json"))

    ast_schema = load_schema("ast.schema.json")

    # 4. Validate all ast.json files under test/
    ast_pattern = os.path.join(test_root, "**", "ast.json")
    for path in sorted(glob.glob(ast_pattern, recursive=True)):
        results.append(validate_file(path, ast_schema, "ast.json"))

    # Print results
    failed = 0
    for path, error in results:
        rel = os.path.relpath(path, os.path.dirname(SCRIPT_DIR))
        if error is None:
            print(f"✓  {rel}")
        else:
            print(f"✗  {rel}")
            print(f"   {error}", file=sys.stderr)
            failed += 1

    total = len(results)
    print(f"\n{total - failed}/{total} files valid (config.json / meta.json / tokens.json / ast.json)", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())