const std = @import("std");
const Match = @import("./algorithm.zig").Match;
const Location = @import("./algorithm.zig").Location;
const Pattern = @import("./root.zig").Pattern;

const FAIL = 0;
const DEAD = 1;
const START = 2;

/// An implementation of `Finder` using the Aho-Corasick algorithm.
pub const AhoCorasick = struct {
    nodes: std.ArrayList(Node),

    /// Deinitialize with `deinit`.
    pub fn init(allocator: std.mem.Allocator, patterns: []const Pattern) !AhoCorasick {
        // TODO: This is where we would select a trainer based on the desired match semantics,
        // but only leftmost-longest is implemented now.
        const trainer = try LeftmostLongestTrainer.init(allocator, patterns);
        return AhoCorasick{ .nodes = trainer.nodes };
    }

    /// Release all allocated memory.
    pub fn deinit(self: *AhoCorasick) void {
        for (self.nodes.items) |*node| node.deinit();
        self.nodes.deinit();
    }

    /// Implementation of `Finder.find` for `AhoCorasick`.
    pub fn find(self: AhoCorasick, text: []const u8, at: usize) ?Location {
        var index_in_bytes = at;
        var current_state: usize = START;
        var last_location = self.getLocation(START, 0, index_in_bytes);

        while (index_in_bytes < text.len) {
            current_state = self.nextNonFailNode(current_state, text[index_in_bytes]);
            std.debug.assert(current_state != FAIL); // Should never return fail.
            index_in_bytes += 1;
            if (current_state == DEAD) {
                std.debug.assert(last_location != null);
                return last_location;
            }
            const location = self.getLocation(current_state, 0, index_in_bytes);
            if (location != null) last_location = location;
        }

        return last_location;
    }

    fn getLocation(self: AhoCorasick, id: usize, match: usize, end: usize) ?Location {
        const state = self.getNode(id);
        if (state.matches.items.len == 0 or match >= state.matches.items.len) return null;

        const match_node = state.matches.items[match];
        return Location{ .match = match_node, .end = end };
    }

    /// Return a `*Node` by id.
    ///
    /// Does not perform bounds check.
    fn getNode(self: AhoCorasick, id: usize) *Node {
        return &self.nodes.items[id];
    }

    /// Return the next non-fail `Node`.
    fn nextNonFailNode(self: AhoCorasick, id: usize, byte: u8) usize {
        var current_id = id;
        while (true) {
            const next = self.getNode(current_id).getTransition(byte);
            if (next != FAIL) return next else current_id = self.getNode(current_id).fail;
        }
    }
};

