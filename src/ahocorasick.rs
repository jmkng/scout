use std::collections::{
    VecDeque,
};

use crate::{
    Match,
    Location,
    Pattern,
};

const FAIL: usize = 0;
const DEAD: usize = 1;
const START: usize = 2;

/// Automaton node.
#[derive(Clone)]
pub struct Node {
    /// Patterns match by this node.
    pub matches: Vec<Match>,
    /// Transitions to other node.
    pub transitions: [usize; 256],
    /// Fail transition id.
    pub fail: usize,
    /// Distance from START.
    pub depth: usize,
}

impl Node {
    pub fn new(fail: usize, depth: usize) -> Self {
        return Self{ matches: Vec::new(), transitions: [0; 256], fail, depth }
    }

    /// Return the length of the longest match.
    /// The longest match is the first one added during trie construction,
    /// because any subsequent match is one from a fail transition, which points to a suffix.
    /// Returns None if the node has no matches.
    pub fn get_longest_match_len(&self) -> Option<usize> {
        self.matches.get(0).map(|p| p.pattern_len)
    }
}

/// Position of a Node within a trie.
struct Position {
    /// Node id associated with this position.
    id: usize,
    /// Depth for a related parent fallback node, if known.
    depth_longest_match: Option<usize>,
}

// NOTE: Anything marked *LL is for leftmost-longest match semantics.

/// Aho-Corasick with leftmost-longest match semantics.
#[derive(Clone)]
pub struct LeftmostLongest {
    nodes: Vec<Node>,
}

impl LeftmostLongest {
    /// Return a new AhoCorasick automaton with leftmost-longest
    /// match semantics.
    pub fn new(patterns: &[Pattern]) -> Self {
        let mut ll = Self { nodes: Vec::new() };
        ll.build_trie(patterns);
        ll.encode_start_to_start();
        ll.encode_dead_to_dead();
        ll.encode_trie_failure();
        if ll.nodes[START].matches.len() > 0 {
            ll.encode_start_to_dead();
        }
        ll
    }

    /// Return the [`Location`] of the next [`Match`] in the haystack from start_byte_index.
    pub fn find(&self, haystack: &[u8], mut start_byte_index: usize) -> Option<Location> {
        let mut last_location = self.get_location(START, 0, start_byte_index);
        let mut current_node_id: usize = START;
        while start_byte_index < haystack.len() {
            current_node_id = self.get_next_non_fail_node_id(current_node_id, haystack[start_byte_index]);
            debug_assert_ne!(current_node_id, FAIL);
            start_byte_index += 1;
            if current_node_id == DEAD {
                debug_assert_ne!(last_location, None);
                return last_location;
            }
            let location = self.get_location(current_node_id, 0, start_byte_index);
            if location.is_some() {
                last_location = location;
            }
        }
        last_location
    }

