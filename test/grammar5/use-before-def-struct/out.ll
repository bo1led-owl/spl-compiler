; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Config = type { i64, ptr }

@.str.0 = private constant [4 x i8] c"abc\00"

define i64 @main() {
entry:
  %c = alloca %Config, align 8
  store %Config zeroinitializer, ptr %c, align 8
  %fieldaddr = getelementptr inbounds nuw %Config, ptr %c, i32 0, i32 0
  store i64 3, ptr %fieldaddr, align 8
  %fieldaddr1 = getelementptr inbounds nuw %Config, ptr %c, i32 0, i32 1
  store ptr @.str.0, ptr %fieldaddr1, align 8
  %fieldaddr2 = getelementptr inbounds nuw %Config, ptr %c, i32 0, i32 0
  %fieldtmp = load i64, ptr %fieldaddr2, align 8
  %addtmp = add i64 %fieldtmp, 4
  ret i64 %addtmp
}
