; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %x = alloca i1, align 1
  store i1 true, ptr %x, align 1
  %y = alloca i64, align 8
  %x1 = load i1, ptr %x, align 1
  %zexttmp = zext i1 %x1 to i64
  store i64 %zexttmp, ptr %y, align 8
  %y2 = load i64, ptr %y, align 8
  ret i64 %y2
}
