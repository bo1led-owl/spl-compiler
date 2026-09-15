; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare i64 @putchar(i8)

declare i64 @exit(i64)

define i64 @main() {
entry:
  %r = alloca i64, align 8
  %calltmp = call i64 @putchar(i8 65)
  store i64 %calltmp, ptr %r, align 8
  %code = alloca i64, align 8
  store i64 0, ptr %code, align 8
  %code1 = load i64, ptr %code, align 8
  ret i64 %code1
}
