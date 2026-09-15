# SysProLang

Version: 5

## Grammar

```bnf
program ::= { structDeclaration } { externDeclaration } { funcDeclaration } { statement } EOF

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

structDeclaration ::=
    "struct" IDENT "{" { fieldDeclaration } "}"

fieldDeclaration ::= IDENT ":" type ";"

returnStatement ::= "return" expression ";"

declarationStatement ::=
    "val" IDENT ":" type "=" expression ";"
  | "var" IDENT ":" type "=" expression ";"
  | "var" IDENT ":" type ";"
  | "val" IDENT ":" type ";"

assignmentStatement ::=
    postfixExpression "=" expression ";"

expressionStatement ::= expression ";"

ifStatement ::=
    "if" "(" expression ")" statement
    [ "else" statement ]

whileStatement ::= "while" "(" expression ")" statement

breakStatement ::= "break" ";"

continueStatement ::= "continue" ";"

externDeclaration ::=
    "extern" "def" IDENT "(" [ typedParamList ] ")" ":" type ";"

funcDeclaration ::=
    "def" IDENT "(" [ typedParamList ] ")" ":" type block

typedParamList ::= IDENT ":" type { "," IDENT ":" type }


; Type definitions

type ::= "Int8" | "Int16" | "Int32" | "Int64"
       | "Bool"
       | "String"
       | IDENT                          ; struct type (name)
       | type "[" INTEGER_LITERAL "]"   ; array type


; Expression definitions go from lowest operator precedence
; to the highest, allowing for straightforward expression parsing.
; Comparison operators produce Bool values.
; Logical operators && and || are short-circuit.
; Function call, field access, and array subscript have the highest precedence.
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
  | postfixExpression

postfixExpression ::=
    primaryExpression { postfixOp }

postfixOp ::=
    "(" [ argumentList ] ")"     ; function call
  | "." IDENT                    ; field access
  | "[" expression "]"           ; array subscript

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
- `struct`

### Semantic rules

All semantic rules from grammar 4 apply, plus:

- **Struct definitions** use `struct Name { field: Type; ... }`. Struct names must
  start with an uppercase letter.
- **Struct fields** can be any type: `Int8`, `Int16`, `Int32`, `Int64`, `Bool`,
  `String`, or another struct type. Nested structs are embedded by value.
- **Field access** uses dot notation: `expr.field`. The field must exist in the
  struct type.
- **Structs are value types**: assignment, passing to functions, and returning from
  functions all copy the entire struct by value. A struct assignment
  (`a = b` where both are structs) copies all fields (LLVM `memcpy`).
- **Passing structs to functions** is by value: the entire struct is copied.
- **Returning structs from functions** is by value (LLVM handles the ABI).
- **Passing structs to `extern` C functions** is not allowed (only primitive types and strings).
- **Arrays** are declared as `var arr: Type[N];` where `N` is a compile-time integer
  constant. The element type can be any type.
- **Array subscript** uses bracket notation: `arr[index]`. Indexing is zero-based.
  Out-of-bounds access is undefined behavior.
- **Arrays are value types**: an array assignment (`a = b`) copies all elements by
  value (LLVM `memcpy`). Arrays are stack-allocated in their declaring scope and
  cannot be passed to or returned from functions.
- **Error recovery**: see [`doc/error-handling.md`](error-handling.md) for the
  recommended error recovery strategy.
