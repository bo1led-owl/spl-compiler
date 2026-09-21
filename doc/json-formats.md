# JSON Formats and Schemas

## Overview

The SysProLang test suite uses JSON files to store golden test data for the lexer
and parser stages. These files are validated against JSON Schema definitions to
ensure consistency across test cases and compiler implementations.

## Schema files location

All schema files live in `test/schemas/`:

| Schema file | Validates | Description |
|---|---|---|
| `test/schemas/tokens.schema.json` | `tokens.json` | Token streams produced by the lexer |
| `test/schemas/ast.schema.json` | `ast.json` | AST trees produced by the parser |
| `test/schemas/meta.schema.json` | `meta.json` | Test case metadata |
| `test/schemas/config.schema.json` | `test/config.json` | Test runner configuration |

## Schema enforcement

### Validation script

Run `test/validate_schemas.py` to validate all JSON files against their schemas:

```bash
python3 test/validate_schemas.py
```

This script:
1. Loads all schema definitions from `test/schemas/`.
2. Scans recursively for `config.json`, `meta.json`, `tokens.json`, and `ast.json`
   files under the `test/` directory.
3. Validates each file against its respective schema using the `jsonschema` Python
   package.
4. Prints a checkmark (✓) for each valid file, or a cross (✗) with error details.
5. Exits with code 0 if all files are valid, 1 otherwise.

### Dependency

Install the `jsonschema` package:

```bash
pip install jsonschema
```

### CI enforcement

The CI workflow validates all schema files on every push. A PR with invalid JSON
files will be blocked.

---

## Token JSON format (`tokens.json`)

### Schema rules

- The file is a **JSON array** (top-level type: `array`).
- Every element is a **token object** with **required** properties:
  - `kind` (string): token kind identifier (e.g., `"IDENT"`, `"INT"`, `"PLUS"`,
    `"SEMI"`, `"EOF"`, etc.)
  - `line` (integer >= 1): source line where the token starts (1-based).
  - `column` (integer >= 1): source column where the token starts (1-based).
- No other properties are kept during golden comparison (the test runner's lexer
  stage preprocessor applies `{"keep": ["kind", "line", "column"]}`).
- The array must have at least 1 element (the `EOF` token is always present).
- The `kind` values are uppercase names like `IDENT`, `INT`, `PLUS`, `SEMI`, `EOF`,
  `IF`, `WHILE`, `RETURN`, `DEF`, `COLON`, `INT64`, `STRUCT`, `DOT`, etc.
- See each grammar `.md` file for the full list of token kinds introduced at each
  grammar version.

### Token comparison

During testing, both the golden `tokens.json` and the compiler's output are passed
through a JSON filter that drops all fields except `kind`, `line`, `column`. This
means the `value` field (which contains the raw token text in compiler output) is
**not compared**, allowing different compilers to use different string representations.

### Example

Source:

```scala
var x = 10;
return x / 2;
```

```json
[
{"kind": "VAR", "value": "var", "line": 1, "column": 1},
{"kind": "IDENT", "value": "x", "line": 1, "column": 5},
{"kind": "ASSIGN", "value": "=", "line": 1, "column": 7},
{"kind": "INT", "value": "10", "line": 1, "column": 9},
{"kind": "SEMI", "value": ";", "line": 1, "column": 11},
{"kind": "RETURN", "value": "return", "line": 2, "column": 1},
{"kind": "IDENT", "value": "x", "line": 2, "column": 8},
{"kind": "DIV", "value": "/", "line": 2, "column": 10},
{"kind": "INT", "value": "2", "line": 2, "column": 12},
{"kind": "SEMI", "value": ";", "line": 2, "column": 13},
{"kind": "EOF", "value": "", "line": 2, "column": 14}
]
```

### Token kind reference

See each grammar `.md` file for the complete list of token kinds (`"kind"` values)
introduced at each grammar version:

