import Foundation
import Security

/// Generates passwords and passphrases from the system CSPRNG — never
/// `Int.random`, which is seeded predictably enough to matter here.
enum PasswordGenerator {

    struct Options: Equatable {
        var length: Int = 20
        var includeUppercase = true
        var includeDigits = true
        var includeSymbols = true
        /// Drops l/I/1/O/0 so the password can be read aloud or copied by hand.
        var avoidAmbiguous = true
    }

    private static let lowercase = "abcdefghijkmnopqrstuvwxyz"
    private static let lowercaseFull = "abcdefghijklmnopqrstuvwxyz"
    private static let uppercase = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    private static let uppercaseFull = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let digits = "23456789"
    private static let digitsFull = "0123456789"
    private static let symbols = "!@#$%^&*-_=+?"

    static func make(_ options: Options = Options()) -> String {
        var alphabet = Array(options.avoidAmbiguous ? lowercase : lowercaseFull)
        var required: [Character] = []

        if options.includeUppercase {
            let set = Array(options.avoidAmbiguous ? uppercase : uppercaseFull)
            alphabet += set
            required.append(pick(from: set))
        }
        if options.includeDigits {
            let set = Array(options.avoidAmbiguous ? digits : digitsFull)
            alphabet += set
            required.append(pick(from: set))
        }
        if options.includeSymbols {
            let set = Array(symbols)
            alphabet += set
            required.append(pick(from: set))
        }

        let length = max(options.length, required.count + 1)
        var characters = required
        while characters.count < length {
            characters.append(pick(from: alphabet))
        }
        return String(shuffle(characters))
    }

    /// Four-word style, for the master passphrase suggestion.
    static func makePassphrase(words: Int = 4) -> String {
        let list = wordList
        var chosen: [String] = []
        for _ in 0..<words { chosen.append(list[index(below: list.count)]) }
        return chosen.joined(separator: "-") + "-" + String(format: "%02d", index(below: 100))
    }

    // MARK: - Cryptographic randomness

    private static func index(below limit: Int) -> Int {
        precondition(limit > 0)
        // Rejection sampling keeps the distribution flat instead of biasing
        // toward the low end the way a plain modulo would.
        let bound = UInt32.max - (UInt32.max % UInt32(limit))
        while true {
            var value: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &value) { buffer in
                SecRandomCopyBytes(kSecRandomDefault, 4, buffer.baseAddress!)
            }
            if value < bound { return Int(value % UInt32(limit)) }
        }
    }

    private static func pick(from set: [Character]) -> Character {
        set[index(below: set.count)]
    }

    private static func shuffle(_ input: [Character]) -> [Character] {
        var characters = input
        guard characters.count > 1 else { return characters }
        for i in stride(from: characters.count - 1, to: 0, by: -1) {
            characters.swapAt(i, index(below: i + 1))
        }
        return characters
    }

    private static let wordList = [
        "marble", "rickshaw", "cardamom", "lantern", "harbour", "cinnamon", "monsoon", "trellis",
        "walnut", "kestrel", "saffron", "compass", "thicket", "mandarin", "quartz", "verandah",
        "jasmine", "anchor", "tamarind", "meadow", "copper", "sparrow", "banyan", "lagoon",
        "pepper", "sundial", "almond", "cobalt", "papaya", "willow", "ember", "kettle",
        "glacier", "orchid", "pebble", "turmeric", "velvet", "acorn", "bamboo", "canyon"
    ]
}
