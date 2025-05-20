const std = @import("std");
const math = std.math;
const heap = std.heap;
const mem = std.mem;
const os = std.os;
const debug = std.debug;
const unicode = std.unicode;
const ascii = std.ascii;

pub const RegexMatchConfig = struct {
    const MatchMode = enum { exact, substring };
    const CaseMode = enum { exact, ignore };

    mode: MatchMode = .exact,
    case: CaseMode = .exact,
};

pub const RegexTypeConfig = struct {
    state_bits: u8 = 64,
};

pub fn Regex(comptime cfg: RegexTypeConfig) type {
    const RU = RegexUnmanaged(cfg);
    return struct {
        const Self = @This();

        alloc: mem.Allocator,
        r: RU,

        pub fn compile(a: mem.Allocator, rex: []const u8) !Self {
            return .{
                .alloc = a,
                .r = try RU.compile(a, rex),
            };
        }

        pub fn deinit(self: Self) void {
            self.r.deinit(self.alloc);
        }

        pub fn match(self: Self, c: RegexMatchConfig, str: []const u8) bool {
            return self.r.match(c, str);
        }

        pub fn dumpDot(self: Self, writer: anytype) !void {
            try self.r.dumpDot(writer);
        }
    };
}

pub fn RegexUnmanaged(comptime cfg: RegexTypeConfig) type {
    if (cfg.state_bits <= 2) @compileError("At least 3 bits are required.");
    // Integer type that encodes states as a bitfield.
    const T = @Type(.{ .int = .{ .bits = cfg.state_bits, .signedness = .unsigned } });
    return struct {
        const Self = @This();

        /// The first bit is hardcoded as the start/entry state. The last
        /// state is hardcoded as the final/exit state.
        const start_state = 1;
        const end_state = 1 << (cfg.state_bits - 1);
        const empty_state = 0;

        /// Rules. Behold: Two possible values for when are reserved: 0
        /// is for always actionable rules and 1 is for matching any one
        /// literal except for newlines.
        from: []T,
        to: []T,
        when: []u8,

        pub fn compile(a: mem.Allocator, rex: []const u8) !Self {
            var cmp = try Compiler(T).new(a);
            defer cmp.deinit(a);

            var it = Tokenizer.from(rex);
            while (try it.next()) |token| {
                switch (token) {
                    .literal => |l| try cmp.addLiteral(a, l),
                    .multibyte_literal => |l| try cmp.addMultiByteLiteral(a, l),
                    .literal_array => |ar| try cmp.addLiteralArray(a, ar),
                    .modifier => |m| try cmp.addModifier(a, m),
                    .@"or" => try cmp.addOr(a),
                    .open_block => try cmp.openSubblock(a),
                    .close_block => try cmp.closeSubblock(a),
                }
            }

            const rules_owned = try cmp.getOwned(a);
            return .{
                .from = rules_owned.from,
                .to = rules_owned.to,
                .when = rules_owned.when,
            };
        }

        pub fn deinit(self: Self, a: mem.Allocator) void {
            a.free(self.from);
            a.free(self.to);
            a.free(self.when);
        }

        pub fn match(self: Self, c: RegexMatchConfig, str: []const u8) bool {
            var states = self.applyAlwaysActionableRules(c, start_state, str.len == 0) orelse return true;
            var skip: usize = 0;
            for (str, 0..) |ch, index| {
                if (skip > 0) {
                    skip -= 1;
                    continue;
                }
                const reached_end = index == str.len - 1;
                states = self.applyRules(c, states, ch, reached_end, &skip) orelse return true;
                if (c.mode == .substring) states |= start_state;
                states = self.applyAlwaysActionableRules(c, states, reached_end) orelse return true;
                if (c.mode == .exact and states == empty_state) return false;
            }
            return false;
        }

        /// Helper for match(). Applies rules, except for always actionable
        /// rules. Returns null if end_state is reached.
        fn applyRules(self: Self, c: RegexMatchConfig, current: T, _ch: u8, reached_end: bool, skip: *usize) ?T {
            debug.assert(skip.* == 0);
            const ch = if (c.case == .ignore and ascii.isAlphabetic(_ch)) ascii.toLower(_ch) else _ch;
            var states: T = empty_state;
            for (self.from, self.to, self.when) |f, t, _w| {
                const w = if (c.case == .ignore and ascii.isAlphabetic(_w)) ascii.toLower(_w) else _w;
                if ((w == ch or (w == 1 and ch != '\n')) and (f & current) > 0) {
                    states |= t;

                    // If we encounter the end state we may only return null
                    // if we either do not care whether the rest of the string
                    // matches the rules (meaning we are _not_ in exact matching mode)
                    // or when we have reached the end of the input string.
                    if ((states & end_state) > 0 and (c.mode == .substring or reached_end)) {
                        return null;
                    }

                    // Make . selector correctly skip multi-byte codepoints.
                    if (w == 1) {
                        const bytelen = unicode.utf8ByteSequenceLength(ch) catch 1;
                        skip.* = bytelen - 1;
                    }
                }
            }
            return states;
        }

        /// Helper for match().  Applies always actionable rules, which act
        /// "immediately". Returns null if end_state is reached.
        fn applyAlwaysActionableRules(self: Self, c: RegexMatchConfig, current: T, reached_end: bool) ?T {
            var states: T = current;
            var check_again: bool = true;
            while (check_again) {
                for (self.from, self.to, self.when) |f, t, w| {
                    // Is rule always actionable, matches our state and has
                    // not been applied yet?
                    if (w == 0 and (f & states) > 0 and (t & states) == 0) {
                        states |= t;
                        check_again = true;

                        // If we have encountered the end state, we may return
                        // null only if we are not in exact match mode and as such
                        // do not care whether the rest of the string matches,
                        // or if we have reached the end of the string.
                        if ((states & end_state) > 0 and
                            (c.mode == .substring or reached_end))
                        {
                            return null;
                        }
                    } else {
                        check_again = false;
                    }
                }
            }
            return states;
        }

        pub fn dumpDot(self: Self, writer: anytype) !void {
            try writer.writeAll("digraph exre {\n");
            for (self.from, self.to, self.when) |f, t, w| {
                try writer.writeByte('\t');
                try writeDotStateName(writer, f);
                try writer.writeAll(" -> ");
                try writeDotStateName(writer, t);
                switch (w) {
                    0 => try writer.writeByte('\n'),
                    1 => try writer.writeAll(" [label=\".\"]\n"),
                    else => {
                        if (ascii.isAlphanumeric(w)) {
                            try writer.print(" [label=\"{c}\"]\n", .{w});
                        } else {
                            try writer.print(" [label=\"0x{X}\"]\n", .{w});
                        }
                    },
                }
            }
            try writer.writeAll("}\n");
        }

        fn writeDotStateName(writer: anytype, s: T) !void {
            if (s == start_state) {
                try writer.writeAll("start");
            } else if (s == end_state) {
                try writer.writeAll("end");
            } else {
                var i: u8 = 0;
                var y: T = s;
                while (y > 0) : (i += 1) {
                    y >>= 1;
                }
                try writer.print("s{}", .{i - 1});
            }
        }
    };
}

