; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @double(i64 %0) {
entry:
  %x = alloca i64, align 8
  store i64 %0, ptr %x, align 8
  %x1 = load i64, ptr %x, align 8
  %multmp = mul i64 %x1, 2
  ret i64 %multmp
}

define i64 @main() {
entry:
  %y = alloca i64, align 8
  %calltmp = call i64 @double(i64 21)
  store i64 %calltmp, ptr %y, align 8
  %y1 = load i64, ptr %y, align 8
  ret i64 %y1
}
