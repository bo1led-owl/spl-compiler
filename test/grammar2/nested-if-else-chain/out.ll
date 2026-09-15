; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  br i1 true, label %then, label %else

then:                                             ; preds = %entry
  ret i64 1
  br label %ifmerge

ifmerge:                                          ; preds = %ifmerge2, %then
  ret i64 0

else:                                             ; preds = %entry
  br i1 false, label %then1, label %else3

then1:                                            ; preds = %else
  ret i64 2
  br label %ifmerge2

ifmerge2:                                         ; preds = %else3, %then1
  br label %ifmerge

else3:                                            ; preds = %else
  ret i64 3
  br label %ifmerge2
}
