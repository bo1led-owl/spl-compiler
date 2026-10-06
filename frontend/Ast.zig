const std = @import("std");
const Self = @This();

const Token = @import("lex.zig").Token;

pub const NodeList = std.MultiArrayList(Node);

nodes: NodeList,

/// heterogeneous list of out-of-band extra info
/// can, for example, store indices of statements in a block
extra_data: []u32,

/// range of extra data, `end` is not included
pub const ExtraIndex = enum(u32) { _ };

/// range of extra data, `end` is not included
pub const ExtraRange = struct { begin: ExtraIndex, end: ExtraIndex };

pub const Node = struct {
    pub const Index = enum(u32) {
        root = 0,
        _,

        pub fn toOptional(self: Node.Index) Node.OptIndex {
            std.debug.assert(@backingInt(self) != @backingInt(OptIndex.none));
            return @fromBackingInt(@backingInt(self));
        }
    };

    pub const OptIndex = enum(u32) {
        root = 0,
        none = std.math.maxInt(u32),
        _,

        pub fn toIndex(self: Node.OptIndex) ?Node.Index {
            if (self == .none) return null;
            return @fromBackingInt(@backingInt(self));
        }
    };

    // kind of a terrifiyng layout at first, but really it's just an attempt to pack
    // everything as closely as possible to minimize memory footprint

    kind: Kind,
    token: Token.Index,

    /// a generalized union used based on the `kind` of the node
    data: Data = undefined,

    pub const Kind = enum {
        /// root node of the AST
        /// `token` is the first token in the file
        /// `data` is `extra_range`, where a slice of extra data contains indices of statements
        root,
        /// recovery node, put as a plug in case of parsing failure
        /// `token` is some token related to the error
        recovery,
        /// variable declaration
        /// `token` is "var" or "val" to check mutability
        /// `data` is `node`, pointing to the initialization expression
        var_decl,
        /// reference to some kind of entity by its name
        /// `token` is the name
        /// `data` is not used
        name_ref,
        /// boolean literal
        /// `token` is "true" or "false"
        bool_literal,
        /// integer literal
        /// `token` is the number token
        /// `data` is not used
        number,
        /// return statement
        /// `token` is "return"
        /// `data` is `node`, pointing to the return value
        @"return",
        /// unary operations
        /// `token` is the op
        /// `data` is `node`, pointing to the operand
        unary,
        /// binary operations
        /// `token` is the op
        /// `data` is `node_node`, lhs and rhs respectively
        binary,
        /// assignment statement
        /// follows the same rules as `binary`, but separated for ease of checking
        assign,
        /// block of statements
        /// `token` is the opening '{'
        /// `data` is `extra_range`, containing indices of statements inside
        block,
        /// else'less "if" statement
        /// `token` is "if"
        /// `data` is `node_node`, pointing to condition and body
        if_simple,
        /// "if" statement with "else"
        /// `token` is "if"
        /// `data` is `node_extra`,
        /// `node` pointing to condition and `extra` to [body_index, else_index] in extras
        if_full,
        /// while loop statement
        /// `token` is "while"
        /// `data` is `node_node`, pointing to condition and body
        @"while",
        /// "continue" statement
        /// `token` is "continue"
        @"continue",
        /// "break" statement
        /// `token` is "break"
        @"break",
    };

    pub const Data = union {
        node: Index,
        node_node: struct { Node.Index, Node.Index },
        node_extra: struct { Node.Index, ExtraIndex },
        extra_range: ExtraRange,

        // reserved for the future
        opt_node: OptIndex,
    };
};

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.nodes.deinit(gpa);
    gpa.free(self.extra_data);
    self.* = undefined;
}

pub fn extractExtras(self: Self, range: ExtraRange) []u32 {
    return self.extra_data[@backingInt(range.begin)..@backingInt(range.end)];
}

pub fn nodeKind(self: Self, index: Node.Index) Node.Kind {
    return self.nodes.items(.kind)[@backingInt(index)];
}

pub fn nodeToken(self: Self, index: Node.Index) Token.Index {
    return self.nodes.items(.token)[@backingInt(index)];
}

pub fn nodeData(self: Self, index: Node.Index) Node.Data {
    return self.nodes.items(.data)[@backingInt(index)];
}

pub const info = struct {
    pub const VarDecl = struct {
        mutability_token: Token.Index,
        name_token: Token.Index,
        init_expr: Node.Index,
    };

    pub const If = struct {
        cond: Node.Index,
        then_node: Node.Index,
        else_node: Node.OptIndex,
    };

    pub fn varDecl(ast: Self, node_index: Node.Index) info.VarDecl {
        std.debug.assert(ast.nodeKind(node_index) == .var_decl);

        const main_token = ast.nodeToken(node_index);
        return .{
            .mutability_token = main_token,
            .name_token = main_token + 1,
            .init_expr = ast.nodeData(node_index).node,
        };
    }

    pub fn ifAny(ast: Self, node_index: Node.Index) info.If {
        return switch (ast.nodeKind(node_index)) {
            .if_simple => ifSimple(ast, node_index),
            .if_full => ifFull(ast, node_index),
            else => @panic("`if_simple` of `if_full` expected"),
        };
    }

    pub fn ifSimple(ast: Self, node_index: Node.Index) info.If {
        std.debug.assert(ast.nodeKind(node_index) == .if_simple);

        const cond, const then_node = ast.nodeData(node_index).node_node;
        return .{ .cond = cond, .then_node = then_node, .else_node = .none };
    }

    pub fn ifFull(ast: Self, node_index: Node.Index) info.If {
        std.debug.assert(ast.nodeKind(node_index) == .if_full);

        const cond, const extra_index = ast.nodeData(node_index).node_extra;
        const then_node: Node.Index = @fromBackingInt(ast.extra_data[@backingInt(extra_index)]);
        const else_node: Node.Index = @fromBackingInt(ast.extra_data[@backingInt(extra_index) + 1]);
        return .{ .cond = cond, .then_node = then_node, .else_node = else_node.toOptional() };
    }
};
