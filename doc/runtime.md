# SysProLang Runtime Library

The runtime library provides helper functions that your compiled programs
can call via `extern` declarations. It is compiled separately and linked
with the LLVM IR output of your compiler.

## Source code

The runtime library is a small C library that lives in the `libruntime/` directory:

```
libruntime/
  CMakeLists.txt       # CMake build (optional — compile manually too)
  spl_runtime.h        # Function declarations
  spl_runtime.c        # Implementations
```

The starter repository provides these files as part of the
`libruntime/` directory. If you are writing your own compiler from scratch,
you will need to create them yourself following the interface below.

## Functions

### Grammar 3+

| Function | Signature | Description |
|----------|-----------|-------------|
| `print_int` | `void print_int(int64_t val)` | Print an integer to stdout (no newline) |
| `println_int` | `void println_int(int64_t val)` | Print an integer followed by newline |
| `println` | `void println()` | Print a newline only |
| `print_string` | `void print_string(const char* val)` | Print a string to stdout |
| `println_string` | `void println_string(const char* val)` | Print a string followed by newline |

From grammar 4 on, these are declared in SysProLang as `Void` functions:

```spl
extern def print_int(x: Int64): Void;
extern def println_int(x: Int64): Void;
extern def println(): Void;
extern def print_string(s: String): Void;
extern def println_string(s: String): Void;
```

> Grammar 3 has no `Void` type: declare runtime functions with an omitted or
> dummy return type appropriate for your implementation (all values are `Int64`).

These are called via the `extern` mechanism introduced in grammar 3.
They are compiled as a separate C library and linked with your output.

> Grammar 4 adds string support: `print_string` takes a `String` parameter
> which maps to `ptr` in LLVM IR (pointer to null-terminated bytes).

> Heap allocation functions (`malloc`/`free`) are not part of the runtime.
> If you tackle grammar 6 (stretch), declare them directly as extern C
> functions — they are not keywords, just regular extern declarations.

## Using the Runtime

### From your compiler's generated LLVM IR

```llvm
; Declare runtime functions
declare void @print_int(i64)
declare void @println_int(i64)
declare void @println()
declare void @print_string(ptr)
declare void @println_string(ptr)

define i64 @main() {
entry:
    call void @print_int(i64 42)
    call void @println()
    call void @print_string(ptr @str)
    ret i64 0
}
```

### Linking with the runtime

```bash
# 1. Build the runtime library (if using CMake)
cmake -S . -B build && cmake --build build

# 2. Your compiler produces output.ll
./splc -o output.ll source.spl

# 3. Link with runtime and produce executable
clang output.ll -Lbuild/libruntime -lsplruntime -o program

# 4. Run
./program
```

Your compiler's workflow may differ — the harness only needs an executable.
You can embed the runtime by having your compiler emit `declare` statements
and link with `clang`.

## Adding New Runtime Functions

If you need additional helpers for your compiler (e.g., for achievements),
add them to `spl_runtime.c` and declare them as `extern` in your language:

```c
// spl_runtime.c
int64_t my_helper(int64_t x, int64_t y) {
    return x * y + 1;
}
```

```spl
extern def my_helper(Int64, Int64) -> Int64;
```

Then declare in LLVM IR:
```llvm
declare i64 @my_helper(i64, i64)
```

## Notes

- All runtime functions use the C calling convention (default in LLVM).
- The runtime is written in C11 and compiles with `clang` or `gcc`.
- Students writing their compiler in Rust, Python, etc. still link the C
  runtime — their compiler just emits LLVM IR that calls these functions.

## Installation and linking

For LLVM/Clang installation, compiling generated IR into executables, and
setting up the test harness `compile` stage, see
[`doc/setup.md`](setup.md).