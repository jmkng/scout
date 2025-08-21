Scout can quickly and efficiently search for patterns in large amounts of text.

# Installation

```
zig fetch --save git+https://github.com/jmkng/scout
```

In `build.zig`:

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
}
```

Give the patterns to Scout.init to train an automaton.

```zig
const Scout = @import("scout").Scout;

var s = Scout.init(allocator,  .{ .patterns = &patterns });
defer s.deinit();
```

Use Scout.next to return the location of the next pattern from a starting index,
or null if none are found.

```zig
const haystack = "hello >> world";
var maybe_location = s.next(haystack, 0);
```

Alternatively, use Scout.all to return a slice of all the discovered patterns from a starting index.
It will be empty if none are found.

The caller owns the returned memory.

```zig
const haystack = "hello >> world";
var locations = s.all(haystack, 0);
defer allocator.free(locations);
```

The Scout.starts method returns a match if the index is the beginning of a pattern,
or null otherwise.

```zig
const haystack = "hello >> world";
var maybe_match = s.starts(haystack, 0); // Null
maybe_match = s.starts(haystack, 6); // Match 
```