/// Used to train an `AhoCorasick` automaton with leftmost-longest matching semantics.
const LeftmostLongestTrainer = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),

    /// Deinitialize with `deinit`.
    fn init(allocator: std.mem.Allocator, patterns: []const Pattern) !LeftmostLongestTrainer {
        var trainer = LeftmostLongestTrainer{ .allocator = allocator, .nodes = std.ArrayList(Node).init(allocator) };
        try trainer.buildTrie(patterns);
        trainer.encodeStartToStart();
        trainer.encodeDeadToDead();
        try trainer.encodeTrieFailure();
        if (trainer.getNode(START).matches.items.len > 0) trainer.encodeStartToDead();
        return trainer;
    }

    /// Release all allocated memory.
    fn deinit(self: *LeftmostLongestTrainer) void {
        for (self.nodes.items) |*node| node.deinit();
        self.nodes.deinit();
    }

    /// Build a trie with a node for each byte in the provided patterns.
    fn buildTrie(self: *LeftmostLongestTrainer, patterns: []const Pattern) !void {
        // Create three nodes for the base (fail, start, dead) states.
        for (0..3) |_| _ = try self.addNode(0);

        // For each pattern, create a chain of nodes ending with a leaf node containing a match.
        for (patterns) |pattern| {
            var current_node_id: usize = START;

            for (pattern.value, 0..) |byte, index| {
                const byte_non_zero_index = index + 1;
                const current_node_transition_id = self.getNode(current_node_id).getTransition(byte);

                if (current_node_transition_id == FAIL) {
                    // Add a transition for the byte.
                    const id = try self.addNode(byte_non_zero_index);
                    self.getNode(current_node_id).setTransition(byte, id);
                    current_node_id = id;
                } else current_node_id = current_node_transition_id; // Transition already exists, so just move to it.
            }

            // After iterating through the bytes in the pattern, we end up at the tip of the branch for that pattern.
            // Create a match here to represent that.
            const match = Match{ .id = pattern.id, .len = pattern.value.len };
            try self.getNode(current_node_id).matches.append(match);
        }
    }

    /// Encode a `FAIL` state transition for each `Node`.
    fn encodeTrieFailure(self: *LeftmostLongestTrainer) !void {
        // 0 = transition id
        // 1 = depth of longest match
        var queue = std.ArrayList(Position).init(self.allocator);
        defer queue.deinit();

        // Populate the queue by performing a breadth-first search of all transitions from `START`.
        for (0..256) |byte| {
            const as_u8: u8 = @intCast(byte);
            const transition_id = self.getNode(START).getTransition(as_u8);
            if (transition_id == START) continue; // Avoid infinite loop...
            const match_depth: ?usize = if (self.getNode(START).matches.items.len > 0) 0 else null;
            try queue.append(Position{ .id = transition_id, .depth_longest_match = match_depth });

            // * LL
            // Failure should lead to `DEAD` instead of `START`.
            var next = self.getNode(transition_id);
            if (next.matches.items.len > 0) next.fail = DEAD;
        }

        // Traverse queue to find additional transitions.
        while (queue.items.len > 0) {
            const popped = queue.pop();
            const len_after_pop = queue.items.len;

            for (0..256) |byte| {
                const as_u8: u8 = @intCast(byte);
                const leads_to_id = self.getNode(popped.id).getTransition(as_u8);
                if (leads_to_id == FAIL) continue; // If it doesn't lead to anything, skip it.
                var transition_node = self.getNode(leads_to_id);

                // Find the depth of the fallback node.
                var next_match_depth: ?usize = null;
                if (popped.depth_longest_match != null) {
                    next_match_depth = popped.depth_longest_match;
                } else if (transition_node.matches.items.len > 0) {
                    next_match_depth = transition_node.depth - transition_node.getLongestMatch().? + 1;
                }
                try queue.append(Position{ .id = leads_to_id, .depth_longest_match = next_match_depth });

                // Figure out what this falls back to.
                const popped_fail_id = self.getNode(popped.id).fail;
                const fail_id = self.getNode(popped_fail_id).getTransition(as_u8);
                if (next_match_depth != null) {
                    const fail_depth = self.getNode(fail_id).depth;
                    const leads_to_depth = self.getNode(leads_to_id).depth;

                    if (leads_to_depth - next_match_depth.? + 1 > fail_depth) {
                        self.getNode(leads_to_id).fail = DEAD;
                        continue;
                    }

                    // * LL
                    std.debug.assert(self.getNode(leads_to_id).fail == START);
                }
                self.getNode(leads_to_id).fail = fail_id;

                std.debug.assert(fail_id != leads_to_id);

                var fail_node: ?*Node = null;
                var leads_to_node: ?*Node = null;

                if (fail_id < leads_to_id) {
                    const left = self.nodes.items[0..leads_to_id];
                    const right = self.nodes.items[leads_to_id..self.nodes.items.len];
                    fail_node = &left[fail_id];
                    leads_to_node = &right[0];
                } else {
                    const left = self.nodes.items[0..fail_id];
                    const right = self.nodes.items[fail_id..self.nodes.items.len];
                    fail_node = &right[0];
                    leads_to_node = &left[leads_to_id];
                }
                std.debug.assert(fail_node != null and leads_to_node != null);
                // Clone the fail_node matches over to leads_to_node matches.
                try leads_to_node.?.matches.appendSlice(fail_node.?.matches.items);
            }

            // If this is a match state with no transitions, set FAIL to DEAD to prevent it from restarting.
            if (queue.items.len == len_after_pop and self.getNode(popped.id).matches.items.len > 0) {
                self.getNode(popped.id).fail = DEAD;
            }
            // *  LL
            // A non leftmost-longest implementation may want to copy empty matches from the state state here,
            // to support overlapping matches.
        }
    }

    /// Encode `start->fail` transitions as `start->start`.
    fn encodeStartToStart(self: *LeftmostLongestTrainer) void {
        for (0..256) |byte| {
            const as_u8: u8 = @intCast(byte);
            var node = self.getNode(START);
            if (node.getTransition(as_u8) == FAIL) node.setTransition(as_u8, START);
        }
    }

    /// Encode `dead->fail` transitions as `dead->dead`.
    fn encodeDeadToDead(self: *LeftmostLongestTrainer) void {
        for (0..256) |byte| {
            const as_u8: u8 = @intCast(byte);
            var node = self.getNode(DEAD);
            if (node.getTransition(as_u8) == FAIL) node.setTransition(as_u8, DEAD);
        }
    }

    /// Encode `start->start` transitions as `start->dead`.
    fn encodeStartToDead(self: *LeftmostLongestTrainer) void {
        for (0..256) |byte| {
            const as_u8: u8 = @intCast(byte);
            var node = self.getNode(START);
            if (node.getTransition(as_u8) == START) node.setTransition(as_u8, DEAD);
        }
    }

    /// Add a new `Node` and return the ID.
    fn addNode(self: *LeftmostLongestTrainer, depth: usize) !usize {
        const id = self.nodes.items.len;
        const node = Node.init(self.allocator, START, depth);
        try self.nodes.append(node);
        return id;
    }

    /// Return a pointer to a `Node` based on ID.
    fn getNode(self: *LeftmostLongestTrainer, id: usize) *Node {
        return &self.nodes.items[id];
    }
};

