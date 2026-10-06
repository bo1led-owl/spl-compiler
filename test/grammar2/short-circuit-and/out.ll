; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %x = alloca i64, align 8
  store i64 1, ptr %x, align 8
  %y = alloca i64, align 8
  store i64 0, ptr %y, align 8
  %r = alloca i64, align 8
  store i64 0, ptr %r, align 8
  %x1 = load i64, ptr %x, align 8
  %cmptmp = icmp eq i64 %x1, 0
  %zexttmp = zext i1 %cmptmp to i64
  %y2 = load i64, ptr %y, align 8
  %cmptmp3 = icmp eq i64 %y2, 0
  %zexttmp4 = zext i1 %cmptmp3 to i64
  %lbool = icmp ne i64 %zexttmp, 0
  %rbool = icmp ne i64 %zexttmp4, 0
  %andtmp = and i1 %lbool, %rbool
  %andext = zext i1 %andtmp to i64
  %ifcond = icmp ne i64 %andext, 0
  br i1 %ifcond, label %then, label %ifmerge

then:                                             ; preds = %entry
  store i64 1, ptr %r, align 8
  br label %ifmerge

ifmerge:                                          ; preds = %then, %entry
  %r5 = load i64, ptr %r, align 8
  ret i64 %r5
}
