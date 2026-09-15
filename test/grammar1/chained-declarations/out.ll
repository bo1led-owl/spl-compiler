; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %x = alloca i64, align 8
  store i64 5, ptr %x, align 8
  %y = alloca i64, align 8
  %x1 = load i64, ptr %x, align 8
  store i64 %x1, ptr %y, align 8
  %y2 = load i64, ptr %y, align 8
  ret i64 %y2
}
