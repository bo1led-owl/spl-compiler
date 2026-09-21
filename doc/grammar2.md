# SysProLang

Version: 2

## Grammar

```bnf
program ::= { statement } EOF

statement ::=
    returnStatement
  | declarationStatement
  | assignmentStatement
  | expressionStatement
  | ifStatement
  | whileStatement
  | breakStatement
  | continueStatement
  | block

block ::= "{" { statement } "}"

returnStatement ::= "return" expression ";"

declarationStatement ::= "val" IDENT "=" expression ";"
                       | "var" IDENT "=" expression ";"

assignmentStatement ::= IDENT "=" expression ";"

expressionStatement ::= expression ";"

ifStatement ::=
    "if" "(" expression ")" statement
    [ "else" statement ]

whileStatement ::= "while" "(" expression ")" statement

breakStatement ::= "break" ";"

continueStatement ::= "continue" ";"


; Expression definitions go from lowest operator precedence
; to the highest, allowing for straightforward expression parsing.
; Comparison operators produce integer values (0 or 1).
; Logical operators && and || are short-circuit.
expression ::= logicalOrExpression

logicalOrExpression ::=
    logicalAndExpression { "||" logicalAndExpression }

logicalAndExpression ::=
    equalityExpression { "&&" equalityExpression }

equalityExpression ::=
    relationalExpression { ("==" | "!=") relationalExpression }

relationalExpression ::=
    additiveExpression { ("<" | ">" | "<=" | ">=") additiveExpression }

additiveExpression ::=
    multiplicativeExpression { ("+" | "-") multiplicativeExpression }

multiplicativeExpression ::=
    unaryExpression { ("*" | "/") unaryExpression }

unaryExpression ::=
    "!" unaryExpression
  | "-" unaryExpression
  | primaryExpression

primaryExpression ::=
    INTEGER_LITERAL
  | IDENT
  | "true"
  | "false"
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
- `if`
- `else`
- `while`
- `break`
- `continue`
- `true`
- `false`

### Semantic rules

All semantic rules from grammar 1 apply, plus:

- **`if` condition** is truthy if the expression evaluates to a non-zero value.
  The `else` branch is optional.
- **`while` loop** repeats the body as long as the condition is non-zero.
- **`break`** exits the innermost enclosing `while` loop immediately.
  A `break` outside any loop is a semantic error.
- **`continue`** jumps to the loop condition check of the innermost enclosing `while`
  loop. A `continue` outside any loop is a semantic error.
- **Boolean constants** `true` and `false` are integer values `1` and `0` respectively.
- **Comparison operators** (`==`, `!=`, `<`, `>`, `<=`, `>=`) produce integer values
  (`1` for true, `0` for false).
- **Logical operators** `&&` and `||` are short-circuit: `&&` evaluates the right
  operand only if the left is non-zero; `||` evaluates the right operand only if
  the left is zero. `!` negates (non-zero becomes `0`, zero becomes `1`).
- **All values remain `Int64`** --- no type system yet.
- **Error recovery**: see [`doc/error-handling.md`](error-handling.md) for the
  recommended error recovery strategy.

## Token kinds (new in grammar 2)

These `"kind"` values appear in `tokens.json` golden files, in addition to those from grammar 1:

| Token kind | Grammar source | Notes |
|---|---|---|
| `IF` | `if` | Keyword |
| `ELSE` | `else` | Keyword |
| `WHILE` | `while` | Keyword |
| `BREAK` | `break` | Keyword |
| `CONTINUE` | `continue` | Keyword |
| `TRUE` | `true` | Boolean literal |
| `FALSE` | `false` | Boolean literal |
| `LBRACE` | `{` | Block opening |
| `RBRACE` | `}` | Block closing |
| `EQ` | `==` | Equality |
| `NE` | `!=` | Inequality |
| `LT` | `<` | Less-than |
| `GT` | `>` | Greater-than |
| `LE` | `<=` | Less-or-equal |
| `GE` | `>=` | Greater-or-equal |
| `AND` | `&&` | Logical AND (short-circuit) |
| `OR` | `\|\|` | Logical OR (short-circuit) |
| `NOT` | `!` | Logical NOT |

All tokens from grammar 1 also apply.

### Example

> TODO

## AST node kinds (new in grammar 2)

These `"kind"` values appear in `ast.json` golden files, in addition to those from grammar 1:

| AST kind | `elems[]` children | Notes |
|---|---|---|
| `If` | `[cond, thenBody, elseBody?]` | `elseBody` is omitted if absent (2 or 3 children) |
| `While` | `[cond, body]` | |
| `Break` | `[]` | |
| `Continue` | `[]` | |
| `Block` | `[statements..]` | Wraps a `{ ... }` block |
| `BoolLiteral` | `[]` | Boolean literal |
| `BinOp` | `[left, right]` | New operators: `"=="`, `"!="`, `"<"`, `">"`, `"<="`, `">="`, `"&&"`, `"\|\|"` |
| `Unary` | `[operand]` | New operator: `"!"` |

All AST kinds from grammar 1 also apply.

### Notes on expression AST

- `==`, `!=`, `<`, `>`, `<=`, `>=` comparisons are represented as `BinOp` nodes.
- `&&`, `||` are also `BinOp` nodes.
- `!` (logical NOT) is a `Unary` node.
- `true` and `false` literals are `BoolLiteral` nodes. In grammar 2 (no type system)
  semantically they are treated as `Int64` 1 or 0.
- `If` nodes have `elems[0]` = condition, `elems[1]` = then-body, and optionally
  `elems[2]` = else-body. The presence of exactly 2 or 3 children distinguishes
  `if (cond) stmt` from `if (cond) stmt else stmt`.

### Example

> TODO
