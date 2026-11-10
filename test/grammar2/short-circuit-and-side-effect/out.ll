; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %x = alloca i64, align 8
  store i64 0, ptr %x, align 8
  %x1 = load i64, ptr %x, align 8
  %cmptmp = icmp ne i64 %x1, 0
  %zexttmp = zext i1 %cmptmp to i64
  %lbool = icmp ne i64 %zexttmp, 0
  br i1 %lbool, label %logic.rhs, label %logic.end

logic.rhs:                                        ; preds = %entry
  %x2 = load i64, ptr %x, align 8
  %divtmp = sdiv i64 10, %x2
  %cmptmp3 = icmp sgt i64 %divtmp, 0
  %zexttmp4 = zext i1 %cmptmp3 to i64
  %rbool = icmp ne i64 %zexttmp4, 0
  br label %logic.end

logic.end:                                        ; preds = %logic.rhs, %entry
  %logictmp = phi i1 [ false, %entry ], [ %rbool, %logic.rhs ]
  %logicext = zext i1 %logictmp to i64
  %ifcond = icmp ne i64 %logicext, 0
  br i1 %ifcond, label %then, label %ifmerge

then:                                             ; preds = %logic.end
  ret i64 1
  br label %ifmerge

ifmerge:                                          ; preds = %then, %logic.end
  ret i64 0
}
