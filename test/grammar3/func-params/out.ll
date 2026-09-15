; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @add(i64 %0, i64 %1) {
entry:
  %a = alloca i64, align 8
  store i64 %0, ptr %a, align 8
  %b = alloca i64, align 8
  store i64 %1, ptr %b, align 8
  %result = alloca i64, align 8
  %a1 = load i64, ptr %a, align 8
  %b2 = load i64, ptr %b, align 8
  %addtmp = add i64 %a1, %b2
  store i64 %addtmp, ptr %result, align 8
  %result3 = load i64, ptr %result, align 8
  ret i64 %result3
}

define i64 @main() {
entry:
  ret i64 0
}
