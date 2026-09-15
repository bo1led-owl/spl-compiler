; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %cmp = alloca i64, align 8
  store i64 0, ptr %cmp, align 8
  %cmp2 = alloca i64, align 8
  store i64 1, ptr %cmp2, align 8
  %cmp3 = alloca i64, align 8
  store i64 1, ptr %cmp3, align 8
  %cmp4 = alloca i64, align 8
  store i64 0, ptr %cmp4, align 8
  %cmp5 = alloca i64, align 8
  store i64 1, ptr %cmp5, align 8
  %cmp6 = alloca i64, align 8
  store i64 0, ptr %cmp6, align 8
  ret i64 0
}
