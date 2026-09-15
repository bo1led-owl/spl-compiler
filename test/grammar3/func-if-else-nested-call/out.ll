; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @max(i64 %0, i64 %1) {
entry:
  %a = alloca i64, align 8
  store i64 %0, ptr %a, align 8
  %b = alloca i64, align 8
  store i64 %1, ptr %b, align 8
  %a1 = load i64, ptr %a, align 8
  %b2 = load i64, ptr %b, align 8
  %cmptmp = icmp sgt i64 %a1, %b2
  %zexttmp = zext i1 %cmptmp to i64
  %ifcond = icmp ne i64 %zexttmp, 0
  br i1 %ifcond, label %then, label %else

then:                                             ; preds = %entry
  %a3 = load i64, ptr %a, align 8
  ret i64 %a3
  br label %ifmerge

ifmerge:                                          ; preds = %else, %then
  ret i64 0

else:                                             ; preds = %entry
  %b4 = load i64, ptr %b, align 8
  ret i64 %b4
  br label %ifmerge
}

define i64 @main() {
entry:
  %m = alloca i64, align 8
  %calltmp = call i64 @max(i64 10, i64 20)
  store i64 %calltmp, ptr %m, align 8
  %m1 = load i64, ptr %m, align 8
  ret i64 %m1
}
