grammar grammar4;

// Grammarinator (ANTLR v4) grammar for SysProLang v4 — Primitive types, String, cast.
//
// Adds explicit integer types (Int8, Int16, Int32, Int64), Bool type, String type
// with string literals ("hello"), and explicit cast<Type>(expr) for type conversions.
// Everything from grammars 1–3 is retained with type annotations added.
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

// Type annotations are required on all declarations.
declarationStatement : ('val' | 'var') IDENT ':' type '=' expression ';';

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

// extern declaration for C interop with typed parameters and return type.
externDeclaration : 'extern' 'def' IDENT '(' typedParamList? ')' ':' type ';';

// Function declaration with typed parameters and return type.
funcDeclaration : 'def' IDENT '(' typedParamList? ')' ':' type block;

// Type annotation on each parameter.
typedParamList : IDENT ':' type (',' IDENT ':' type)*;

// Primitive and built-in types.
type : INT8 | INT16 | INT32 | INT64 | BOOL | STRING;

// Expression definitions go from lowest operator precedence
// to the highest, allowing for straightforward expression parsing.
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
    | STRING_LITERAL
    | IDENT
    | 'true'
    | 'false'
    | '(' expression ')'
    | 'cast' '<' type '>' '(' expression ')'
    ;

// Lexical tokens

fragment NON_ZERO_DIGIT : [1-9];
fragment DIGIT : [0-9];

// Type keywords — defined before IDENT so they take priority.
INT8   : 'Int8';
INT16  : 'Int16';
INT32  : 'Int32';
INT64  : 'Int64';
BOOL   : 'Bool';
STRING : 'String';

INTEGER_LITERAL : '0' | NON_ZERO_DIGIT DIGIT*;

STRING_LITERAL : '"' (~["\\] | '\\' .)* '"';

IDENT : [a-zA-Z_] [a-zA-Z0-9_]*;

// Whitespace and comments. Declared for documentation and for the Grammarinator
// serializer (test/fuzz/whitespace.py), which emits these between terms; no
// parser rule references them.
WS : [ \t\n\r]+;
LINE_COMMENT : '//' ~[\r\n]*;
BLOCK_COMMENT : '/*' .*? '*/';