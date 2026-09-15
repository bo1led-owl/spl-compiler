; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Outer = type { %Inner, i64 }
%Inner = type { i64 }

define i64 @main() {
entry:
  %o = alloca %Outer, align 8
  store %Outer zeroinitializer, ptr %o, align 8
  %fieldaddr = getelementptr inbounds nuw %Outer, ptr %o, i32 0, i32 0
  %fieldaddr1 = getelementptr inbounds nuw %Inner, ptr %fieldaddr, i32 0, i32 0
  store i64 42, ptr %fieldaddr1, align 8
  %fieldaddr2 = getelementptr inbounds nuw %Outer, ptr %o, i32 0, i32 1
  store i64 7, ptr %fieldaddr2, align 8
  %fieldaddr3 = getelementptr inbounds nuw %Outer, ptr %o, i32 0, i32 0
  %fieldaddr4 = getelementptr inbounds nuw %Inner, ptr %fieldaddr3, i32 0, i32 0
  %fieldtmp = load i64, ptr %fieldaddr4, align 8
  %fieldaddr5 = getelementptr inbounds nuw %Outer, ptr %o, i32 0, i32 1
  %fieldtmp6 = load i64, ptr %fieldaddr5, align 8
  %addtmp = add i64 %fieldtmp, %fieldtmp6
  ret i64 %addtmp
}
