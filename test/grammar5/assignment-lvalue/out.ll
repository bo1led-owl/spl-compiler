; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Pair = type { i64, i64 }

define i64 @main() {
entry:
  %p = alloca %Pair, align 8
  store %Pair zeroinitializer, ptr %p, align 8
  %arr = alloca [4 x i64], align 8
  store [4 x i64] zeroinitializer, ptr %arr, align 8
  %fieldaddr = getelementptr inbounds nuw %Pair, ptr %p, i32 0, i32 0
  store i64 10, ptr %fieldaddr, align 8
  %fieldaddr1 = getelementptr inbounds nuw %Pair, ptr %p, i32 0, i32 1
  store i64 20, ptr %fieldaddr1, align 8
  %subsaddr = getelementptr [4 x i64], ptr %arr, i32 0, i64 0
  %fieldaddr2 = getelementptr inbounds nuw %Pair, ptr %p, i32 0, i32 0
  %fieldtmp = load i64, ptr %fieldaddr2, align 8
  store i64 %fieldtmp, ptr %subsaddr, align 8
  %subsaddr3 = getelementptr [4 x i64], ptr %arr, i32 0, i64 1
  %fieldaddr4 = getelementptr inbounds nuw %Pair, ptr %p, i32 0, i32 1
  %fieldtmp5 = load i64, ptr %fieldaddr4, align 8
  store i64 %fieldtmp5, ptr %subsaddr3, align 8
  %fieldaddr6 = getelementptr inbounds nuw %Pair, ptr %p, i32 0, i32 0
  %subsaddr7 = getelementptr [4 x i64], ptr %arr, i32 0, i64 0
  %substmp = load i64, ptr %subsaddr7, align 8
  %subsaddr8 = getelementptr [4 x i64], ptr %arr, i32 0, i64 1
  %substmp9 = load i64, ptr %subsaddr8, align 8
  %addtmp = add i64 %substmp, %substmp9
  store i64 %addtmp, ptr %fieldaddr6, align 8
  %fieldaddr10 = getelementptr inbounds nuw %Pair, ptr %p, i32 0, i32 0
  %fieldtmp11 = load i64, ptr %fieldaddr10, align 8
  ret i64 %fieldtmp11
}
