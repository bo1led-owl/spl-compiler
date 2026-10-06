; ModuleID = 'spl'
source_filename = "spl"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i64 @bar() {
entry:
  ret i64 1
}

define i64 @foo() {
entry:
  %calltmp = call i64 @bar()
  ret i64 %calltmp
}

define i64 @main() {
entry:
  %calltmp = call i64 @foo()
  ret i64 %calltmp
}
