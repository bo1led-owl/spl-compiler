; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@.str.0 = private constant [3 x i8] c"hi\00"

define i64 @main() {
entry:
  %a = alloca i8, align 1
  store i8 1, ptr %a, align 1
  %b = alloca i16, align 2
  store i16 2, ptr %b, align 2
  %c = alloca i32, align 4
  store i32 3, ptr %c, align 4
  %d = alloca i64, align 8
  store i64 4, ptr %d, align 8
  %e = alloca i1, align 1
  store i1 true, ptr %e, align 1
  %f = alloca ptr, align 8
  store ptr @.str.0, ptr %f, align 8
  %d1 = load i64, ptr %d, align 8
  ret i64 %d1
}
