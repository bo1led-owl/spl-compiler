; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Point = type { i64, i64 }

define i64 @dotProduct(%Point %0, %Point %1) {
entry:
  %a = alloca %Point, align 8
  store %Point %0, ptr %a, align 8
  %b = alloca %Point, align 8
  store %Point %1, ptr %b, align 8
  %fieldaddr = getelementptr inbounds nuw %Point, ptr %a, i32 0, i32 0
  %fieldtmp = load i64, ptr %fieldaddr, align 8
  %fieldaddr1 = getelementptr inbounds nuw %Point, ptr %b, i32 0, i32 0
  %fieldtmp2 = load i64, ptr %fieldaddr1, align 8
  %multmp = mul i64 %fieldtmp, %fieldtmp2
  %fieldaddr3 = getelementptr inbounds nuw %Point, ptr %a, i32 0, i32 1
  %fieldtmp4 = load i64, ptr %fieldaddr3, align 8
  %fieldaddr5 = getelementptr inbounds nuw %Point, ptr %b, i32 0, i32 1
  %fieldtmp6 = load i64, ptr %fieldaddr5, align 8
  %multmp7 = mul i64 %fieldtmp4, %fieldtmp6
  %addtmp = add i64 %multmp, %multmp7
  ret i64 %addtmp
}

define i64 @main() {
entry:
  %p1 = alloca %Point, align 8
  store %Point zeroinitializer, ptr %p1, align 8
  %p2 = alloca %Point, align 8
  store %Point zeroinitializer, ptr %p2, align 8
  %fieldaddr = getelementptr inbounds nuw %Point, ptr %p1, i32 0, i32 0
  store i64 1, ptr %fieldaddr, align 8
  %fieldaddr1 = getelementptr inbounds nuw %Point, ptr %p1, i32 0, i32 1
  store i64 2, ptr %fieldaddr1, align 8
  %fieldaddr2 = getelementptr inbounds nuw %Point, ptr %p2, i32 0, i32 0
  store i64 3, ptr %fieldaddr2, align 8
  %fieldaddr3 = getelementptr inbounds nuw %Point, ptr %p2, i32 0, i32 1
  store i64 4, ptr %fieldaddr3, align 8
  %result = alloca i64, align 8
  %p14 = load %Point, ptr %p1, align 8
  %p25 = load %Point, ptr %p2, align 8
  %calltmp = call i64 @dotProduct(%Point %p14, %Point %p25)
  store i64 %calltmp, ptr %result, align 8
  %result6 = load i64, ptr %result, align 8
  ret i64 %result6
}