    /// Return a [`Location`] for a node id and match id with end index.
    fn get_location(&self, id: usize, r#match: usize, end: usize) -> Option<Location> {
        let node = &self.nodes[id];
        if node.matches.len() == 0 || r#match >= node.matches.len() {
            return None;
        }
        let match_node = node.matches[r#match];
        Some(Location{ r#match: match_node, end })
    }

    /// Return the next non-fail node id.
    fn get_next_non_fail_node_id(&self, mut id: usize, byte: u8) -> usize {
        loop {
            let next = self.nodes[id].transitions[byte as usize];
            if next != FAIL {
                return next
            } else {
                id = self.nodes[id].fail;
            }
        }
    }

    //>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    // Trie
    //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    /// Build a trie with a node for each byte in patterns.
    fn build_trie(&mut self, patterns: &[Pattern]) {
        // These are the initial states.
        // FAIL, DEAD, START.
        for _ in 0..3 {
            self.add_node(0);
        }
        // For each pattern, create a chain of nodes ending with a leaf node containing a match.
        for pattern in patterns.iter() {
            let mut current_node_id = START;
            // Iterate over pattern to create a transition to each character from START.
            for (depth, byte) in pattern.value.iter().enumerate() {
                let depth_non_zero_index = depth + 1;
                let current_node_transition_id = self.nodes[current_node_id].transitions[*byte as usize];
                if current_node_transition_id == FAIL {
                    // Add a transition for the byte.
                    let new_node_id = self.add_node(depth_non_zero_index);
                    self.nodes[current_node_id].transitions[*byte as usize] = new_node_id;
                    current_node_id = new_node_id;
                } else {
                    // Transition already exists, so just move to it.
                    current_node_id = current_node_transition_id;
                }
            }

            // Found the end of the branch for this pattern.
            // Record the match.
            let m = Match { pattern_id: pattern.id, pattern_len: pattern.value.len() };
            self.nodes[current_node_id].matches.push(m);
        }
    }

    /// Encode START->FAIL transitions as START->START.
    fn encode_start_to_start(&mut self) {
        for byte in 0..256 {
            if self.nodes[START].transitions[byte] == FAIL {
                self.nodes[START].transitions[byte] = START;
            }
        }
    }

    /// Encode DEAD->FAIL transitions as DEAD->DEAD.
    fn encode_dead_to_dead(&mut self) {
        for byte in 0..256 {
            if self.nodes[DEAD].transitions[byte] == FAIL {
                self.nodes[DEAD].transitions[byte] = DEAD;
            }
        }
    }

    /// Encode START->START transitions as START->DEAD.
    fn encode_start_to_dead(&mut self) {
        for byte in 0..256 {
            if self.nodes[START].transitions[byte] == START {
                self.nodes[START].transitions[byte] = DEAD;
            }
        }
    }

    /// Encode a fail state transition for each node.
    fn encode_trie_failure(&mut self) {
        let mut queue: VecDeque<Position> = VecDeque::new();

        for byte in 0..256 {
            let start_node = &mut &self.nodes[START];
            let transition_id = start_node.transitions[byte as usize];
            // Avoid infinite loop...
            if transition_id == START {
                continue;
            }
            let match_depth: Option<usize> = if start_node.matches.len() > 0 {
                Some(0)
            } else {
                None
            };
            queue.push_back(Position{ id: transition_id, depth_longest_match: match_depth });

            // *LL
            // In leftmost-longest, failure transitions to DEAD instead of START.
            let next_node = &mut self.nodes[transition_id];
            if next_node.matches.len() > 0 {
                next_node.fail = DEAD;
            }
        }

        // Traverse queue to find additional transitions.
        while let Some(position) = queue.pop_front() {
            let prev = queue.len();
            for byte in 0..256 {
                let next_id = self.nodes[position.id].transitions[byte];
                // If it does not transition to anything, skip it.
                if next_id == FAIL {
                    continue;
                }
                let transition_node = &self.nodes[next_id];

                // Establish depth of match, if any. None if no match exists.
                let next_match_depth = match position.depth_longest_match {
                    Some(depth) => Some(depth),
                    _ if transition_node.matches.len() > 0 => {
                        Some(transition_node.depth - transition_node.get_longest_match_len().unwrap() + 1)
                    }
                    None => None,
                };
                queue.push_back(Position { id: next_id, depth_longest_match: next_match_depth });

                // Figure out what this falls back to.
                let fail_id = {
                    let mut fail_id = self.nodes[position.id].fail;
                    while self.nodes[position.id].transitions[byte] == FAIL {
                        fail_id = self.nodes[position.id].fail;
                    }
                    self.nodes[fail_id].transitions[byte]
                };

                if let Some(match_depth) = next_match_depth {
                    let fail_depth = self.nodes[fail_id].depth;
                    let next_depth = self.nodes[next_id].depth;
                    if next_depth - match_depth + 1 > fail_depth {
                        self.nodes[next_id].fail = DEAD;
                        continue;
                    }

                    // *LL
                    debug_assert_ne!(self.nodes[next_id].fail, START, "should never fail to start in leftmost configuration");
                }
                self.nodes[next_id].fail = fail_id;
                debug_assert!(fail_id != next_id);

                // Shadow fail_id and next_id Node equivalents.
                let (fail_id, next_id) = if fail_id < next_id {
                    let (left, right) = self.nodes.split_at_mut(next_id);
                    (&mut left[fail_id], &mut right[0])
                } else {
                    let (left, right) = self.nodes.split_at_mut(fail_id);
                    (&mut right[0], &mut left[next_id])
                };
                next_id.matches.extend_from_slice(&fail_id.matches);
            }

            // If this is a match state with no transitions, set FAIL to DEAD to prevent it from restarting.
            if queue.len() == prev && self.nodes[position.id].matches.len() > 0 {
                self.nodes[position.id].fail = DEAD;
            }
            // *LL
            // A non leftmost-longest implementation may want to copy empty matches from the state state here,
            // to support overlapping matches.
        }
    }

    /// Add a Node and return its id.
    fn add_node(&mut self, depth: usize) -> usize {
        let id = self.nodes.len();
        self.nodes.push(Node {
            depth,
            fail: START,
            transitions: [FAIL; 256],
            matches: vec![],
        });
        id
    }
} // impl LeftmostLongest

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ahocorasick_basics() {
        let haystack = b"abc def ghi jkl mno pqr abc";
        let patterns = [
            Pattern { id: 0, value: b"bc" },
            Pattern { id: 1, value: b"ghi" },
            Pattern { id: 2, value: b"o p" },
            Pattern { id: 3, value: b"qr" },
        ];
        let expected = [
            Location { r#match: Match { pattern_id: 0, pattern_len: 2 }, end: 3 },
            Location { r#match: Match { pattern_id: 1, pattern_len: 3 }, end: 11 },
            Location { r#match: Match { pattern_id: 2, pattern_len: 3 }, end: 21 },
            Location { r#match: Match { pattern_id: 3, pattern_len: 2 }, end: 23 },
            Location { r#match: Match { pattern_id: 0, pattern_len: 2 }, end: 27 },
        ];
        t(&patterns, haystack, &expected);
    }

    #[track_caller]
    fn t(patterns: &[Pattern], haystack: &[u8], expected: &[Location]) {
        let mut ll = LeftmostLongest::new(patterns);
        let locations = all(&mut ll, haystack, 0);
        assert_eq!(expected.len(), locations.len());
        for (index, expected) in expected.iter().enumerate() {
            assert_eq!(expected, &locations[index]);
        }
    }

    fn all(ll: &mut LeftmostLongest, haystack: &[u8], mut at: usize) -> Vec<Location> {
        let mut locations: Vec<Location> = Vec::new();
        while at < haystack.len() {
            if let Some(loc) = ll.find(haystack, at) {
                if loc.end == at {
                    at += 1;
                } else {
                    at = loc.end;
                }
                locations.push(loc);
            } else {
                break;
            }
        }
        locations
    }
}
