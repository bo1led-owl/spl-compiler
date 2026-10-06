; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @bar() {
entry:
  ret i64 42
}

declare void @println_int(i64)

define i64 @baz(i64 %0) {
entry:
  %y = alloca i64, align 8
  store i64 %0, ptr %y, align 8
  %y1 = load i64, ptr %y, align 8
  ret i64 %y1
}

declare void @putchar(i8)

define i64 @main() {
entry:
  call void @putchar(i8 66)
  call void @putchar(i8 10)
  %calltmp = call i64 @baz(i64 42)
  call void @println_int(i64 %calltmp)
  %calltmp1 = call i64 @bar()
  ret i64 %calltmp1
}