- [`doc/grammar1.md`](grammar1.md#token-kinds) — base tokens
- [`doc/grammar2.md`](grammar2.md#token-kinds-new-in-grammar-2) — control flow, boolean, comparison, logical
- [`doc/grammar3.md`](grammar3.md#token-kinds-new-in-grammar-3) — function definitions, extern
- [`doc/grammar4.md`](grammar4.md#token-kinds-new-in-grammar-4) — type keywords, cast, string
- [`doc/grammar5.md`](grammar5.md#token-kinds-new-in-grammar-5) — struct, array subscript, field access

---

## AST JSON format (`ast.json`)

### Schema rules

The schema defines a recursive `astNode` object with:

**Required properties** (every node must have these):

| Property | Type | Description |
|---|---|---|
| `line` | integer (>= 1) | Source line number where the node starts (1-based) |
| `column` | integer (>= 1) | Source column where the node starts (1-based) |
| `kind` | string | AST node kind (e.g., `"Program"`, `"Declare"`, `"IntLiteral"`, `"BinOp"`, etc.) |
| `elems` | array of `astNode` | Ordered list of child nodes (may be `[]`) |

**Additional properties** are allowed (not required, not restricted). These include
named attributes like `value`, `mut`, `type`, etc.

### AST comparison

During testing, both the golden `ast.json` and the compiler's output are passed
through a JSON filter that keeps only `kind`, `line`, `column`, `elems`.
All extra named fields (like `value`, `mut`, `type`, `name`, `op`, `message`,
`field`) are **dropped during comparison**. This means:

- The structure of the tree (what `elems` contains) is compared.
- Named extra properties serve as human-readable annotations but are not
  enforced in golden comparisons.

### The `elems[]` array convention

The `elems[]` array contains all child nodes in a fixed order. Named relationships
(left vs right, condition vs body, etc.) are **positional**:

| Node kind | `elems[]` order | Number of children |
|---|---|---|
| `Program` | top-level statements | N |
| `Block` | statements | N |
| `Return` | `[value]` | 1 (or 0 if missing) |
| `Declare` | `[name, expr?]` | 1 or 2 |
| `Assign` | `[name, expr]` | 2 |
| `If` | `[cond, thenBody, elseBody?]` | 2 or 3 |
| `While` | `[cond, body]` | 2 |
| `Break` | `[]` | 0 |
| `Continue` | `[]` | 0 |
| `IntLiteral` | `[]` | 0 |
| `BoolLiteral` | `[]` | 0 |
| `StringLiteral` | `[]` | 0 |
| `Ident` | `[]` | 0 |
| `BinOp` | `[left, right]` | 2 |
| `Unary` | `[operand]` | 1 |
| `Call` | `[callee, args...]` | 1 + N |
| `FuncDecl` | `[name, params..., body]` | N_params + 2 |
| `ExternDecl` | `[name, params...]` | N_params + 1 |
| `Param` | `[name]` | 1 |
| `Cast` | `[value]` | 1 |
| `StructDecl` | `[name, fields...]` | N_fields + 1 |
| `FieldAccess` | `[base, name]` | 2 |
| `Subscript` | `[base, index]` | 2 |
| `Error` | `[]` | 0 |

### Example

Source:

```scala
var x = 10;
return x / 2;
```

```json
{
  "line": 1,
  "column": 1,
  "kind": "Program",
  "elems": [
    {
      "line": 1,
      "column": 1,
      "kind": "Declare",
      "mut": "var",
      "elems": [
        {
          "line": 1,
          "column": 5,
          "kind": "Ident",
          "value": "x"
          "elems": [],
        },
        {
          "line": 1,
          "column": 9,
          "kind": "IntLiteral",
          "value": 10,
          "elems": []
        }
      ],
    },
    {
      "line": 2,
      "column": 1,
      "kind": "Return",
      "elems": [
        {
          "line": 2,
          "column": 10,
          "kind": "BinOp",
          "value": "/"
          "elems": [
            {
              "line": 2,
              "column": 8,
              "kind": "Ident",
              "value": "x"
              "elems": [],
            },
            {
              "line": 2,
              "column": 12,
              "kind": "IntLiteral",
              "value": 2,
              "elems": []
            }
          ],
        }
      ]
    }
  ],
}
```

---

## Meta JSON format (`meta.json`)

The `meta.json` file describes a test case's metadata. See
[`test/schemas/meta.schema.json`](../test/schemas/meta.schema.json) for the full
schema.

### Required properties

- `grammar`: grammar version constraint (string, list, or per-stage dict).
- `stages`: list of stage names to run (e.g., `["lexer", "parser"]`).
- `exit`: expected exit code (integer, `"nonzero"`, or per-stage dict).

### Example

```json
{
  "$schema": "../../schemas/meta.schema.json",
  "grammar": ">=2",
  "stages": ["lexer", "parser"],
  "exit": 0
}
```

The `$schema` key is optional but recommended for editor LSP support.

---

## Config JSON format (`config.json`)

The `test/config.json` file configures the test runner. It defines:

- Build command
- Default grammar version
- Available grammar versions
- Per-stage commands and output paths
- Preprocessing pipelines
- Fuzz testing parameters

See [`test/config.json`](../test/config.json) and
[`test/schemas/config.schema.json`](../test/schemas/config.schema.json) for details.

---

## Preprocessing and golden comparison

Both `tokens.json` and `ast.json` go through a preprocessing step before
diffing against golden files, defined in `test/config.json`:

```json
{
  "lexer": {
    "preprocess": [{"type": "json", "keep": ["kind", "line", "column"]}]
  },
  "parser": {
    "preprocess": [{"type": "json", "keep": ["kind", "line", "column", "elems"]}]
  }
}
```

The `json` preprocessor recursively filters each object tree, keeping only the
listed scalar fields while preserving all nested objects and arrays. This makes
golden comparison robust to differences in extra fields that different compilers
may or may not emit.

### What gets compared

| Stage | Golden file | Compared fields |
|---|---|---|
| lexer | `tokens.json` | `kind`, `line`, `column` |
| parser | `ast.json` | `kind`, `line`, `column`, `elems` |
| llvm | `out.ll` | Full text (after LLVM name normalization) |
| run | `stdout` | Full text (optional tolerance) |

> LLVM IR golden comparison (`out.ll`) is opt-in with `--check-ir`.
> By default, only lexer, parser, and run stages are checked.

## Grammar-by-grammar AST and token reference

For a detailed, grammar-by-grammar breakdown of which token kinds and AST node
kinds are introduced, see:

- [`doc/grammar1.md`](grammar1.md) — Token kinds and AST nodes for grammar 1
- [`doc/grammar2.md`](grammar2.md) — Token kinds and AST nodes new in grammar 2
- [`doc/grammar3.md`](grammar3.md) — Token kinds and AST nodes new in grammar 3
- [`doc/grammar4.md`](grammar4.md) — Token kinds and AST nodes new in grammar 4
- [`doc/grammar5.md`](grammar5.md) — Token kinds and AST nodes new in grammar 5