const Node = struct {
    /// The patterns matched by this `Node`.
    matches: std.ArrayList(Match),
    /// Transitions to other `Node`.
    transition: [256]usize = [_]usize{0} ** 256,
    /// The ID of the `Node` that acts as the `FAIL` transition for this `Node`.
    fail: usize,
    /// The distance of this `Node` from the `START` `Node`.
    depth: usize,

    /// Deinitialize with `deinit`.
    fn init(allocator: std.mem.Allocator, fail: usize, depth: usize) Node {
        return Node{
            .matches = std.ArrayList(Match).init(allocator),
            .fail = fail,
            .depth = depth,
        };
    }

    /// Release all allocated memory.
    fn deinit(self: *Node) void {
        self.matches.deinit();
    }

    /// Get a `Node` transition ID for a byte.
    fn getTransition(self: *Node, byte: u8) usize {
        return self.transition[byte];
    }

    /// Set a `Node` transition id for a byte.
    fn setTransition(self: *Node, byte: u8, id: usize) void {
        self.transition[byte] = id;
    }

    /// Return the length of the longest `Match` on this `Node`.
    ///
    /// **Note:** The longest match for any node is the first one added during trie construction,
    /// because any subsequent match is one from a fail transition,
    /// which points to a suffix.
    fn getLongestMatch(self: *Node) ?usize {
        return if (self.matches.items.len > 0) self.matches.items[0].len else null;
    }
};

/// Documents the location of another `Node` within a trie.
const Position = struct {
    /// the ID of the `Node` associated with this `Position`.
    id: usize,
    /// An optional depth for a related parent fallback node.
    depth_longest_match: ?usize,
};

const testing = std.testing;
const Scout = @import("./root.zig").Scout;

test "ahocorasick basics" {
    const ah = "abc def ghi jkl mno pqr abc";
    const ap = .{
        Pattern{ .id = 0, .value = "bc" },
        Pattern{ .id = 1, .value = "ghi" },
        Pattern{ .id = 2, .value = "o p" },
        Pattern{ .id = 3, .value = "qr" },
    };
    const ae = .{
        Location{ .match = Match{ .id = 0, .len = 2 }, .end = 3 },
        Location{ .match = Match{ .id = 1, .len = 3 }, .end = 11 },
        Location{ .match = Match{ .id = 2, .len = 3 }, .end = 21 },
        Location{ .match = Match{ .id = 3, .len = 2 }, .end = 23 },
        Location{ .match = Match{ .id = 0, .len = 2 }, .end = 27 },
    };
    try t(&ap, ah, &ae);

    const bh = "a";
    const bp = .{
        Pattern{ .id = 0, .value = "a" },
    };
    const be = .{
        Location{ .match = Match{ .id = 0, .len = 1 }, .end = 1 },
    };
    try t(&bp, bh, &be);

    const ch = "aa";
    const cp = .{
        Pattern{ .id = 0, .value = "a" },
    };
    const ce = .{
        Location{ .match = Match{ .id = 0, .len = 1 }, .end = 1 },
        Location{ .match = Match{ .id = 0, .len = 1 }, .end = 2 },
    };
    try t(&cp, ch, &ce);
}

