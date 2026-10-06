; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Point = type { i64, i64 }

declare void @println_int(i64)

define i64 @bar() {
entry:
  ret i64 42
}

declare void @putchar(i8)

define i64 @baz(%Point %0) {
entry:
  %p = alloca %Point, align 8
  store %Point %0, ptr %p, align 8
  %fieldaddr = getelementptr inbounds nuw %Point, ptr %p, i32 0, i32 0
  %fieldtmp = load i64, ptr %fieldaddr, align 8
  %fieldaddr1 = getelementptr inbounds nuw %Point, ptr %p, i32 0, i32 1
  %fieldtmp2 = load i64, ptr %fieldaddr1, align 8
  %addtmp = add i64 %fieldtmp, %fieldtmp2
  ret i64 %addtmp
}

define %Point @makePoint(i64 %0, i64 %1) {
entry:
  %px = alloca i64, align 8
  store i64 %0, ptr %px, align 8
  %py = alloca i64, align 8
  store i64 %1, ptr %py, align 8
  %p = alloca %Point, align 8
  store %Point zeroinitializer, ptr %p, align 8
  %fieldaddr = getelementptr inbounds nuw %Point, ptr %p, i32 0, i32 0
  %px1 = load i64, ptr %px, align 8
  store i64 %px1, ptr %fieldaddr, align 8
  %fieldaddr2 = getelementptr inbounds nuw %Point, ptr %p, i32 0, i32 1
  %py3 = load i64, ptr %py, align 8
  store i64 %py3, ptr %fieldaddr2, align 8
  %p4 = load %Point, ptr %p, align 8
  ret %Point %p4
}

define i64 @main() {
entry:
  call void @putchar(i8 66)
  call void @putchar(i8 10)
  %calltmp = call %Point @makePoint(i64 4, i64 5)
  %calltmp1 = call i64 @baz(%Point %calltmp)
  call void @println_int(i64 %calltmp1)
  %calltmp2 = call i64 @bar()
  ret i64 %calltmp2
}
