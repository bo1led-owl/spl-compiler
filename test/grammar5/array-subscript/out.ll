; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %arr = alloca [5 x i64], align 8
  store [5 x i64] zeroinitializer, ptr %arr, align 8
  %i = alloca i64, align 8
  store i64 0, ptr %i, align 8
  store i64 0, ptr %i, align 8
  %subsaddr = getelementptr [5 x i64], ptr %arr, i32 0, i64 0
  store i64 10, ptr %subsaddr, align 8
  %subsaddr1 = getelementptr [5 x i64], ptr %arr, i32 0, i64 1
  store i64 20, ptr %subsaddr1, align 8
  %subsaddr2 = getelementptr [5 x i64], ptr %arr, i32 0, i64 2
  store i64 30, ptr %subsaddr2, align 8
  %subsaddr3 = getelementptr [5 x i64], ptr %arr, i32 0, i64 3
  store i64 40, ptr %subsaddr3, align 8
  %subsaddr4 = getelementptr [5 x i64], ptr %arr, i32 0, i64 4
  store i64 50, ptr %subsaddr4, align 8
  %result = alloca i64, align 8
  %subsaddr5 = getelementptr [5 x i64], ptr %arr, i32 0, i64 2
  %substmp = load i64, ptr %subsaddr5, align 8
  store i64 %substmp, ptr %result, align 8
  %result6 = load i64, ptr %result, align 8
  ret i64 %result6
}
