; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %a = alloca i1, align 1
  store i1 true, ptr %a, align 1
  %b = alloca i1, align 1
  store i1 false, ptr %b, align 1
  %cmp = alloca i1, align 1
  store i1 true, ptr %cmp, align 1
  ret i64 0
}
