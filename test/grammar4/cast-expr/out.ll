; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %x = alloca i8, align 1
  store i8 42, ptr %x, align 1
  %y = alloca i16, align 2
  %x1 = load i8, ptr %x, align 1
  %sexttmp = sext i8 %x1 to i16
  store i16 %sexttmp, ptr %y, align 2
  %z = alloca i32, align 4
  %y2 = load i16, ptr %y, align 2
  %sexttmp3 = sext i16 %y2 to i32
  store i32 %sexttmp3, ptr %z, align 4
  %w = alloca i64, align 8
  %z4 = load i32, ptr %z, align 4
  %sexttmp5 = sext i32 %z4 to i64
  store i64 %sexttmp5, ptr %w, align 8
  %w6 = load i64, ptr %w, align 8
  ret i64 %w6
}
