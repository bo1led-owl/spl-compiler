; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @main() {
entry:
  %a = alloca i64, align 8
  store i64 1, ptr %a, align 8
  %b = alloca i64, align 8
  store i64 0, ptr %b, align 8
  %c = alloca i64, align 8
  %a1 = load i64, ptr %a, align 8
  %b2 = load i64, ptr %b, align 8
  %lbool = icmp ne i64 %a1, 0
  %rbool = icmp ne i64 %b2, 0
  %andtmp = and i1 %lbool, %rbool
  %andext = zext i1 %andtmp to i64
  %a3 = load i64, ptr %a, align 8
  %nottmp = icmp eq i64 %a3, 0
  %notext = zext i1 %nottmp to i64
  %lbool4 = icmp ne i64 %andext, 0
  %rbool5 = icmp ne i64 %notext, 0
  %ortmp = or i1 %lbool4, %rbool5
  %orext = zext i1 %ortmp to i64
  store i64 %orext, ptr %c, align 8
  ret i64 0
}
