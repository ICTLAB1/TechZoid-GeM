import Foundation

/// Whole-word search over recognised text.
///
/// Plain `contains` is wrong for the short cues this app leans on. "emi" sits
/// inside "PREMIER" and "Premium"; "nav" inside "Navi Mumbai"; "cif" inside
/// "specific"; "roi" inside "steroid". A credit card reading "HDFC BANK
/// PREMIER" scored as a loan for exactly that reason, and then had a stray
/// number filed as its EMI.
///
/// So a term only counts when what sits either side of it is not part of the
/// same word. The boundary is required only at an end that is itself a word
/// character, because plenty of real cues end in punctuation — "policy #",
/// "a/c no", "no.".
///
/// Deliberately not a regular expression: this runs over every cue for every
/// line of a long statement, and compiling a pattern per cue per line is far
/// more expensive than walking the string.
enum TextMatching {

    /// Where `term` first appears as a whole word, if it does.
    static func range(of term: String, in haystack: String) -> Range<String.Index>? {
        guard !term.isEmpty, !haystack.isEmpty else { return nil }

        let needsLeadingBoundary = term.first.map(isWordCharacter) ?? false
        let needsTrailingBoundary = term.last.map(isWordCharacter) ?? false

        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let found = haystack.range(
                  of: term,
                  options: [.caseInsensitive],
                  range: searchStart ..< haystack.endIndex
              ) {
            if boundaryHolds(found, in: haystack, leading: needsLeadingBoundary, trailing: needsTrailingBoundary) {
                return found
            }
            // Step past this occurrence and keep looking — a later one in the
            // same line may be a genuine whole word.
            searchStart = haystack.index(after: found.lowerBound)
        }
        return nil
    }

    static func contains(_ term: String, in haystack: String) -> Bool {
        range(of: term, in: haystack) != nil
    }

    /// The first of `terms` that appears as a whole word, in the order given.
    static func firstMatch(of terms: [String], in haystack: String) -> (term: String, range: Range<String.Index>)? {
        for term in terms {
            if let range = range(of: term, in: haystack) { return (term, range) }
        }
        return nil
    }

    private static func boundaryHolds(
        _ found: Range<String.Index>,
        in haystack: String,
        leading: Bool,
        trailing: Bool
    ) -> Bool {
        if leading, found.lowerBound > haystack.startIndex {
            let before = haystack[haystack.index(before: found.lowerBound)]
            if isWordCharacter(before) { return false }
        }
        if trailing, found.upperBound < haystack.endIndex {
            if isWordCharacter(haystack[found.upperBound]) { return false }
        }
        return true
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
