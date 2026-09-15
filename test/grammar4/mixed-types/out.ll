; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %i32 = alloca i32, align 4
  store i32 1000, ptr %i32, align 4
  %i16 = alloca i16, align 2
  %i321 = load i32, ptr %i32, align 4
  %trunctmp = trunc i32 %i321 to i16
  store i16 %trunctmp, ptr %i16, align 2
  %i64 = alloca i64, align 8
  %i162 = load i16, ptr %i16, align 2
  %sexttmp = sext i16 %i162 to i64
  store i64 %sexttmp, ptr %i64, align 8
  %i643 = load i64, ptr %i64, align 8
  ret i64 %i643
}
