; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %a = alloca i64, align 8
  store i64 1, ptr %a, align 8
  %b = alloca i64, align 8
  store i64 0, ptr %b, align 8
  %c = alloca i64, align 8
  %a1 = load i64, ptr %a, align 8
  %lbool = icmp ne i64 %a1, 0
  br i1 %lbool, label %logic.rhs, label %logic.end

logic.rhs:                                        ; preds = %entry
  %b2 = load i64, ptr %b, align 8
  %rbool = icmp ne i64 %b2, 0
  br label %logic.end

logic.end:                                        ; preds = %logic.rhs, %entry
  %logictmp = phi i1 [ false, %entry ], [ %rbool, %logic.rhs ]
  %logicext = zext i1 %logictmp to i64
  %lbool3 = icmp ne i64 %logicext, 0
  br i1 %lbool3, label %logic.end5, label %logic.rhs4

logic.rhs4:                                       ; preds = %logic.end
  %a6 = load i64, ptr %a, align 8
  %nottmp = icmp eq i64 %a6, 0
  %notext = zext i1 %nottmp to i64
  %rbool7 = icmp ne i64 %notext, 0
  br label %logic.end5

logic.end5:                                       ; preds = %logic.rhs4, %logic.end
  %logictmp8 = phi i1 [ true, %logic.end ], [ %rbool7, %logic.rhs4 ]
  %logicext9 = zext i1 %logictmp8 to i64
  store i64 %logicext9, ptr %c, align 8
  %c10 = load i64, ptr %c, align 8
  ret i64 %c10
}
