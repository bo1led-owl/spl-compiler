const std = @import("std");
const Self = @This();

const lex = @import("lex.zig");
const Token = lex.Token;

pub const NodeList = std.MultiArrayList(Node);

nodes: NodeList.Slice,

/// heterogeneous list of out-of-band extra info
/// can, for example, store indices of statements in a block
extra_data: []u32,

pub const ExtraIndex = enum(u32) {
    _,

    pub fn toU32(self: ExtraIndex) u32 {
        return @backingInt(self);
    }
};

/// range of extra data, `end` is not included
pub const ExtraRange = struct { begin: ExtraIndex, len: u32 };

pub const Node = struct {
    pub const Index = enum(u32) {
        root = 0,
        _,

        pub fn toOptional(self: Node.Index) Node.OptIndex {
            std.debug.assert(@backingInt(self) != @backingInt(OptIndex.none));
            return @fromBackingInt(@backingInt(self));
        }

        pub fn toU32(self: Node.Index) u32 {
            return @backingInt(self);
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
        /// `data` is `extra_range`
        /// extras format: [(extern_decl|fn_decl)*]
        root,
        /// recovery node, put as a plug in case of parsing failure
        /// `token` is some token related to the error
        recovery,
        /// function prototype, namely `def FOO(a1, a2, ...)`
        /// `token` is either "extern" or "def"
        /// `data` is `extra_range`
        /// extras format: [arg*]
        ///
        /// extern functions are declared using this kind of node
        fn_proto,
        /// function declaration
        /// `token` is "def"
        /// `data` is `node_and_node`, pointing to `fn_proto` and function body
        fn_decl,
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
        /// `data` is `node_and_node`, lhs and rhs respectively
        binary,
        /// assignment statement
        /// follows the same rules as `binary`, but separated for ease of checking
        assign,
        /// call expression
        /// `token` is the opening '('
        /// data is `extra_range`
        /// extras format: [callee, arg*]
        call,
        /// block of statements
        /// `token` is the opening '{'
        /// `data` is `extra_range`
        /// extras format: [stmt*]
        block,
        /// else'less "if" statement
        /// `token` is "if"
        /// `data` is `node_and_node`, pointing to condition and body
        if_simple,
        /// "if" statement with "else"
        /// `token` is "if"
        /// `data` is `node_and_extra`, `node` is pointing to condition
        /// extras format: [body, else]
        if_full,
        /// while loop statement
        /// `token` is "while"
        /// `data` is `node_and_node`, pointing to condition and body
        @"while",
        /// "continue" statement
        /// `token` is "continue"
        @"continue",
        /// "break" statement
        /// `token` is "break"
        @"break",
    };

    pub const Data = union {
        node: Node.Index,
        node_and_node: struct { Node.Index, Node.Index },
        node_and_extra: struct { Node.Index, ExtraIndex },
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
    return self.extra_data[range.begin.toU32()..][0..range.len];
}

pub fn nodeKind(self: Self, index: Node.Index) Node.Kind {
    return self.nodes.items(.kind)[index.toU32()];
}

pub fn nodeToken(self: Self, index: Node.Index) Token.Index {
    return self.nodes.items(.token)[index.toU32()];
}

pub fn nodeData(self: Self, index: Node.Index) Node.Data {
    return self.nodes.items(.data)[index.toU32()];
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

    pub const FnProto = struct {
        // to be extended with return type and argument types
        is_extern: bool,
        name_token: Token.Index,
        params: []Token.Index,
    };

    pub const Call = struct {
        callee: Node.Index,
        args: []Node.Index,
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
            else => unreachable,
        };
    }

    pub fn ifSimple(ast: Self, node_index: Node.Index) info.If {
        std.debug.assert(ast.nodeKind(node_index) == .if_simple);

        const cond, const then_node = ast.nodeData(node_index).node_and_node;
        return .{ .cond = cond, .then_node = then_node, .else_node = .none };
    }

    pub fn ifFull(ast: Self, node_index: Node.Index) info.If {
        std.debug.assert(ast.nodeKind(node_index) == .if_full);

        const cond, const extra_index = ast.nodeData(node_index).node_and_extra;
        const then_node: Node.Index = @fromBackingInt(ast.extra_data[extra_index.toU32()]);
        const else_node: Node.Index = @fromBackingInt(ast.extra_data[extra_index.toU32() + 1]);
        return .{ .cond = cond, .then_node = then_node, .else_node = else_node.toOptional() };
    }

    pub fn fnProto(ast: Self, tokens: lex.TokenList.Slice, node_index: Node.Index) info.FnProto {
        std.debug.assert(ast.nodeKind(node_index) == .fn_proto);

        const token_index = ast.nodeToken(node_index);
        const is_extern = tokens.items(.kind)[token_index] == .kw_extern;
        const name_token = if (is_extern) token_index + 2 else token_index + 1;

        const params = ast.extractExtras(ast.nodeData(node_index).extra_range);
        return .{ .is_extern = is_extern, .name_token = name_token, .params = params };
    }

    pub fn call(ast: Self, node_index: Node.Index) info.Call {
        std.debug.assert(ast.nodeKind(node_index) == .call);

        const data: []Node.Index = @ptrCast(ast.extractExtras(ast.nodeData(node_index).extra_range));
        return .{ .callee = data[0], .args = data[1..] };
    }
};