test "Regex" {
    const testing = std.testing;
    {
        var r = try Regex(.{}).compile(testing.allocator, "ab");
        defer r.deinit();
        try testing.expect(r.match(.{}, "ab"));
        try testing.expect(!r.match(.{}, "abab"));
        try testing.expect(!r.match(.{}, " ab "));
        try testing.expect(!r.match(.{}, "cccabccc"));
        try testing.expect(r.match(.{ .mode = .substring }, "ab"));
        try testing.expect(r.match(.{ .mode = .substring }, "abab"));
        try testing.expect(r.match(.{ .mode = .substring }, "ccccabccc"));
        try testing.expect(!r.match(.{ .mode = .substring }, "ccccccc"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "ab?");
        defer r.deinit();
        try testing.expect(r.match(.{}, "ab"));
        try testing.expect(r.match(.{}, "a"));
        try testing.expect(!r.match(.{}, "abb"));
        try testing.expect(!r.match(.{}, "aab"));
        try testing.expect(r.match(.{ .mode = .substring }, "ab"));
        try testing.expect(r.match(.{ .mode = .substring }, "abbb"));
        try testing.expect(r.match(.{ .mode = .substring }, "aaaaabbb"));
        try testing.expect(r.match(.{ .mode = .substring }, "aaaaab"));
        try testing.expect(r.match(.{ .mode = .substring }, "aaaaa"));
        try testing.expect(!r.match(.{ .mode = .substring }, "bbbbb"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "ab+c");
        defer r.deinit();
        try testing.expect(r.match(.{}, "abc"));
        try testing.expect(r.match(.{}, "abbbbc"));
        try testing.expect(r.match(.{}, "abbc"));
        try testing.expect(r.match(.{}, "abbbbbbbbbbbbbbbbbbbbbc"));
        try testing.expect(!r.match(.{}, "abbbbbbbbbbbbbbvbbbbbbbc"));
        try testing.expect(!r.match(.{}, "ac"));
        try testing.expect(!r.match(.{ .mode = .substring }, "ac"));
        try testing.expect(r.match(.{ .mode = .substring }, "cccccccabccc"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "ab*c");
        defer r.deinit();
        try testing.expect(r.match(.{}, "ac"));
        try testing.expect(r.match(.{}, "abc"));
        try testing.expect(r.match(.{}, "abbbbc"));
        try testing.expect(r.match(.{}, "abbc"));
        try testing.expect(r.match(.{}, "abbbbbbbbbbbbbbbbbbbbbc"));
        try testing.expect(!r.match(.{}, "abbbbbbbbbbbbbbvbbbbbbbc"));
        try testing.expect(r.match(.{ .mode = .substring }, "cccccccabccc"));
        try testing.expect(r.match(.{ .mode = .substring }, "cccccccaccc"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a(b)c");
        defer r.deinit();
        try testing.expect(r.match(.{}, "abc"));
        try testing.expect(!r.match(.{}, "abbc"));
        try testing.expect(r.match(.{ .mode = .substring }, "cccccccabccc"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a|b");
        defer r.deinit();
        try testing.expect(r.match(.{}, "a"));
        try testing.expect(r.match(.{}, "b"));
        try testing.expect(!r.match(.{}, "ab"));
        try testing.expect(!r.match(.{}, "a|b"));
        try testing.expect(r.match(.{ .mode = .substring }, "aabbbbb"));
        try testing.expect(r.match(.{ .mode = .substring }, "aaaaaaa"));
        try testing.expect(r.match(.{ .mode = .substring }, "bbbbbbb"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a(b|c)d");
        defer r.deinit();
        try testing.expect(r.match(.{}, "abd"));
        try testing.expect(r.match(.{}, "acd"));
        try testing.expect(r.match(.{ .mode = .substring }, "vvacdvvv"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a(b|c)?");
        defer r.deinit();
        try testing.expect(r.match(.{}, "ab"));
        try testing.expect(r.match(.{}, "ac"));
        try testing.expect(r.match(.{}, "a"));
        try testing.expect(r.match(.{ .mode = .substring }, "vvacvvv"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a.");
        defer r.deinit();
        try testing.expect(r.match(.{}, "ab"));
        try testing.expect(r.match(.{}, "ac"));
        try testing.expect(!r.match(.{}, "a"));
        try testing.expect(r.match(.{ .mode = .substring }, "vvavvv"));
        try testing.expect(!r.match(.{ .mode = .substring }, "vva"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "aä");
        defer r.deinit();
        try testing.expect(r.match(.{}, "aä"));
        try testing.expect(r.match(.{ .mode = .substring }, "aaäaaa"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "aµ?");
        defer r.deinit();
        try testing.expect(r.match(.{}, "a"));
        try testing.expect(r.match(.{}, "aµ"));
        try testing.expect(!r.match(.{}, "aµµ"));
        try testing.expect(r.match(.{ .mode = .substring }, "aaµaaa"));
        try testing.expect(r.match(.{ .mode = .substring }, "aaaaa"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "aµ+");
        defer r.deinit();
        try testing.expect(!r.match(.{}, "a"));
        try testing.expect(r.match(.{}, "aµµµµµµµ"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "aµ*");
        defer r.deinit();
        try testing.expect(r.match(.{}, "a"));
        try testing.expect(r.match(.{}, "aµµµµµµµ"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a[bc]");
        defer r.deinit();
        try testing.expect(r.match(.{}, "ab"));
        try testing.expect(r.match(.{}, "ac"));
        try testing.expect(!r.match(.{}, "a"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a[böä]");
        defer r.deinit();
        try testing.expect(r.match(.{}, "ab"));
        try testing.expect(r.match(.{}, "aö"));
        try testing.expect(r.match(.{}, "aä"));
        try testing.expect(!r.match(.{}, "a"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "aA");
        defer r.deinit();
        try testing.expect(!r.match(.{ .case = .exact }, "aa"));
        try testing.expect(!r.match(.{ .case = .exact }, "AA"));
        try testing.expect(!r.match(.{ .case = .exact }, "Aa"));
        try testing.expect(r.match(.{ .case = .exact }, "aA"));
        try testing.expect(r.match(.{ .case = .ignore }, "aa"));
        try testing.expect(r.match(.{ .case = .ignore }, "AA"));
        try testing.expect(r.match(.{ .case = .ignore }, "Aa"));
        try testing.expect(r.match(.{ .case = .ignore }, "aA"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a.b");
        defer r.deinit();
        try testing.expect(r.match(.{}, "acb"));
        try testing.expect(r.match(.{}, "aµb"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a.?b");
        defer r.deinit();
        try testing.expect(r.match(.{}, "acb"));
        try testing.expect(r.match(.{}, "aµb"));
        try testing.expect(r.match(.{}, "ab"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a.+b");
        defer r.deinit();
        try testing.expect(r.match(.{}, "acb"));
        try testing.expect(r.match(.{}, "aµb"));
        try testing.expect(r.match(.{}, "aµµöäüb"));
        try testing.expect(!r.match(.{}, "ab"));
    }
    {
        var r = try Regex(.{}).compile(testing.allocator, "a.*b");
        defer r.deinit();
        try testing.expect(r.match(.{}, "acb"));
        try testing.expect(r.match(.{}, "aµb"));
        try testing.expect(r.match(.{}, "aµµöäüb"));
        try testing.expect(r.match(.{}, "ab"));
    }
}

fn Compiler(comptime T: type) type {
    const start_state = 1;
    const end_state = 1 << (@typeInfo(T).int.bits - 1);
    return struct {
        const Self = @This();

        const Block = struct {
            start: T,
            end: T,
            before_last_subblock: T,
        };

        blocks: std.ArrayListUnmanaged(Block) = .{},

        from: std.ArrayListUnmanaged(T) = .{},
        to: std.ArrayListUnmanaged(T) = .{},
        when: std.ArrayListUnmanaged(u8) = .{},

        current_state: T = start_state,
        state_counter: T = start_state,

        pub fn new(a: mem.Allocator) !Self {
            var cmp: Self = .{};
            try cmp.blocks.append(a, .{
                .start = start_state,
                .end = end_state,
                .before_last_subblock = start_state,
            });
            return cmp;
        }

        pub fn deinit(self: *Self, a: mem.Allocator) void {
            self.blocks.deinit(a);
            self.from.deinit(a);
            self.to.deinit(a);
            self.when.deinit(a);
            self.* = undefined;
        }

        pub fn getOwned(self: *Self, a: mem.Allocator) !struct {
            from: []T,
            to: []T,
            when: []u8,
        } {
            if (self.blocks.items.len != 1) return error.RegexInvalid;
            try self.closeSubblock(a);
            const from_owned = try self.from.toOwnedSlice(a);
            errdefer a.free(from_owned);
            const to_owned = try self.to.toOwnedSlice(a);
            errdefer a.free(to_owned);
            const when_owned = try self.when.toOwnedSlice(a);
            errdefer a.free(when_owned);
            return .{
                .from = from_owned,
                .to = to_owned,
                .when = when_owned,
            };
        }

        fn nextState(self: *Self) !T {
            debug.assert(self.state_counter < math.maxInt(T));
            self.state_counter <<= 1;
            if (self.current_state == end_state) {
                return error.RegexTooComplex;
            }
            return self.state_counter;
        }

        fn currentBlock(self: *Self) *Block {
            return &self.blocks.items[self.blocks.items.len - 1];
        }

        fn rule(self: *Self, a: mem.Allocator, f: T, t: T, w: u8) !void {
            try self.when.append(a, w);
            try self.from.append(a, f);
            try self.to.append(a, t);
        }

        pub fn addLiteral(self: *Self, a: mem.Allocator, l: u8) !void {
            const cb = self.currentBlock();
            cb.before_last_subblock = self.current_state;
            const new_state = try self.nextState();
            try self.rule(a, self.current_state, new_state, l);
            self.current_state = new_state;
        }

        pub fn addMultiByteLiteral(self: *Self, a: mem.Allocator, mbl: []const u8) !void {
            const cb = self.currentBlock();
            cb.before_last_subblock = self.current_state;
            var next_state: T = self.current_state;
            for (mbl) |byte| {
                next_state = try self.nextState();
                try self.rule(a, self.current_state, next_state, byte);
                self.current_state = next_state;
            }
        }

        pub fn addLiteralArray(self: *Self, a: mem.Allocator, lits: []const u8) !void {
            const cb = self.currentBlock();

            cb.before_last_subblock = self.current_state;
            const after = try self.nextState();

            var escape: bool = false;
            var skip: u3 = 0;
            for (lits, 0..) |l, index| {
                if (skip > 0) {
                    skip -= 1;
                    continue;
                }

                if (escape) {
                    const lit = switch (l) {
                        'n' => '\n',
                        't' => '\t',
                        'r' => '\r',
                        '[', ']', '\\' => l,
                        else => return error.RegexInvalid,
                    };
                    try self.rule(a, self.current_state, after, lit);
                    escape = false;
                } else {
                    switch (l) {
                        '[', ']' => return error.RegexInvalid,
                        '\\' => escape = true,
                        else => {
                            const bytes = unicode.utf8ByteSequenceLength(l) catch 1;
                            if (bytes == 1) {
                                try self.rule(a, self.current_state, after, l);
                            } else {
                                skip = bytes - 1;
                                var prev: T = self.current_state;
                                for (lits[index .. index + bytes - 1]) |byte| {
                                    const next = try self.nextState();
                                    try self.rule(a, prev, next, byte);
                                    prev = next;
                                }
                                try self.rule(a, prev, after, lits[index + bytes - 1]);
                            }
                        },
                    }
                }
            }
            self.current_state = after;
        }

        pub fn addOr(self: *Self, a: mem.Allocator) !void {
            const cb = self.currentBlock();
            try self.rule(a, self.current_state, cb.end, 0);
            self.current_state = cb.start;
        }

        pub fn addModifier(self: *Self, a: mem.Allocator, mod: u8) !void {
            const cb = self.currentBlock();
            switch (mod) {
                // Block matches zero or more.
                '*' => {
                    try self.rule(a, cb.before_last_subblock, self.current_state, 0);
                    try self.rule(a, self.current_state, cb.before_last_subblock, 0);
                },

                // Block matches one or more.
                '+' => try self.rule(a, self.current_state, cb.before_last_subblock, 0),

                // Block matches zero or one.
                '?' => try self.rule(a, cb.before_last_subblock, self.current_state, 0),

                else => unreachable,
            }
        }

        pub fn openSubblock(self: *Self, a: mem.Allocator) !void {
            const cb = self.currentBlock();
            cb.before_last_subblock = self.current_state;
            const end = try self.nextState();
            try self.blocks.append(a, .{
                .start = self.current_state,
                .before_last_subblock = self.current_state,
                .end = end,
            });
        }

        pub fn closeSubblock(self: *Self, a: mem.Allocator) !void {
            if (self.blocks.items.len == 0) return error.RegexInvalid;
            const cb = self.currentBlock();
            try self.rule(a, self.current_state, cb.end, 0);
            self.current_state = cb.end;
            _ = self.blocks.pop();
        }
    };
}

const Tokenizer = struct {
    const Token = union(enum) {
        literal: u8,
        multibyte_literal: []const u8,
        literal_array: []const u8,
        modifier: u8,
        @"or": void,
        open_block: void,
        close_block: void,
    };

    input: []const u8,
    allow_mods: bool = false,

    pub fn from(str: []const u8) Tokenizer {
        return .{ .input = str };
    }

    pub fn next(self: *Tokenizer) !?Token {
        if (self.input.len == 0) return null;
        const ch = self.input[0];
        const prev_input = self.input;
        self.input = if (self.input.len >= 1) self.input[1..] else "";
        switch (ch) {
            '[' => {
                self.allow_mods = true;

                // We need to iterate over the block to make sure we skip
                // escaped brackets. Actually parsing escapes is done in
                // the compiler.
                var close_index: usize = undefined;
                var esc: bool = false;
                for (self.input, 0..) |c, i| {
                    if (esc) {
                        esc = false;
                        continue;
                    }
                    switch (c) {
                        '\\' => esc = true,
                        '[' => return error.RegexInvalid,
                        ']' => {
                            close_index = i;
                            break;
                        },
                        else => {},
                    }
                } else {
                    return error.RegexInvalid;
                }

                const block = self.input[0..close_index];
                if (block.len == 0) return error.RegexInvalid;
                const rest = self.input[close_index..];
                self.input = if (rest.len > 1) rest[1..] else "";
                return Token{ .literal_array = block };
            },
            ']' => return error.RegexInvalid,
            '(' => {
                self.allow_mods = false;
                return Token.open_block;
            },
            ')' => {
                self.allow_mods = true;
                return Token.close_block;
            },
            '\\' => {
                self.allow_mods = true;
                if (self.input.len == 0) return error.RegexInvalid;
                const n = self.input[0];
                self.input = if (self.input.len >= 1) self.input[1..] else "";
                switch (n) {
                    '\\', '[', ']', '(', ')', '|', '+', '*', '?', '.' => {
                        return Token{ .literal = n };
                    },
                    'n' => return Token{ .literal = '\n' },
                    't' => return Token{ .literal = '\t' },
                    'r' => return Token{ .literal = '\r' },
                    else => return error.RegexInvalid,
                }
            },
            '+', '*', '?' => {
                if (!self.allow_mods) return error.RegexInvalid;
                self.allow_mods = false;
                return Token{ .modifier = ch };
            },
            '.' => {
                self.allow_mods = true;
                return Token{ .literal = 1 };
            },
            '|' => {
                self.allow_mods = false;
                return Token.@"or";
            },
            else => {
                self.allow_mods = true;
                const bytes = unicode.utf8ByteSequenceLength(ch) catch 1;
                if (bytes == 1 or prev_input.len < bytes) {
                    return Token{ .literal = ch };
                }
                self.input = self.input[bytes - 1 ..];
                return Token{ .multibyte_literal = prev_input[0..bytes] };
            },
        }
    }
};

test "Tokenizer" {
    const testing = std.testing;
    {
        var it = Tokenizer.from("abcd");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'b' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'c' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'd' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("ab|cd");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'b' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token.@"or", (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'c' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'd' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("a(b|c)d");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token.open_block, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'b' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token.@"or", (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'c' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token.close_block, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'd' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("a(b|c)+d?");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token.open_block, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'b' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token.@"or", (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'c' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token.close_block, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '+' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'd' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("a??");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expectError(error.RegexInvalid, it.next());
    }
    {
        var it = Tokenizer.from("a?+");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expectError(error.RegexInvalid, it.next());
    }
    {
        var it = Tokenizer.from("a.?");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 1 }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("(a?)?");
        try testing.expectEqual(Tokenizer.Token.open_block, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token.close_block, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("a\\?");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = '?' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("a\\?a?");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = '?' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("a\\??");
        try testing.expectEqual(Tokenizer.Token{ .literal = 'a' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .literal = '?' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
    {
        var it = Tokenizer.from("\\??");
        try testing.expectEqual(Tokenizer.Token{ .literal = '?' }, (try it.next()).?);
        try testing.expectEqual(Tokenizer.Token{ .modifier = '?' }, (try it.next()).?);
        try testing.expect((try it.next()) == null);
        try testing.expect((try it.next()) == null);
    }
}
