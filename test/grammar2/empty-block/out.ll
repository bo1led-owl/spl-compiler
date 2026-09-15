; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %x = alloca i64, align 8
  store i64 1, ptr %x, align 8
  br label %while_header

while_header:                                     ; preds = %while_body, %entry
  %x1 = load i64, ptr %x, align 8
  %whilecond = icmp ne i64 %x1, 0
  br i1 %whilecond, label %while_body, label %while_end

while_body:                                       ; preds = %while_header
  br label %while_header

while_end:                                        ; preds = %while_header
  ret i64 0
}
