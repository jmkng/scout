const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const AhoCorasick = @import("./ahocorasick.zig").AhoCorasick;

/// Flags for supported algorithms.
pub const Algorithm = enum {
    /// Aho-Corasick with leftmost-longest match semantics.
    ahocorasick_ll,
};

pub const Scout = struct {
    backend: Backend,

    /// Deinitialize with deinit.
    pub fn init(alloc: Allocator, patterns: []const Pattern, algo: Algorithm) !Scout {
        return .{ 
            .backend = switch(algo) {
                .ahocorasick_ll => .{ 
                    .ahocorasick = try AhoCorasick.init(alloc, patterns) 
                },
            }
        };
    }

    /// Release all allocated memory.
    pub fn deinit(self: *Scout, alloc: Allocator) void {
        self.backend.deinit(alloc);
    }

    /// Return the next Location in text from index at.
    pub fn find(self: *Scout, text: []const u8, at: usize) ?Location {
        return self.backend.find(text, at);
    }

    /// Return a Location for each match in text from index at.
    /// Caller owns the returned memory.
    pub fn all(self: *Scout, alloc: Allocator, text: []const u8, at: usize) ![]Location {
        var result = std.ArrayList(Location).empty;
        defer result.deinit(alloc);

        var pos: usize = at;
        while (pos < text.len) {
            if (self.find(text, pos)) |location| {
                if (location.end == pos) pos += 1 else pos = location.end;
                try result.append(alloc, location);
            } else break;
        }

        return try result.toOwnedSlice(alloc);
    }

    /// Return a Match if a pattern begins at the provided index.
    pub fn starts(self: *Scout, text: []const u8, at: usize) ?Match {
        const maybe_location = self.find(text, at);
        if (maybe_location == null) return null;

        const location = maybe_location.?;
        if (location.beginning() == at) return location.match else return null;
    }

    /// Storage for the selected algorithm.
    /// A method find is exposed, which calls the underlying find method on the backend.
    const Backend = union(enum) {
        ahocorasick: AhoCorasick,

        /// Release all allocated memory.
        fn deinit(self: *Backend, alloc: Allocator) void {
            switch (self.*) {
                .ahocorasick => |*aho| aho.deinit(alloc),
            }
        }

        /// Call the find method on the active backend.
        fn find(self: Backend, text: []const u8, at: usize) ?Location {
            return switch (self) {
                .ahocorasick => |aho| aho.find(text, at),
            };
        }
    };
};

/// A byte pattern that can be searched for.
pub const Pattern = struct {
    /// A unique identifier for this pattern.
    id: usize,
    /// The actual value to be found.
    ///
    /// Example:
    ///
    /// ">>", "hello", "world", "##"
    value: []const u8,
};

/// Location of a Match within some source text.
pub const Location = struct {
    match: Match,
    /// Ending index of the pattern.
    ///
    /// This is the index of the first non-pattern byte that is discovered after
    /// a pattern is matched.
    ///
    /// For example, searching bytes "##hello" for a pattern of "##" will return a Location
    /// that has an ending index of 2, which is the character "h".
    ///
    /// Slicing as [location.beginning()..location.end] returns "##".
    end: usize,

    /// Return the beginning index of the Match.
    pub fn beginning(self: Location) usize {
        return self.end - self.match.len;
    }
};

/// Represents a matched pattern.
pub const Match = struct {
    /// Matched pattern id.
    id: usize,
    /// Pattern length.
    len: usize,
};

const testing = std.testing;

test "lifecycle" {
    // These are the patterns that the algorithm will recognize.
    // When a match is found in some text, a Match is returned which contains the pattern id you provided for that pattern.
    const patterns = [_]Pattern{
        Pattern{ .id = 0, .value = ">>" },
        Pattern{ .id = 1, .value = "##" },
    };
    var scout = try Scout.init(testing.allocator, patterns[0..patterns.len], Algorithm.ahocorasick_ll);
    defer scout.deinit(testing.allocator);
}
