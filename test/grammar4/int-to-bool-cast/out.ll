; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %x = alloca i64, align 8
  store i64 1, ptr %x, align 8
  %y = alloca i1, align 1
  %x1 = load i64, ptr %x, align 8
  %trunctmp = trunc i64 %x1 to i1
  store i1 %trunctmp, ptr %y, align 1
  %y2 = load i1, ptr %y, align 1
  br i1 %y2, label %then, label %else

then:                                             ; preds = %entry
  ret i64 1
  br label %ifmerge

ifmerge:                                          ; preds = %else, %then
  ret i64 0

else:                                             ; preds = %entry
  ret i64 0
  br label %ifmerge
}
