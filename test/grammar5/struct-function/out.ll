; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Point = type { i64, i64 }

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
  %pt = alloca %Point, align 8
  store %Point zeroinitializer, ptr %pt, align 8
  %calltmp = call %Point @makePoint(i64 3, i64 4)
  %copy_tmp = alloca %Point, align 8
  store %Point %calltmp, ptr %copy_tmp, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %pt, ptr align 1 %copy_tmp, i64 ptrtoint (ptr getelementptr (%Point, ptr null, i32 1) to i64), i1 false)
  %result = alloca i64, align 8
  %fieldaddr = getelementptr inbounds nuw %Point, ptr %pt, i32 0, i32 0
  %fieldtmp = load i64, ptr %fieldaddr, align 8
  %fieldaddr1 = getelementptr inbounds nuw %Point, ptr %pt, i32 0, i32 1
  %fieldtmp2 = load i64, ptr %fieldaddr1, align 8
  %addtmp = add i64 %fieldtmp, %fieldtmp2
  store i64 %addtmp, ptr %result, align 8
  %result3 = load i64, ptr %result, align 8
  ret i64 %result3
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #0

attributes #0 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
