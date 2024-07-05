# Installation

```
zig fetch --save git+https://github.com/jmkng/scout
```

In `build.zig`:

```zig
const scout = b.dependency("scout", .{});
exe.root_module.addImport("scout", scout.module("scout"));
```

# Usage

Create a set of patterns for Scout to search for.

```zig
const Pattern = @import("scout").Pattern;

const patterns = [_]Pattern{
    Pattern{ .id = 0, .value = ">>" },
}
```

Create an instance of `Scout`, which will train an automaton on your patterns.

```zig
const Scout = @import("scout").Scout;

// The `algorithm` property is where you would set the algorithm used 
// to perform the search.
//
// Only AhoCorasick with leftmost-longest matching semantics is 
// implemented now. It is the default, so you can exclude this property for now.
var s = Scout.init(allocator,  .{ .algorithm = .ahocorasick_leftmost, .patterns = &patterns });
defer scout.deinit();
```

The `next` method returns the location of the next pattern from an index,
or null if none are found.

```zig
const haystack = "hello >> world";
var maybe_location = s.next(haystack, 0);
```

The `all` method returns a slice of all the discovered patterns from an index.
The slice has no items if none are found.

The caller owns the returned memory.

```zig
const haystack = "hello >> world";
var locations = s.all(haystack, 0);
defer allocator.free(locations);
```

The `start` method returns a match if the index is the beginning of a pattern,
or null if it is not.

```zig
const haystack = "hello >> world";
var maybe_match = s.starts(haystack, 0); // Null
maybe_match = s.starts(haystack, 6); // Match 
```
