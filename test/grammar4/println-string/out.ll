; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@.str.0 = private constant [12 x i8] c"hello world\00"

declare void @println_string(ptr)

define i64 @main() {
entry:
  call void @println_string(ptr @.str.0)
  ret i64 0
}
