pub const Kind = enum {
    number,
    ident,
    kw_val,
    kw_var,
    kw_return,
    semi,
    assign,
    plus,
    minus,
    asterisk,
    slash,
    lparen,
    rparen,
};

kind: Kind,
offset: u32,
