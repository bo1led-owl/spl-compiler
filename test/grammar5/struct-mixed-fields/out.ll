; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%Mixed = type { i8, i16, i32, i64, i1, ptr }

@.str.0 = private constant [3 x i8] c"hi\00"

define i64 @main() {
entry:
  %m = alloca %Mixed, align 8
  store %Mixed zeroinitializer, ptr %m, align 8
  %fieldaddr = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 0
  store i8 1, ptr %fieldaddr, align 1
  %fieldaddr1 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 1
  store i16 2, ptr %fieldaddr1, align 2
  %fieldaddr2 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 2
  store i32 3, ptr %fieldaddr2, align 4
  %fieldaddr3 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 3
  store i64 4, ptr %fieldaddr3, align 8
  %fieldaddr4 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 4
  store i1 true, ptr %fieldaddr4, align 1
  %fieldaddr5 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 5
  store ptr @.str.0, ptr %fieldaddr5, align 8
  %result = alloca i64, align 8
  store i64 0, ptr %result, align 8
  %fieldaddr6 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 0
  %fieldtmp = load i8, ptr %fieldaddr6, align 1
  %sexttmp = sext i8 %fieldtmp to i64
  %fieldaddr7 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 1
  %fieldtmp8 = load i16, ptr %fieldaddr7, align 2
  %sexttmp9 = sext i16 %fieldtmp8 to i64
  %addtmp = add i64 %sexttmp, %sexttmp9
  %fieldaddr10 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 2
  %fieldtmp11 = load i32, ptr %fieldaddr10, align 4
  %sexttmp12 = sext i32 %fieldtmp11 to i64
  %addtmp13 = add i64 %addtmp, %sexttmp12
  %fieldaddr14 = getelementptr inbounds nuw %Mixed, ptr %m, i32 0, i32 3
  %fieldtmp15 = load i64, ptr %fieldaddr14, align 8
  %addtmp16 = add i64 %addtmp13, %fieldtmp15
  store i64 %addtmp16, ptr %result, align 8
  %result17 = load i64, ptr %result, align 8
  ret i64 %result17
}
