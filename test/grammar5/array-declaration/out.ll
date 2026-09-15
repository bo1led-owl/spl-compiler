; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %arr = alloca [10 x i64], align 8
  store [10 x i64] zeroinitializer, ptr %arr, align 8
  %subsaddr = getelementptr [10 x i64], ptr %arr, i32 0, i64 0
  store i64 1, ptr %subsaddr, align 8
  %subsaddr1 = getelementptr [10 x i64], ptr %arr, i32 0, i64 1
  store i64 2, ptr %subsaddr1, align 8
  %subsaddr2 = getelementptr [10 x i64], ptr %arr, i32 0, i64 2
  store i64 3, ptr %subsaddr2, align 8
  %sum = alloca i64, align 8
  %subsaddr3 = getelementptr [10 x i64], ptr %arr, i32 0, i64 0
  %substmp = load i64, ptr %subsaddr3, align 8
  %subsaddr4 = getelementptr [10 x i64], ptr %arr, i32 0, i64 1
  %substmp5 = load i64, ptr %subsaddr4, align 8
  %addtmp = add i64 %substmp, %substmp5
  %subsaddr6 = getelementptr [10 x i64], ptr %arr, i32 0, i64 2
  %substmp7 = load i64, ptr %subsaddr6, align 8
  %addtmp8 = add i64 %addtmp, %substmp7
  store i64 %addtmp8, ptr %sum, align 8
  %sum9 = load i64, ptr %sum, align 8
  ret i64 %sum9
}
