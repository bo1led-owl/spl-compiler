grammar grammar3;

// Grammarinator (ANTLR v4) grammar for SysProLang v3 — Functions.
//
// Adds function declarations (def) and extern declarations for C interop.
// Everything from grammars 1 and 2 is retained.
//
// Unlike the .md reference, whitespace and comments are modeled explicitly here:
// the WS, LINE_COMMENT and BLOCK_COMMENT lexical rules declare the tokens that
// the fuzzer's serializer (see test/fuzz/whitespace.py) inserts *arbitrarily*
// between terms when generating samples. No parser rule references these rules
// directly; the serializer emits them between tokens. Because the compiler's
// lexer runs a single-line comment to end-of-line, a generated line comment
// must always end with a newline (whitespace.py guarantees this).

program : externDeclaration* funcDeclaration* EOF;

statement
    : returnStatement
    | declarationStatement
    | assignmentStatement
    | expressionStatement
    | ifStatement
    | whileStatement
    | breakStatement
    | continueStatement
    | block
    ;

block : '{' statement* '}';

returnStatement : 'return' expression ';';

declarationStatement : ('val' | 'var') IDENT '=' expression ';';

assignmentStatement : IDENT '=' expression ';';

expressionStatement : expression ';';

// if/else/if-else chain — explicit alternatives so Grammarinator
// explores both branches evenly.
ifStatement
    : 'if' '(' expression ')' statement 'else' statement
    | 'if' '(' expression ')' statement
    ;

whileStatement : 'while' '(' expression ')' statement;

breakStatement : 'break' ';';

continueStatement : 'continue' ';';

// extern declaration for C interop.
// Example: extern def foo(a, b);
externDeclaration : 'extern' 'def' IDENT '(' paramList? ')' ';';

// Function declaration with optional parameters.
// Example: def add(a, b) { return a + b; }
funcDeclaration : 'def' IDENT '(' paramList? ')' block;

paramList : IDENT (',' IDENT)*;

// Expression definitions go from lowest operator precedence
// to the highest, allowing for straightforward expression parsing.
// Comparison operators produce integer values (0 or 1).
// Logical operators && and || are short-circuit.
expression : logicalOrExpression;

logicalOrExpression
    : logicalAndExpression ('||' logicalAndExpression)*
    ;

logicalAndExpression
    : equalityExpression ('&&' equalityExpression)*
    ;

equalityExpression
    : relationalExpression (('==' | '!=') relationalExpression)*
    ;

relationalExpression
    : additiveExpression (('<' | '>' | '<=' | '>=') additiveExpression)*
    ;

additiveExpression
    : multiplicativeExpression (('+' | '-') multiplicativeExpression)*
    ;

multiplicativeExpression
    : unaryExpression (('*' | '/') unaryExpression)*
    ;

unaryExpression
    : '!' unaryExpression
    | '-' unaryExpression
    | callExpression
    ;

// Function call has the highest precedence.
// Any primary expression can be followed by zero or more call arguments.
callExpression
    : primaryExpression ('(' argumentList? ')')*
    ;

argumentList : expression (',' expression)*;

primaryExpression
    : INTEGER_LITERAL
    | IDENT
    | 'true'
    | 'false'
    | '(' expression ')'
    ;

// Lexical tokens

fragment NON_ZERO_DIGIT : [1-9];
fragment DIGIT : [0-9];

INTEGER_LITERAL : '0' | NON_ZERO_DIGIT DIGIT*;

IDENT : [a-zA-Z_] [a-zA-Z0-9_]*;

// Whitespace and comments. Declared for documentation and for the Grammarinator
// serializer (test/fuzz/whitespace.py), which emits these between terms; no
// parser rule references them.
WS : [ \t\n\r]+;
LINE_COMMENT : '//' ~[\r\n]*;
BLOCK_COMMENT : '/*' .*? '*/';