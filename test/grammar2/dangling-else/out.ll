; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  br i1 true, label %then, label %ifmerge

then:                                             ; preds = %entry
  br i1 false, label %then1, label %else

ifmerge:                                          ; preds = %ifmerge2, %entry
  ret i64 0

then1:                                            ; preds = %then
  ret i64 1
  br label %ifmerge2

ifmerge2:                                         ; preds = %else, %then1
  br label %ifmerge

else:                                             ; preds = %then
  ret i64 2
  br label %ifmerge2
}
