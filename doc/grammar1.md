# SysProLang

Version: 1

## Grammar

```bnf
program ::= { statement } EOF

statement ::=
    returnStatement
  | declarationStatement
  | assignmentStatement
  | expressionStatement

returnStatement ::= "return" expression ";"

declarationStatement ::= "val" IDENT "=" expression ";"
                       | "var" IDENT "=" expression ";"

assignmentStatement ::= IDENT "=" expression ";"

expressionStatement ::= expression ";"

; Expression definitions go from lowest operator precedence
; to the highest, allowing for straightforward expression parsing.
expression ::= additiveExpression

additiveExpression ::=
    multiplicativeExpression { ("+" | "-") multiplicativeExpression }

multiplicativeExpression ::=
    unaryExpression { ("*" | "/") unaryExpression }

unaryExpression ::=
    "-" unaryExpression
  | primaryExpression

primaryExpression ::=
    INTEGER_LITERAL
  | IDENT
  | "(" expression ")"


; Lexical tokens

INTEGER_LITERAL ::=
    "0"
  | NON_ZERO_DIGIT { DIGIT }

IDENT ::= NON_DIGIT { (NON_DIGIT | DIGIT) }

NON_DIGIT ::=
    "a" | "b" | ... | "z"
  | "A" | "B" | ... | "Z"
  | "_"

DIGIT ::= "0" | NON_ZERO_DIGIT

NON_ZERO_DIGIT ::=
    "1" | "2" | ... | "9"
```

> Comments and whitespaces are not explicit in above grammar.
> It is assumed that all terms in grammar rules (except lexical tokens)
> can have arbitrary number of whitespaces and/or comments between them.

### Comments

SysProLang uses C-style comments:

- Single-line: `//` ... end-of-line
- Multi-line: `/*` ... `*/`

### Keywords

- `return`
- `val`
- `var`

### Semantic rules

- **All variables must be declared** with `var` or `val` before use. Assignment to an
  undeclared identifier is a semantic error.
- **`val` declarations are immutable**: a `val` variable cannot appear on the left-hand
  side of an assignment.
- **Every program must have at least one statement** before EOF. The last statement must
  be a `return` statement (which terminates the implicit `main()` function).
- **All values are `Int64`** (64-bit signed integer). Integer literals are implicitly
  `Int64`.
- **The program body is the implicit `main()` function**: it is compiled as if wrapped
  in `def main() -> Int64 { ... }`. The `return` statement provides the return value.
- **Operator precedence** is encoded in the grammar: `+`/`-` lower than `*`/`/`,
  unary `-` highest. Parentheses override precedence.
- **Comments and whitespace** are ignored by the parser (handled by the lexer).
- **Error recovery**: see [`doc/error-handling.md`](error-handling.md) for the
  recommended error recovery strategy.

## Token kinds

These are the `"kind"` values that appear in `tokens.json` golden files:

| Token kind | Grammar source | Notes |
|---|---|---|
| `IDENT` | `IDENT` (any identifier) | |
| `INT` | `INTEGER_LITERAL` | |
| `RETURN` | `return` | Keyword |
| `VAL` | `val` | Keyword |
| `VAR` | `var` | Keyword |
| `PLUS` | `+` | |
| `MINUS` | `-` | |
| `MULT` | `*` | |
| `DIV` | `/` | |
| `ASSIGN` | `=` | Assignment |
| `LPAREN` | `(` | |
| `RPAREN` | `)` | |
| `SEMI` | `;` | |
| `EOF` | (end of file) | Always the last token |

> Comments are filtered out by the lexer before the parser sees them,
> so comment token kinds never appear in golden token files.

### Example

Source:

```
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

## AST node kinds

These are the `"kind"` values that appear in `ast.json` golden files:

| AST kind | `elems[]` children | Notes |
|---|---|---|
| `Program` | `[statements...]` | Wraps all top-level statements (implicit `main()`) |
| `Return` | `[expr]` | Return value is the single child |
| `Declare` | `[name, expr]` | `var`/`val` declaration with name as `Ident` node |
| `Assign` | `[name, expr]` | Name is an `Ident` node |
| `IntLiteral` | `[]` | Literal integer value |
| `Ident` | `[]` | Identifier name reference |
| `BinOp` | `[left, right]` | Binary arithmetic operator |
| `Unary` | `[operand]` | Unary minus |
| `Error` | `[]` | Produced during error recovery |

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
          "value": "x",
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
          "value": "/",
          "elems": [
            {
              "line": 2,
              "column": 8,
              "kind": "Ident",
              "value": "x",
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
