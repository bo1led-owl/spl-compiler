; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@.str.0 = private constant [14 x i8] c"hello\0Aworld\09!\00"
@.str.1 = private constant [13 x i8] c"quote \22 here\00"
@.str.2 = private constant [11 x i8] c"back\\slash\00"

define i64 @main() {
entry:
  %s = alloca ptr, align 8
  store ptr @.str.0, ptr %s, align 8
  %t = alloca ptr, align 8
  store ptr @.str.1, ptr %t, align 8
  %u = alloca ptr, align 8
  store ptr @.str.2, ptr %u, align 8
  ret i64 0
}
