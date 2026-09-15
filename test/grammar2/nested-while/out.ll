; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %i = alloca i64, align 8
  store i64 0, ptr %i, align 8
  %j = alloca i64, align 8
  store i64 0, ptr %j, align 8
  br label %while_header

while_header:                                     ; preds = %while_end4, %entry
  %i1 = load i64, ptr %i, align 8
  %cmptmp = icmp slt i64 %i1, 10
  %zexttmp = zext i1 %cmptmp to i64
  %whilecond = icmp ne i64 %zexttmp, 0
  br i1 %whilecond, label %while_body, label %while_end

while_body:                                       ; preds = %while_header
  br label %while_header2

while_end:                                        ; preds = %while_header
  ret i64 0

while_header2:                                    ; preds = %while_body3, %while_body
  %j5 = load i64, ptr %j, align 8
  %cmptmp6 = icmp slt i64 %j5, 10
  %zexttmp7 = zext i1 %cmptmp6 to i64
  %whilecond8 = icmp ne i64 %zexttmp7, 0
  br i1 %whilecond8, label %while_body3, label %while_end4

while_body3:                                      ; preds = %while_header2
  %j9 = load i64, ptr %j, align 8
  %addtmp = add i64 %j9, 1
  store i64 %addtmp, ptr %j, align 8
  br label %while_header2

while_end4:                                       ; preds = %while_header2
  %i10 = load i64, ptr %i, align 8
  %addtmp11 = add i64 %i10, 1
  store i64 %addtmp11, ptr %i, align 8
  br label %while_header
}
