; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Point = type { i64, i64 }

define i64 @main() {
entry:
  %points = alloca [3 x %Point], align 8
  store [3 x %Point] zeroinitializer, ptr %points, align 8
  %subsaddr = getelementptr [3 x %Point], ptr %points, i32 0, i64 0
  %fieldaddr = getelementptr inbounds nuw %Point, ptr %subsaddr, i32 0, i32 0
  store i64 1, ptr %fieldaddr, align 8
  %subsaddr1 = getelementptr [3 x %Point], ptr %points, i32 0, i64 0
  %fieldaddr2 = getelementptr inbounds nuw %Point, ptr %subsaddr1, i32 0, i32 1
  store i64 2, ptr %fieldaddr2, align 8
  %subsaddr3 = getelementptr [3 x %Point], ptr %points, i32 0, i64 1
  %fieldaddr4 = getelementptr inbounds nuw %Point, ptr %subsaddr3, i32 0, i32 0
  store i64 3, ptr %fieldaddr4, align 8
  %subsaddr5 = getelementptr [3 x %Point], ptr %points, i32 0, i64 1
  %fieldaddr6 = getelementptr inbounds nuw %Point, ptr %subsaddr5, i32 0, i32 1
  store i64 4, ptr %fieldaddr6, align 8
  %subsaddr7 = getelementptr [3 x %Point], ptr %points, i32 0, i64 2
  %fieldaddr8 = getelementptr inbounds nuw %Point, ptr %subsaddr7, i32 0, i32 0
  store i64 5, ptr %fieldaddr8, align 8
  %subsaddr9 = getelementptr [3 x %Point], ptr %points, i32 0, i64 2
  %fieldaddr10 = getelementptr inbounds nuw %Point, ptr %subsaddr9, i32 0, i32 1
  store i64 6, ptr %fieldaddr10, align 8
  %sum = alloca i64, align 8
  %subsaddr11 = getelementptr [3 x %Point], ptr %points, i32 0, i64 0
  %fieldaddr12 = getelementptr inbounds nuw %Point, ptr %subsaddr11, i32 0, i32 0
  %fieldtmp = load i64, ptr %fieldaddr12, align 8
  %subsaddr13 = getelementptr [3 x %Point], ptr %points, i32 0, i64 0
  %fieldaddr14 = getelementptr inbounds nuw %Point, ptr %subsaddr13, i32 0, i32 1
  %fieldtmp15 = load i64, ptr %fieldaddr14, align 8
  %addtmp = add i64 %fieldtmp, %fieldtmp15
  %subsaddr16 = getelementptr [3 x %Point], ptr %points, i32 0, i64 1
  %fieldaddr17 = getelementptr inbounds nuw %Point, ptr %subsaddr16, i32 0, i32 0
  %fieldtmp18 = load i64, ptr %fieldaddr17, align 8
  %addtmp19 = add i64 %addtmp, %fieldtmp18
  store i64 %addtmp19, ptr %sum, align 8
  %sum20 = load i64, ptr %sum, align 8
  ret i64 %sum20
}
