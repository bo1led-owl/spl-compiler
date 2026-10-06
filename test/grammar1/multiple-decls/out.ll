; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %a = alloca i64, align 8
  store i64 1, ptr %a, align 8
  %b = alloca i64, align 8
  store i64 2, ptr %b, align 8
  %c = alloca i64, align 8
  store i64 3, ptr %c, align 8
  %0 = load i64, ptr %a, align 8
  %1 = load i64, ptr %b, align 8
  %2 = add i64 %0, %1
  %3 = load i64, ptr %c, align 8
  %4 = add i64 %2, %3
  ret i64 %4
}
