# zig-exre

zig-exre is a regular expression library for zig. It uses a vaguely
Thompson-esque approach of compiling regular expressions to nondeterministic
automata which are implemented as state machines.


Basic usage:

```zig
const exre = @import("exre");

const r = try exre.Regex(.{}).compile(alloc, "ab?|c*d");
defer r.deinit();

if (r.match(.{}, string)) {
    // ...
}
```

Alternatively you can also use the unmanaged version.

```zig
const r = try exre.RegexUnmanaged(.{}).compile(alloc, "ab?c*.");
defer r.deinit(alloc);
```

The behaviour of the `match()` function is configured via the first argument.
It is a struct exposing the following options:

* `.mode =`
  * `.exact`: Check whether the input string matches the regular expression
    exactly. _(default)_
  * `.substring` : Check whether any substring of the input string matches the
    regular expression.
* `.case = `
  * `.exact`: Match case sensitive. _(default)_
  * `.ignore`: Ignore cases of input string and regular expression. Only applies
    to ASCII.

zig-exre is unicode aware. Codepoints are treated as 'characters', however
there is no grapheme support (yet). Regular expressions are not required to
be valid unicode. Neither is the input string, with the caveat that invalid
unicode may lead to unexpected results if the `.` selector is used.

``` zig
const r = try exre.Regex(.{}).compile(alloc, "aä*");
defer r.deinit();
debug.assert(r.match(.{}, "a"));
debug.assert(r.match(.{}, "aä"));
debug.assert(r.match(.{}, "aääää"));

const e = try exre.Regex(.{}).compile(alloc, "a.+b");
defer e.deinit();
debug.assert(r.match(.{}, "acb"));
debug.assert(r.match(.{}, "aäb"));
debug.assert(r.match(.{}, "aµäüb"));
```

States are represented as bitfields, as such the maximum amount of states
and therefore the maximum complexity of regular expressions are limited. The
default integer encoding for the bitfield is `u64`, which seems to be enough
for common real-world regex usages. The amount of bits used can be configured
at compile time.

```zig
const R = exre.Regex(.{ .state_bits = 128 });
```

The automata graph of the state machine can be printed in the dot format.
You can pipe the output for example into `dot -Tpng` to create a visualisation.

```zig
const r = try exre.Regex(.{}).compile(alloc, "a(b|.?)*");
defer r.deinit();
try r.dumpDot(writer);
```

## Compiler Efficiency

Due to its strictly linear nature the compiler creates unnecessary extra states
for or `|` directives and blocks `()`.  Fixing this would require substantial
changes to the compiler and since it seems to be efficient enough for real
world use cases already this is considered an acceptable trade-off for now.

![diagram of the automata showing unnecessary states](.meta/extra-states.png)

## Performance

Performance is linear, scaling with length of regular expression and match
string.

The graph below was created with the `perf.py` script.  It creates an
array which contains `ab^ic` (where `b^i` is the character `b` repeated
`i` times) and tries to match the regular expressions `ab*c` and `what`
against it using both `match(.{ .mode = .exact }, string)` and
`match(.{ .mode = .substring }, string)` The time is measurement using
`std.time.Timer`. For this test the `exre` command was build
in `ReleaseFast` mode.

![performance graph of various test cases](.meta/perf.png)

While you might want to take these graphs with some seasoning, a good takeaway
is that zig-exre most likely performs well enough for your use case, unless
it is very exotic.

## `exre` Command

The zig-exre repository also compiles the `exre` program which is used to
test the library. It has the `dump`, `grep` and `perf` sub-commands, which
will dump the dot graph of the provided regular expression,act as a primitive
clone of the `grep` utility and perform performance measurement respectively.

## Zig Version

zig-exre is developed against zig releases. Currently zig 0.13.0.

## Contributing

You do not need a sourcehut account to contribute.

The simplest way is just pushing your changes to a publicly accessible git clone
of zig-exre on the git forge of your choice and then telling me about it.

Alternatively you can send patches and pull requests to
[my public inbox](mailto:~leon_plickat/public-inbox@lists.sr.ht)
or to my personal email address. Visit [git-send-email.io](https://git-send-email.io/)
to learn about the canonical way of using git via mail, but in practice you
don't need to worry too much about it.

Either way I recommend reaching out to me before you do any work.

## License

zig-exre is licensed under the Mozilla Public License version 2.0.

While I chose a non-viral license I do encourage you to use a viral
non-permissive license, like the (A)GPL, for your projects using zig-exre
in the spirit of FOSS. Please do not allow for your wonderful work to be
appropriated as free labour to improve someones profit margins. Know your
worth!
