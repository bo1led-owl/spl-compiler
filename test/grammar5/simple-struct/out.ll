; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Point = type { i64, i64 }

define i64 @main() {
entry:
  %p = alloca %Point, align 8
  store %Point zeroinitializer, ptr %p, align 8
  %fieldaddr = getelementptr inbounds nuw %Point, ptr %p, i32 0, i32 0
  store i64 10, ptr %fieldaddr, align 8
  %fieldaddr1 = getelementptr inbounds nuw %Point, ptr %p, i32 0, i32 1
  store i64 20, ptr %fieldaddr1, align 8
  %sum = alloca i64, align 8
  %fieldaddr2 = getelementptr inbounds nuw %Point, ptr %p, i32 0, i32 0
  %fieldtmp = load i64, ptr %fieldaddr2, align 8
  %fieldaddr3 = getelementptr inbounds nuw %Point, ptr %p, i32 0, i32 1
  %fieldtmp4 = load i64, ptr %fieldaddr3, align 8
  %addtmp = add i64 %fieldtmp, %fieldtmp4
  store i64 %addtmp, ptr %sum, align 8
  %sum5 = load i64, ptr %sum, align 8
  ret i64 %sum5
}
