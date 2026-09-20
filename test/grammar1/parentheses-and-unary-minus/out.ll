; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %result = alloca i64, align 8
  store i64 -2, ptr %result, align 8
  %result1 = load i64, ptr %result, align 8
  %negtmp = sub i64 0, %result1
  ret i64 %negtmp
}
