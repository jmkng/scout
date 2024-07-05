const std = @import("std");
const AhoCorasick = @import("./ahocorasick.zig").AhoCorasick;

/// Supported algorithms.
pub const Algorithm = enum {
    /// Aho-Corasick in leftmost longest configuration.
    ahocorasick_leftmost,
};

/// Provides a `find` method used to search bytes with some inner algorithm.
pub const Finder = union(enum) {
    ahocorasick: AhoCorasick,

    /// Release all allocated memory.
    pub fn deinit(self: *Finder) void {
        switch (self.*) {
            .ahocorasick => |*aho| aho.deinit(),
        }
    }

    /// Call `find` on the inner algorithm.
    pub fn find(self: Finder, text: []const u8, at: usize) ?Location {
        switch (self) {
            .ahocorasick => |aho| return aho.find(text, at),
        }
    }
};

/// Describes the location of a `Match` within some source text.
pub const Location = struct {
    /// The `Match` that this `Location` is related to.
    match: Match,
    /// Ending index of the pattern.
    ///
    /// This is the index of the first non-pattern byte that is discovered after
    /// a pattern is matched.
    ///
    /// For example, searching the string "##hello" for a pattern of "##" will return a `Location`
    /// that has an ending index of 2, which is the character "h".
    ///
    /// Slicing the string with `[location.beginning()..location.end]` returns the "##".
    end: usize,

    /// Return the beginning index of the `Match` within this `Location`.
    pub fn beginning(self: Location) usize {
        return self.end - self.match.len;
    }
};

/// Represents a matched pattern.
pub const Match = struct {
    /// Pattern ID.
    id: usize,
    /// Length of the pattern.
    len: usize,
};