test "ahocorasick non-overlapping" {
    const ah = "qwerty";
    const ap = .{
        Pattern{ .id = 0, .value = "qwerty" },
        Pattern{ .id = 1, .value = "werty" },
        Pattern{ .id = 2, .value = "erty" },
    };
    const ae = .{
        Location{ .match = Match{ .id = 0, .len = 6 }, .end = 6 },
    };
    try t(&ap, ah, &ae);
}

test "ahocorasick leftmost" {
    const ah = "abcd";
    const ap = .{
        Pattern{ .id = 0, .value = "ab" },
        Pattern{ .id = 1, .value = "ab" },
    };
    const ae = .{
        Location{ .match = Match{ .id = 0, .len = 2 }, .end = 2 },
    };
    try t(&ap, ah, &ae);

    const bh = "abce";
    const bp = .{
        Pattern{ .id = 0, .value = "abcd" },
        Pattern{ .id = 1, .value = "bce" },
        Pattern{ .id = 2, .value = "b" },
    };
    const be = .{
        Location{ .match = Match{ .id = 1, .len = 3 }, .end = 4 },
    };
    try t(&bp, bh, &be);
}

test "ahocorasick leftmost-longest" {
    const ah = "abcd";
    const ap = .{
        Pattern{ .id = 0, .value = "ab" },
        Pattern{ .id = 1, .value = "abcd" },
    };
    const ae = .{
        Location{ .match = Match{ .id = 1, .len = 4 }, .end = 4 },
    };
    try t(&ap, ah, &ae);

    const bh = "abcdefghz";
    const bp = .{
        Pattern{ .id = 0, .value = "a" },
        Pattern{ .id = 1, .value = "abcdef" },
        Pattern{ .id = 2, .value = "abc" },
        Pattern{ .id = 3, .value = "abcdefg" },
    };
    const be = .{
        Location{ .match = Match{ .id = 3, .len = 7 }, .end = 7 },
    };
    try t(&bp, bh, &be);

    const ch = "azcabbbc";
    const cp = .{
        Pattern{ .id = 0, .value = "a" },
        Pattern{ .id = 1, .value = "ab" },
    };
    const ce = .{
        Location{ .match = Match{ .id = 0, .len = 1 }, .end = 1 },
        Location{ .match = Match{ .id = 1, .len = 2 }, .end = 5 },
    };
    try t(&cp, ch, &ce);
}

test "ahocorasick leftmost-longest starts" {
    const ah = "zabcd";
    const ap = .{
        Pattern{ .id = 0, .value = "ab" },
        Pattern{ .id = 1, .value = "abcd" },
    };
    var scout = try Scout.init(testing.allocator, .{ .algorithm = .ahocorasick_leftmost, .patterns = &ap });
    defer scout.deinit();

    try testing.expect(scout.starts(ah, 0) == null);

    const maybe_match = scout.starts(ah, 1);
    try testing.expect(maybe_match != null);
    try testing.expect(maybe_match.?.id == 1);
}

fn t(patterns: []const Pattern, haystack: []const u8, expected: []const Location) !void {
    var scout = try Scout.init(testing.allocator, .{ .algorithm = .ahocorasick_leftmost, .patterns = patterns });
    defer scout.deinit();

    const result = try scout.all(haystack, 0);
    defer testing.allocator.free(result);

    try std.testing.expectEqual(expected.len, result.len);
    for (expected, 0..) |location, i| {
        try testing.expectEqual(location, result[i]);
    }
}
