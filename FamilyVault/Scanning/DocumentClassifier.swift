import Foundation

/// Works out what a document *is*, so one scan can go straight into the right
/// kind of entry without being told.
///
/// Deliberately simple and inspectable: each category carries the words that
/// only really appear on that kind of paperwork, every hit scores, and the
/// highest score wins. Weighted terms carry the decisive ones — "sum assured"
/// says insurance far more strongly than the word "premium", which turns up on
/// a card statement too.
///
/// It reports how sure it is. A confident read can create an entry outright; a
/// weak one should be shown to the user before anything is filed under a guess.
enum DocumentClassifier {

    struct Verdict {
        var category: ItemCategory
        /// 0–1, from how far the winner pulled ahead of the runner-up.
        var confidence: Double
        /// The terms that decided it, for showing your working.
        var matched: [String]

        /// Below this, the guess is worth confirming rather than acting on.
        var isConfident: Bool { confidence >= DocumentClassifier.confidenceThreshold }
    }

    static let confidenceThreshold = 0.55

    /// Terms that point at one category, and how much each is worth.
    private static let signals: [ItemCategory: [(term: String, weight: Double)]] = [
        .insurance: [
            ("sum assured", 4), ("sum insured", 4), ("policy no", 3), ("policy number", 3),
            ("premium", 2), ("policyholder", 3), ("policy holder", 3), ("nominee", 1),
            ("date of commencement", 3), ("insurance", 2), ("insurer", 3), ("lives assured", 3),
            ("maturity date", 1), ("mediclaim", 4), ("proposer", 3), ("claim", 1)
        ],
        .card: [
            ("credit limit", 4), ("statement date", 3), ("payment due date", 4),
            ("minimum amount due", 4), ("total amount due", 3), ("cardmember", 4),
            ("card member", 4), ("card no", 2), ("available credit", 3), ("reward points", 2),
            ("credit card", 3), ("debit card", 2),
            // The card itself, not a statement about it. A plastic card carries
            // almost no words — the network, "valid thru" and a name — so these
            // have to be enough on their own to place it.
            ("valid thru", 4), ("valid through", 4), ("valid from", 3), ("expires end", 3),
            ("cardholder", 4), ("card holder", 4), ("member since", 3),
            ("mastercard", 4), ("rupay", 4), ("american express", 4), ("amex", 4),
            ("diners club", 4),
            // Lower than the rest: "visa" is also a travel document, and a visa
            // page says "passport" loudly enough to win on identity.
            ("visa", 3)
        ],
        .bankAccount: [
            ("ifsc", 4), ("account holder", 2), ("savings account", 4), ("current account", 3),
            ("passbook", 4), ("branch", 1), ("customer id", 2), ("cif", 2), ("upi", 2),
            ("account statement", 2), ("opening balance", 3), ("closing balance", 3)
        ],
        .loan: [
            ("emi", 4), ("loan account", 4), ("sanction", 3), ("rate of interest", 2),
            ("borrower", 3), ("disbursed", 3), ("amortisation", 3), ("amortization", 3),
            ("principal outstanding", 4), ("tenure", 2), ("loan amount", 3), ("repayment", 2)
        ],
        .investment: [
            ("folio", 4), ("mutual fund", 4), ("fixed deposit", 4), ("term deposit", 3),
            ("nav", 2), ("units", 2), ("maturity amount", 3), ("depositor", 3),
            ("systematic investment", 4), ("ppf", 3), ("nps", 3), ("demat", 3),
            ("amount invested", 3), ("recurring deposit", 4)
        ],
        .identity: [
            ("aadhaar", 5), ("aadhar", 5), ("permanent account number", 5), ("pan card", 5),
            ("passport", 4), ("driving licence", 5), ("driving license", 5),
            ("date of birth", 2), ("government of india", 2), ("govt. of india", 2),
            ("elector", 4), ("voter", 4), ("unique identification", 5)
        ],
        .property: [
            ("sale deed", 5), ("sub registrar", 4), ("survey no", 3), ("khata", 4),
            ("schedule of property", 4), ("sale consideration", 4), ("vendee", 4),
            ("vendor", 2), ("built up area", 3), ("carpet area", 3), ("plot no", 3),
            ("encumbrance", 4), ("registration no", 1)
        ],
        .document: [
            ("certificate", 3), ("agreement", 2), ("this deed", 2), ("witness", 2),
            ("registrar", 2), ("issued by", 1), ("power of attorney", 4), ("affidavit", 4),
            ("warranty", 3), ("invoice", 3), ("receipt", 2)
        ],
        .login: [
            ("username", 3), ("password", 3), ("login id", 3), ("two-factor", 3),
            ("backup codes", 4)
        ]
    ]

    /// Categories with no document form of their own. A scan is never filed as
    /// one of these, so they are left out of scoring entirely.
    private static let notScannable: Set<ItemCategory> = [.note]

    static func classify(_ text: String) -> Verdict? {
        guard !text.isEmpty else { return nil }

        var scores: [(category: ItemCategory, score: Double, matched: [String])] = []

        for category in ItemCategory.allCases where !notScannable.contains(category) {
            guard let terms = signals[category] else { continue }
            var score = 0.0
            var matched: [String] = []
            // Whole words only. As a substring search, "emi" fired on "PREMIER"
            // and sent a scanned credit card into a loan entry.
            for signal in terms where TextMatching.contains(signal.term, in: text) {
                score += signal.weight
                matched.append(signal.term)
            }
            if score > 0 { scores.append((category, score, matched)) }
        }

        guard let best = scores.max(by: { $0.score < $1.score }) else { return nil }

        // A document that only trips one weak signal is not identified, it is
        // merely touched. Two points is one strong term or two soft ones.
        guard best.score >= 4 else {
            return Verdict(category: best.category, confidence: 0.3, matched: best.matched)
        }

        // Confidence is the margin over the runner-up, not the raw score: a
        // long document trips more terms without being any more certain, and
        // what actually matters is whether anything else came close.
        let runnerUp = scores
            .filter { $0.category != best.category }
            .map(\.score)
            .max() ?? 0
        let margin = (best.score - runnerUp) / best.score
        let confidence = min(0.95, 0.5 + margin * 0.5)

        return Verdict(category: best.category, confidence: confidence, matched: best.matched)
    }
}
