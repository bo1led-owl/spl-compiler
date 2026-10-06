; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@.str.0 = private constant [5 x i8] c"done\00"
@.str.1 = private constant [3 x i8] c"hi\00"

define void @log(ptr %0) {
entry:
  %msg = alloca ptr, align 8
  store ptr %0, ptr %msg, align 8
  %msg1 = load ptr, ptr %msg, align 8
  %calltmp = call i64 @println_string(ptr %msg1)
  ret void
}

declare i64 @println_string(i64)

define void @maybe(i1 %0) {
entry:
  %skip = alloca i1, align 1
  store i1 %0, ptr %skip, align 1
  %skip1 = load i1, ptr %skip, align 1
  br i1 %skip1, label %then, label %ifmerge

then:                                             ; preds = %entry
  ret void
  br label %ifmerge

ifmerge:                                          ; preds = %then, %entry
  %calltmp = call i64 @println_string(ptr @.str.0)
  ret void
}

define i64 @main() {
entry:
  call void @log(ptr @.str.1)
  call void @maybe(i1 true)
  ret i64 0
}
