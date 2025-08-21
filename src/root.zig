const std = @import("std");
const Finder = @import("./algorithm.zig").Finder;
const Algorithm = @import("./algorithm.zig").Algorithm;
const Location = @import("./algorithm.zig").Location;
const Match = @import("./algorithm.zig").Match;
const AhoCorasick = @import("./ahocorasick.zig").AhoCorasick;

/// Customize the search behavior of a `Scout` instance.
pub const ScoutParams = struct {
    algorithm: Algorithm = Algorithm.ahocorasick_leftmost,
    patterns: []const Pattern,
};

/// Provides methods for searching text.
pub const Scout = struct {
    allocator: std.mem.Allocator,
    finder: Finder,

    /// Deinitialize with `deinit`.
    pub fn init(allocator: std.mem.Allocator, params: ScoutParams) !Scout {
        const finder = switch (params.algorithm) {
            .ahocorasick_leftmost => Finder{ .ahocorasick = try AhoCorasick.init(allocator, params.patterns) },
        };
        return Scout{ .allocator = allocator, .finder = finder };
    }

    /// Release all allocated memory.
    pub fn deinit(self: *Scout) void {
        self.finder.deinit();
    }

    /// Return the `Location` of the next match from the given index.
    pub fn next(self: Scout, text: []const u8, at: usize) ?Location {
        return self.finder.find(text, at);
    }

    /// Return a `Location` for each match from the given index.
    ///
    /// The caller owns the returned memory.
    pub fn all(self: Scout, text: []const u8, at: usize) ![]Location {
        var result = std.ArrayList(Location).empty;
        defer result.deinit(self.allocator);

        var pos: usize = at;
        while (pos < text.len) {
            if (self.next(text, pos)) |location| {
                if (location.end == pos) pos += 1 else pos = location.end;
                try result.append(self.allocator, location);
            } else break;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Return a `Match` if a pattern begins at the provided index.
    pub fn starts(self: Scout, text: []const u8, at: usize) ?Match {
        const maybe_location = self.next(text, at);
        if (maybe_location == null) return null;

        const location = maybe_location.?;
        if (location.beginning() == at) return location.match else return null;
    }
};

/// Something that can be searched for.
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

const testing = std.testing;

test "lifecycle" {
    const patterns = [_]Pattern{
        Pattern{ .id = 0, .value = ">>" },
        Pattern{ .id = 1, .value = "##" },
    };
    var scout = try Scout.init(testing.allocator, .{ .patterns = patterns[0..patterns.len] });
    defer scout.deinit();
}
