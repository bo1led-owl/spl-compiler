const std = @import("std");

pub const TokenIndex = u32;
const NodeList = std.MultiArrayList(Node);

pub const Node = struct {
    pub const Index = u32;
    pub const OptIndex = ?u32;
    pub const Range = struct { begin: Index, end: Index };

    // kind of a terrifiyng layout at first, but really it's just an attempt to pack
    // everything as closely as possible to minimize memory footprint

    kind: Kind,
    token: TokenIndex,

    /// a generalized union used based on the `kind` of the node
    data: Data = undefined,

    pub const Kind = enum {
        /// variable declaration
        /// `token` is `var` or `val` to check mutability
        /// `data` is `node_node`,
        /// the first one is the name, the second one is the initialization expression
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
        /// `data` is `opt_node`, pointing to the optional return value
        @"return",
        /// unary operations
        /// `token` is the op
        /// `data` is `node`, pointing to the operand
        negate,
        /// binary operations
        /// `token` is the op
        /// `data` is `node_node`, lhs and rhs respectively
        add,
        sub,
        mul,
        div,
        /// assignment
        /// `token` is `=`
        /// `data` is `node_node`,
        /// the first one is the destination, the second one is the source
        assign,
    };

    pub const Data = union {
        node: Index,
        node_node: struct { Index, Index },
        opt_node: OptIndex,
    };
};
