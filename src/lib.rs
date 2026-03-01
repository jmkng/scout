#![allow(warnings)]

pub mod ahocorasick;

/// Matched pattern.
#[derive(Clone)]
pub struct Match {
    pub pattern_id: usize,
    pub pattern_len: usize,
}

/// Location of a match within some source text.
pub struct Location {
    pub r#match: Match,
    /// Index of the first non-pattern byte that is discovered after a match.
    pub end: usize,
}

/// Searchable byte pattern.
#[derive(Clone)]
pub struct Pattern<'a> {
    /// Must be unique within a set of patterns.
    pub id: usize,
    /// The actual bytes to match for this pattern.
    pub value: &'a [u8],
}
