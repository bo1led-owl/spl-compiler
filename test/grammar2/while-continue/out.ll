; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %i = alloca i64, align 8
  store i64 0, ptr %i, align 8
  %x = alloca i64, align 8
  store i64 0, ptr %x, align 8
  br label %while_header

while_header:                                     ; preds = %ifmerge, %then, %entry
  %i1 = load i64, ptr %i, align 8
  %cmptmp = icmp slt i64 %i1, 5
  %zexttmp = zext i1 %cmptmp to i64
  %whilecond = icmp ne i64 %zexttmp, 0
  br i1 %whilecond, label %while_body, label %while_end

while_body:                                       ; preds = %while_header
  %i2 = load i64, ptr %i, align 8
  %addtmp = add i64 %i2, 1
  store i64 %addtmp, ptr %i, align 8
  %i3 = load i64, ptr %i, align 8
  %cmptmp4 = icmp eq i64 %i3, 3
  %zexttmp5 = zext i1 %cmptmp4 to i64
  %ifcond = icmp ne i64 %zexttmp5, 0
  br i1 %ifcond, label %then, label %ifmerge

while_end:                                        ; preds = %while_header
  ret i64 0

then:                                             ; preds = %while_body
  br label %while_header
  br label %ifmerge

ifmerge:                                          ; preds = %then, %while_body
  %x6 = load i64, ptr %x, align 8
  %addtmp7 = add i64 %x6, 1
  store i64 %addtmp7, ptr %x, align 8
  br label %while_header
}
