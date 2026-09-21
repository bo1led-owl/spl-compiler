# SysProLang

Version: 3

## Grammar

```bnf
program ::= { topDeclaration } EOF

topDeclaration ::= externDeclaration
                 | funcDeclaration

externDeclaration ::= "extern" "def" IDENT "(" [ paramList ] ")" ";"

funcDeclaration ::= "def" IDENT "(" [ paramList ] ")" block

paramList ::= IDENT { "," IDENT }

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
; Function call has the highest precedence (tight binding).
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
- `def`
- `extern`

### Semantic rules

All semantic rules from grammar 2 apply, plus:

- **Function definitions** use `def name(params) { body }`. Parameters are passed
  by value. A function must have a `return` statement if it returns a value.
- **Functions are visible anywhere** in the program after they are defined (forward
  references are allowed --- the compiler can collect all function definitions before
  codegen).
- **`extern` declarations** declare a C function with no body. These are linked
  with the compiled program at the end. The calling convention is the C ABI.
- **Function calls** are expressions. A call evaluates all arguments, then transfers
  control to the function. The function's return value is the result of the call
  expression.
- **All values remain `Int64`** --- no type system yet. Functions take `Int64`
  parameters and return `Int64`.
- **A `main` function must be explicitly defined** Top-level statements are not allowed.
- **Error recovery**: see [`doc/error-handling.md`](error-handling.md) for the
  recommended error recovery strategy.

## Token kinds (new in grammar 3)

These `"kind"` values appear in `tokens.json` golden files, in addition to those from grammar 1–2:

| Token kind | Grammar source | Notes |
|---|---|---|
| `DEF` | `def` | Keyword |
| `EXTERN` | `extern` | Keyword |
| `COMMA` | `,` | Parameter/argument separator |

All tokens from grammar 1–2 also apply.

### Example

> TODO

## AST node kinds (new in grammar 3)

These `"kind"` values appear in `ast.json` golden files, in addition to those from grammar 1–2:

| AST kind  | `elems[]` children | Notes |
|---|---|---|
| `ExternDecl` | `[name, params...]` | `external def` function declaration |
| `FuncDecl` | `[name, params..., body]` | `def` function declaration with body as `Block` node |
| `Param` | `[name]` | Name is an `Ident` node |
| `Call` | `[callee, args...]` | Callee is an `Ident` node followed by argument expressions |

All AST kinds from grammar 1–2 also apply.

### Example

> TODO
