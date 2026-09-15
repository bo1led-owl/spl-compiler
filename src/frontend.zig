pub const lex = @import("frontend/lex.zig");
pub const Lexer = lex.Lexer;
pub const ErrorBundle = @import("frontend/ErrorBundle.zig");
pub const Ast = @import("frontend/Ast.zig");
pub const Parser = @import("frontend/Parser.zig");
pub const Sema = @import("frontend/Sema.zig");
pub const Source = @import("frontend/Source.zig");

test {
    _ = lex;
    _ = Source;
    _ = ErrorBundle;
    _ = Ast;
    _ = Parser;
    _ = Sema;
}
