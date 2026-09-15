; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare i64 @putchar(i64)

define i64 @main() {
entry:
  %a = alloca i64, align 8
  %calltmp = call i64 @putchar(i64 72)
  store i64 %calltmp, ptr %a, align 8
  %b = alloca i64, align 8
  %calltmp1 = call i64 @putchar(i64 105)
  store i64 %calltmp1, ptr %b, align 8
  ret i64 0
}
