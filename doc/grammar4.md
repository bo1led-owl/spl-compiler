# SysProLang

Version: 4

## Grammar

```bnf
program ::= { topDeclaration } EOF

topDeclaration ::= externDeclaration
                 | funcDeclaration

externDeclaration ::=
    "extern" "def" IDENT "(" [ typedParamList ] ")" ":" type ";"

funcDeclaration ::=
    "def" IDENT "(" [ typedParamList ] ")" ":" type block

typedParamList ::= IDENT ":" type { "," IDENT ":" type }


; Type definitions

type ::= "Int8" | "Int16" | "Int32" | "Int64"
       | "Bool"
       | "String"


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

declarationStatement ::=
    "val" IDENT ":" type "=" expression ";"
  | "var" IDENT ":" type "=" expression ";"

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
; Comparison operators produce Bool values.
; Logical operators && and || are short-circuit.
; Function call has the highest precedence (tight binding).
; Cast expression binds like a primary expression.
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
  | callExpression

callExpression ::=
    primaryExpression { "(" [ argumentList ] ")" }

argumentList ::= expression { "," expression }

primaryExpression ::=
    INTEGER_LITERAL
  | STRING_LITERAL
  | IDENT
  | "true"
  | "false"
  | "(" expression ")"
  | "cast" "<" type ">" "(" expression ")"


; Lexical tokens

INTEGER_LITERAL ::=
    "0"
  | NON_ZERO_DIGIT { DIGIT }

STRING_LITERAL ::=
    '"' { CHARACTER | ESCAPE_SEQUENCE } '"'

ESCAPE_SEQUENCE ::=
    "\\" ( 'n' | 't' | '\\' | '"' )

CHARACTER ::= (any character except newline, backslash, or double quote)

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
- `def`
- `extern`
- `Int8`
- `Int16`
- `Int32`
- `Int64`
- `Bool`
- `String`
- `cast`

### Semantic rules

All semantic rules from grammar 3 apply, plus:

- **Type annotations are mandatory** on all variable declarations, function parameters,
  and function return types. The syntax is `var name: Type = expr;`.
- **No implicit conversions**: values of different types cannot be mixed in expressions.
  Use `cast<Type>(expr)` to explicitly convert between types.
- **`cast<Type>(expr)** supports:
  - Integer widening: `Int8` → `Int16` → `Int32` → `Int64` (LLVM: `sext`)
  - Integer narrowing: `Int64` → `Int32` → `Int16` → `Int8` (LLVM: `trunc`)
  - `Bool` to integer: `Bool` → `Int8`/`Int16`/`Int32`/`Int64` (LLVM: `zext` --- zero extension, not `sext`)
  - Integer to `Bool`: `Int8`/`Int16`/`Int32`/`Int64` → `Bool` (LLVM: `icmp ne %val, 0` or `trunc` to `i1`)
- **String literals** are of type `String`. A string literal is a null-terminated
  byte array compiled as a global constant. `String` maps to `ptr` in LLVM IR.
- **String variables** are pointers to the string data. Assigning a string literal
  to a `String` variable stores the pointer to the global constant.
- **String comparison** with `==` and `!=` compares string contents, not pointers.
  During codegen, emit a call to `strcmp` from the C standard library:
  ```llvm
  declare i32 @strcmp(ptr, ptr)
  ```
  Compare the return value against `0` to get a `Bool` result.
- **String operations**: The built-in runtime library provides `print_string`
  and `println_string` for output. String concatenation, indexing, and length
  are not part of the core language.
- **The `Bool` type** is distinct from `Int8`. `true` and `false` are `Bool` values.
  Comparison operators return `Bool`. Logical operators `&&`, `||`, `!` require
  `Bool` operands and produce `Bool`.
- **Integer literals** have the type of their declared context. A literal `42` in
  `var x: Int8 = 42;` is `Int8`. In `var x: Int64 = 42;` it is `Int64`.
- **Operators** (`+`, `-`, `*`, `/`, comparisons) require both operands to have the
  same type. Use `cast` if they differ.
- **Extern functions** must specify parameter and return types: `extern def foo(x: Int64): Int64;`
- **Error recovery**: see [`doc/error-handling.md`](error-handling.md) for the
  recommended error recovery strategy.

## Token kinds (new in grammar 4)

These `"kind"` values appear in `tokens.json` golden files, in addition to those from grammar 1–3:

| Token kind | Grammar source | Notes |
|---|---|---|
| `INT8` | `Int8` | Type keyword |
| `INT16` | `Int16` | Type keyword |
| `INT32` | `Int32` | Type keyword |
| `INT64` | `Int64` | Type keyword |
| `BOOL` | `Bool` | Type keyword |
| `STRING` | `String` | Type keyword |
| `CAST` | `cast` | Type conversion keyword |
| `COLON` | `:` | Type annotation separator |
| `STR` | `STRING_LITERAL` | String literal content |

All tokens from grammar 1–3 also apply.

### Example

> TODO

## AST node kinds (new in grammar 4)

These `"kind"` values appear in `ast.json` golden files, in addition to those from grammar 1–3:

| AST kind | `elems[]` children | Notes |
|---|---|---|
| `StringLiteral` | `[]` | |
| `Cast` | `[value]` | Has additional `type` property with the target type name |

### Type annotations

> TODO

### Example

> TODO
