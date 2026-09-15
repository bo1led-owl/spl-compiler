; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@.str.0 = private constant [6 x i8] c"hello\00"
@.str.1 = private constant [6 x i8] c"world\00"

define i64 @main() {
entry:
  %s = alloca ptr, align 8
  store ptr @.str.0, ptr %s, align 8
  %msg = alloca ptr, align 8
  store ptr @.str.1, ptr %msg, align 8
  ret i64 0
}
