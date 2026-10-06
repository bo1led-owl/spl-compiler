; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare void @println_int(i64)

define i64 @fact(i64 %0) {
entry:
  %n = alloca i64, align 8
  store i64 %0, ptr %n, align 8
  %n1 = load i64, ptr %n, align 8
  %cmptmp = icmp sle i64 %n1, 1
  br i1 %cmptmp, label %then, label %ifmerge

then:                                             ; preds = %entry
  ret i64 1
  br label %ifmerge

ifmerge:                                          ; preds = %then, %entry
  %n2 = load i64, ptr %n, align 8
  %n3 = load i64, ptr %n, align 8
  %subtmp = sub i64 %n3, 1
  %calltmp = call i64 @fact(i64 %subtmp)
  %multmp = mul i64 %n2, %calltmp
  ret i64 %multmp
}

define i64 @main() {
entry:
  %calltmp = call i64 @fact(i64 5)
  call void @println_int(i64 %calltmp)
  ret i64 0
}
