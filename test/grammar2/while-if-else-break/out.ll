; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %x = alloca i64, align 8
  store i64 0, ptr %x, align 8
  br label %while_header

while_header:                                     ; preds = %ifmerge, %entry
  %x1 = load i64, ptr %x, align 8
  %cmptmp = icmp slt i64 %x1, 10
  %zexttmp = zext i1 %cmptmp to i64
  %whilecond = icmp ne i64 %zexttmp, 0
  br i1 %whilecond, label %while_body, label %while_end

while_body:                                       ; preds = %while_header
  %x2 = load i64, ptr %x, align 8
  %cmptmp3 = icmp slt i64 %x2, 5
  %zexttmp4 = zext i1 %cmptmp3 to i64
  %ifcond = icmp ne i64 %zexttmp4, 0
  br i1 %ifcond, label %then, label %else

while_end:                                        ; preds = %else, %while_header
  %x6 = load i64, ptr %x, align 8
  ret i64 %x6

then:                                             ; preds = %while_body
  %x5 = load i64, ptr %x, align 8
  %addtmp = add i64 %x5, 1
  store i64 %addtmp, ptr %x, align 8
  br label %ifmerge

ifmerge:                                          ; preds = %else, %then
  br label %while_header

else:                                             ; preds = %while_body
  br label %while_end
  br label %ifmerge
}
