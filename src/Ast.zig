const std = @import("std");

const Self = @This();

pub const TokenIndex = u32;
pub const NodeList = std.MultiArrayList(Node);

nodes: NodeList,

/// heterogeneous list of out-of-band extra info
/// can, for example, store indices of statements in a block
extra_data: []u32,

pub const Node = struct {
    pub const Index = enum(u32) {
        root = 0,
        _,
    };

    pub const OptIndex = enum(u32) {
        root = 0,
        none = std.math.maxInt(u32),
        _,
    };

    /// range of extra data, `end` is not included
    pub const ExtraRange = struct { begin: u32, end: u32 };

    // kind of a terrifiyng layout at first, but really it's just an attempt to pack
    // everything as closely as possible to minimize memory footprint

    kind: Kind,
    token: TokenIndex,

    /// a generalized union used based on the `kind` of the node
    data: Data = undefined,

    pub const Kind = enum {
        /// root node, currently just a block of statements, later will point to all top-level declarations
        /// `token` is the first token in the file
        /// `data` is `extra_range`, where a slice of extra data contains indices of statements
        root,
        /// variable declaration
        /// `token` is `var` or `val` to check mutability
        /// `data` is `node_node`, the first one is the name, the second one is the initialization expression
        var_decl,
        /// reference to some kind of entity by its name
        /// `token` is the name
        /// `data` is not used
        name_ref,
        /// integer literal
        /// `token` is the number token
        /// `data` is not used
        number,
        /// return statement
        /// `token` is `return`
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
    };

    pub const Data = union {
        node: Index,
        node_node: struct { Index, Index },
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

pub fn extractExtras(self: Self, range: Node.ExtraRange) []u32 {
    return self.extra_data[range.begin..range.end];
}
