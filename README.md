Scout can quickly and efficiently search for patterns in text.

The library is designed to work with a variety of algorithms,
but currently provides a single implementation: AhoCorasick with leftmost-longest semantics.

# Installation

```
zig fetch --save git+https://github.com/jmkng/scout
```

In build.zig:

```zig
const scout = b.dependency("scout", .{});
const scout_module = scout.module("scout");
exe.root_module.addImport("scout", scout_module);
```

# Usage

Create some patterns. They let Scout know what you are trying to find.

```zig
const Pattern = @import("scout").Pattern;

const patterns = [_]Pattern{
    Pattern{ .id = 0, .value = ">>" },
    Pattern{ .id = 1, .value = "##" },
};
```

Give the patterns to Scout.init to train an automaton.

```zig
const Scout = @import("scout").Scout;

var scout = try Scout.init(allocator, patterns[0..patterns.len], Algorithm.ahocorasick_ll);
defer scout.deinit();
```

Use the methods on scout to search. See the tests at the bottom of root.zig for examples.
