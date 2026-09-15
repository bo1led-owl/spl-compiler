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
  %z = alloca i64, align 8
  store i64 0, ptr %z, align 8
  %x1 = load i64, ptr %x, align 8
  %ifcond = icmp ne i64 %x1, 0
  br i1 %ifcond, label %then, label %else

then:                                             ; preds = %entry
  %y2 = load i64, ptr %y, align 8
  %ifcond3 = icmp ne i64 %y2, 0
  br i1 %ifcond3, label %then4, label %else6

ifmerge:                                          ; preds = %else, %ifmerge5
  ret i64 0

else:                                             ; preds = %entry
  store i64 3, ptr %z, align 8
  br label %ifmerge

then4:                                            ; preds = %then
  store i64 1, ptr %z, align 8
  br label %ifmerge5

ifmerge5:                                         ; preds = %else6, %then4
  br label %ifmerge

else6:                                            ; preds = %then
  store i64 2, ptr %z, align 8
  br label %ifmerge5
}
