import Foundation

/// A value the app believes it found in a document.
struct ExtractedField: Identifiable, Hashable {
    var id = UUID()
    var label: String
    var value: String
    /// 0–1. Anything below `DocumentFieldExtractor.autoFillThreshold` is
    /// offered for review rather than filled in.
    var confidence: Double
    /// The line it came from, so the user can judge it without opening the PDF.
    var evidence: String
    /// True when the document only printed part of the value — `**** 3417`.
    /// A genuine reading, but not the value, so it is never written in on its
    /// own however the caller treats the rest.
    var isMasked: Bool = false
}

/// Pulls policy, loan, card and identity details out of recognised text.
///
/// This is heuristic, and honest about it: Indian insurers and banks lay their
/// documents out however they like. The rule that keeps it safe is that a
/// value is only ever written into a field that is *empty*; anything that would
/// overwrite what you already typed is shown to you first.
///
/// Three ways of finding a value, because documents state them three ways:
///
/// - **Cued** — `Policy No: 12345`. A label introduces the value.
/// - **Vocabulary** — the value is a known term printed somewhere with no
///   label at all: nothing says "Card type: Visa", the page just says `VISA`.
/// - **Pattern** — the value identifies itself by its own shape. An IFSC code,
///   a UPI handle or a PAN is unmistakable wherever it appears.
enum DocumentFieldExtractor {

    /// Below this, a match is proposed but never applied on its own.
    static let autoFillThreshold = 0.75

    static func fields(in text: String, category: ItemCategory) -> [ExtractedField] {
        guard !text.isEmpty else { return [] }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let whole = lines.joined(separator: "\n")

        var found: [ExtractedField] = []

        for rule in rules(for: category) {
            // First rule to claim a label wins, so the precise patterns listed
            // above the cued fallbacks get the first say.
            guard !found.contains(where: { $0.label == rule.label }) else { continue }
            guard let hit = match(rule: rule, lines: lines, whole: whole) else { continue }
            found.append(hit)
        }

        return found
    }

    // MARK: - Rules

    private struct Rule {
        var label: String
        var strategy: Strategy
        var confidence: Double = 0.85
    }

    private enum Strategy {
        /// Words that introduce the value, matched case-insensitively.
        case cued(cues: [String], kind: ValueKind)
        /// Known terms, searched for anywhere in the document. Each entry maps
        /// the forms that appear in print to the one written into the field.
        case vocabulary([(terms: [String], value: String)])
        /// A self-identifying shape, searched for anywhere in the document.
        case pattern(String)
        /// Who the letter is addressed to. Indian correspondence opens "To,"
        /// with the name on the next line and no label anywhere — which is
        /// the only place a welcome letter states the customer's name.
        case addressee
    }

    private enum ValueKind {
        case alphanumeric   // policy / loan / folio numbers
        case money
        case date
        /// The *last* date on the line. "Policy Period From … 30/06/2026 To …
        /// 29/06/2027" carries the start and the end in one run of text.
        case lastDate
        case percentage
        case name
        case phone
        case email
        case freeText
    }

    /// Words that end a name, or that are a heading rather than a value.
    ///
    /// Real documents run a label straight into the next one — "Nominee Name :
    /// Mrs Geetanjali Jain Relationship to Policyholder: Wife" — and without
    /// this the nominee came out as "Name Mrs Geetanjali Jain Relationship".
    private static let labelWords: Set<String> = [
        "relationship", "policy", "policyholder", "holder", "date", "dob", "age",
        "gender", "address", "member", "members", "nominee", "insured", "proposer",
        "name", "details", "no", "number", "code", "contact", "mobile", "email",
        "sum", "premium", "plan", "tier", "issued", "type", "branch", "account"
    ]

    // MARK: Shared vocabularies and shapes

    private static let ifscPattern = "\\b[A-Z]{4}0[A-Z0-9]{6}\\b"
    private static let panPattern = "\\b[A-Z]{5}[0-9]{4}[A-Z]\\b"
    private static let passportPattern = "\\b[A-PR-WY][0-9]{7}\\b"
    private static let aadhaarPattern = "\\b[2-9][0-9]{3}\\s?[0-9]{4}\\s?[0-9]{4}\\b"
    private static let emailPattern = "\\b[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}\\b"
    private static let urlPattern = "\\b(?:https?://)?(?:www\\.)[A-Z0-9.\\-]+\\.[A-Z]{2,}\\b"
    /// Indian mobiles, the 1800/1860 service numbers, and the STD landlines
    /// insurers actually print for their helplines — "022 6158 2020".
    private static let phonePattern =
        "\\b(?:1800|1860)[\\s\\-]?[0-9]{2,4}[\\s\\-]?[0-9]{3,4}(?:[\\s\\-]?[0-9]{1,4})?\\b"
        + "|\\b0[1-9][0-9]{1,3}[\\s\\-][0-9]{3,4}[\\s\\-][0-9]{3,4}\\b"
        + "|\\b(?:\\+?91[\\s\\-]?)?[6-9][0-9]{9}\\b"
    /// A UPI handle, anchored to the payment handles actually in use so it
    /// cannot swallow an ordinary email address sitting on the same page.
    private static let upiPattern =
        "\\b[A-Z0-9.\\-_]{2,}@(?:okhdfcbank|okicici|oksbi|okaxis|ybl|ibl|axl|apl|paytm|upi|hdfcbank|sbi|icici|axisbank|kotak|yesbank|pnb|jupiteraxis|fam|slc|superyes|abfspay)\\b"
    private static let expiryPattern = "\\b(?:0[1-9]|1[0-2])\\s?/\\s?(?:[0-9]{2}|20[0-9]{2})\\b"

    /// Who issued the paper is almost never introduced by a cue — it is the
    /// letterhead. Longer names come first so "State Bank of India" is not
    /// answered by the "Bank of India" sitting inside it.
    private static let bankVocabulary: [(terms: [String], value: String)] = [
        (["state bank of india"], "State Bank of India"),
        (["central bank of india"], "Central Bank of India"),
        (["union bank of india", "union bank"], "Union Bank of India"),
        (["punjab national bank"], "Punjab National Bank"),
        (["bank of baroda"], "Bank of Baroda"),
        (["indian overseas bank"], "Indian Overseas Bank"),
        (["kotak mahindra bank", "kotak mahindra"], "Kotak Mahindra Bank"),
        (["standard chartered"], "Standard Chartered"),
        (["au small finance"], "AU Small Finance Bank"),
        (["idfc first bank", "idfc first"], "IDFC First Bank"),
        (["indusind bank", "indusind"], "IndusInd Bank"),
        (["bandhan bank"], "Bandhan Bank"),
        (["federal bank"], "Federal Bank"),
        (["canara bank"], "Canara Bank"),
        (["indian bank"], "Indian Bank"),
        (["bank of india"], "Bank of India"),
        (["hdfc bank"], "HDFC Bank"),
        (["icici bank"], "ICICI Bank"),
        (["axis bank"], "Axis Bank"),
        (["yes bank"], "Yes Bank"),
        (["rbl bank"], "RBL Bank"),
        (["idbi bank", "idbi"], "IDBI Bank"),
        (["citibank", "citi bank"], "Citibank"),
        (["hsbc"], "HSBC"),
        (["bank of maharashtra"], "Bank of Maharashtra"),
        (["punjab & sind bank", "punjab and sind bank"], "Punjab & Sind Bank"),
        (["jammu & kashmir bank", "j&k bank"], "Jammu & Kashmir Bank"),
        (["tamilnad mercantile"], "Tamilnad Mercantile Bank"),
        (["karnataka bank"], "Karnataka Bank"),
        (["karur vysya"], "Karur Vysya Bank"),
        (["south indian bank"], "South Indian Bank"),
        (["city union bank"], "City Union Bank"),
        (["uco bank"], "UCO Bank"),
        (["dcb bank"], "DCB Bank"),
        (["csb bank"], "CSB Bank"),
        (["equitas"], "Equitas Small Finance Bank"),
        (["ujjivan"], "Ujjivan Small Finance Bank"),
        (["jana small finance"], "Jana Small Finance Bank"),
        (["esaf"], "ESAF Small Finance Bank"),
        (["utkarsh"], "Utkarsh Small Finance Bank"),
        (["suryoday"], "Suryoday Small Finance Bank"),
        (["india post payments"], "India Post Payments Bank"),
        (["airtel payments"], "Airtel Payments Bank"),
        (["paytm payments"], "Paytm Payments Bank"),
        (["fino payments"], "Fino Payments Bank"),
        (["dbs bank"], "DBS Bank"),
        (["deutsche bank"], "Deutsche Bank"),
        (["sbm bank"], "SBM Bank"),
        (["pnb"], "Punjab National Bank"),
        (["sbi"], "State Bank of India")
    ]

    private static let insurerVocabulary: [(terms: [String], value: String)] = [
        (["life insurance corporation", "lic of india"], "LIC"),
        (["icici prudential"], "ICICI Prudential Life"),
        (["icici lombard"], "ICICI Lombard"),
        (["hdfc life"], "HDFC Life"),
        (["hdfc ergo"], "HDFC ERGO"),
        (["sbi general"], "SBI General"),
        (["sbi life"], "SBI Life"),
        (["max life"], "Max Life"),
        (["bajaj allianz"], "Bajaj Allianz"),
        (["tata aia", "tata aig"], "Tata AIA"),
        (["star health"], "Star Health"),
        (["niva bupa", "max bupa"], "Niva Bupa"),
        (["care health", "religare health"], "Care Health"),
        (["new india assurance"], "New India Assurance"),
        (["oriental insurance"], "Oriental Insurance"),
        (["united india insurance"], "United India Insurance"),
        (["national insurance"], "National Insurance"),
        (["aditya birla sun life"], "Aditya Birla Sun Life"),
        (["pnb metlife"], "PNB MetLife"),
        (["kotak life", "kotak mahindra life"], "Kotak Life"),
        (["reliance general"], "Reliance General"),
        (["cholamandalam"], "Cholamandalam"),
        (["bharti axa"], "Bharti AXA"),
        (["royal sundaram"], "Royal Sundaram"),
        (["go digit", "digit insurance"], "Go Digit"),
        (["manipal cigna"], "Manipal Cigna"),
        (["canara hsbc"], "Canara HSBC Life"),
        (["indiafirst"], "IndiaFirst Life"),
        (["ageas federal"], "Ageas Federal Life"),
        (["edelweiss tokio"], "Edelweiss Tokio Life"),
        (["shriram life"], "Shriram Life"),
        (["aditya birla health"], "Aditya Birla Health"),
        (["universal sompo"], "Universal Sompo"),
        (["future generali"], "Future Generali"),
        (["iffco tokio"], "IFFCO Tokio"),
        (["liberty general"], "Liberty General"),
        (["magma hdi"], "Magma HDI"),
        (["raheja qbe"], "Raheja QBE"),
        (["kotak general"], "Kotak General"),
        (["zuno general", "edelweiss general"], "Zuno General"),
        (["acko"], "Acko"),
        (["navi general"], "Navi General"),
        (["pramerica life"], "Pramerica Life"),
        (["aviva life"], "Aviva Life"),
        (["bharti axa life"], "Bharti AXA Life")
    ]

    private static let amcVocabulary: [(terms: [String], value: String)] = [
        (["icici prudential mutual fund", "icici prudential amc"], "ICICI Prudential Mutual Fund"),
        (["aditya birla sun life mutual fund"], "Aditya Birla Sun Life Mutual Fund"),
        (["franklin templeton"], "Franklin Templeton"),
        (["nippon india"], "Nippon India Mutual Fund"),
        (["motilal oswal"], "Motilal Oswal"),
        (["parag parikh", "ppfas"], "Parag Parikh"),
        (["mirae asset"], "Mirae Asset"),
        (["hdfc mutual fund", "hdfc amc"], "HDFC Mutual Fund"),
        (["sbi mutual fund", "sbi funds"], "SBI Mutual Fund"),
        (["axis mutual fund"], "Axis Mutual Fund"),
        (["kotak mutual fund", "kotak mahindra amc"], "Kotak Mutual Fund"),
        (["uti mutual fund", "uti amc"], "UTI Mutual Fund"),
        (["dsp mutual fund"], "DSP Mutual Fund"),
        (["quant mutual fund"], "Quant Mutual Fund")
    ]

    private static let authorityVocabulary: [(terms: [String], value: String)] = [
        (["unique identification authority", "uidai"], "UIDAI"),
        (["income tax department"], "Income Tax Department"),
        (["ministry of external affairs"], "Ministry of External Affairs"),
        (["regional transport office", "transport department"], "Regional Transport Office"),
        (["election commission"], "Election Commission of India"),
        (["mahanagara palike", "municipal corporation", "nagar nigam"], "Municipal Corporation")
    ]

    private static let cardTypeVocabulary: [(terms: [String], value: String)] = [
        (["rupay"], "RuPay"),
        (["mastercard", "master card"], "Mastercard"),
        (["american express", "amex"], "American Express"),
        (["diners club", "diners"], "Diners Club"),
        (["visa"], "Visa"),
        (["credit card"], "Credit card"),
        (["debit card"], "Debit card")
    ]

    private static let policyTypeVocabulary: [(terms: [String], value: String)] = [
        (["term life", "term plan", "term assurance"], "Term life"),
        (["mediclaim", "health insurance", "health policy", "hospitalisation"], "Health"),
        (["private car", "two wheeler", "motor insurance", "own damage"], "Motor"),
        (["travel insurance", "overseas travel"], "Travel"),
        (["home insurance", "householder"], "Home"),
        (["ulip", "unit linked"], "ULIP"),
        (["endowment"], "Endowment"),
        (["money back"], "Money back"),
        (["whole life"], "Whole life"),
        (["personal accident"], "Personal accident"),
        (["life insurance", "life assurance"], "Life")
    ]

    private static let loanTypeVocabulary: [(terms: [String], value: String)] = [
        (["home loan", "housing loan", "home finance"], "Home loan"),
        (["loan against property"], "Loan against property"),
        (["personal loan"], "Personal loan"),
        (["car loan", "auto loan", "vehicle loan"], "Car loan"),
        (["two wheeler loan"], "Two-wheeler loan"),
        (["education loan", "student loan"], "Education loan"),
        (["gold loan"], "Gold loan"),
        (["business loan"], "Business loan"),
        (["overdraft"], "Overdraft")
    ]

    private static let instrumentVocabulary: [(terms: [String], value: String)] = [
        (["fixed deposit", "term deposit"], "Fixed deposit"),
        (["recurring deposit"], "Recurring deposit"),
        (["sukanya samriddhi"], "Sukanya Samriddhi"),
        (["public provident fund", "ppf"], "PPF"),
        (["national pension system", "nps"], "NPS"),
        (["employees provident fund", "epf", "uan"], "EPF"),
        (["national savings certificate", "nsc"], "NSC"),
        (["kisan vikas patra", "kvp"], "KVP"),
        (["mutual fund", "systematic investment", "sip"], "Mutual fund"),
        (["demat", "equity shares"], "Equity"),
        (["debenture", "bond"], "Bonds")
    ]

    private static let identityTypeVocabulary: [(terms: [String], value: String)] = [
        (["aadhaar", "aadhar", "unique identification authority"], "Aadhaar"),
        (["permanent account number", "pan card", "income tax department"], "PAN"),
        (["passport"], "Passport"),
        (["driving licence", "driving license"], "Driving licence"),
        (["voter", "elector", "election commission"], "Voter ID"),
        (["ration card"], "Ration card"),
        (["birth certificate"], "Birth certificate"),
        (["marriage certificate"], "Marriage certificate")
    ]

    private static let documentTypeVocabulary: [(terms: [String], value: String)] = [
        (["sale deed"], "Sale deed"),
        (["lease deed", "rent agreement", "leave and licence"], "Lease / rent agreement"),
        (["will", "testament"], "Will"),
        (["power of attorney"], "Power of attorney"),
        (["warranty", "guarantee card"], "Warranty"),
        (["invoice", "tax invoice", "receipt"], "Invoice / receipt"),
        (["agreement", "contract"], "Agreement"),
        (["certificate"], "Certificate")
    ]

    private static let assetTypeVocabulary: [(terms: [String], value: String)] = [
        (["apartment", "flat"], "Flat"),
        (["independent house", "bungalow"], "House"),
        (["villa", "row house"], "Villa"),
        (["plot"], "Plot"),
        (["agricultural land", "land"], "Land"),
        (["shop", "commercial unit", "office space"], "Commercial"),
        (["locker", "jewellery", "gold"], "Gold / jewellery"),
        (["vehicle", "motor car", "registration certificate"], "Vehicle")
    ]

    private static func rules(for category: ItemCategory) -> [Rule] {
        switch category {
        case .insurance:
            [
                Rule(label: "Policy number", strategy: .cued(cues: ["policy no", "policy number", "policy #", "certificate no"], kind: .alphanumeric), confidence: 0.9),
                Rule(label: "Policy type", strategy: .vocabulary(policyTypeVocabulary), confidence: 0.8),
                Rule(label: "Insurer", strategy: .vocabulary(insurerVocabulary), confidence: 0.85),
                Rule(label: "Insurer", strategy: .cued(cues: ["insurer", "insurance company", "issued by"], kind: .name), confidence: 0.7),
                Rule(label: "Policy holder", strategy: .cued(cues: ["policy holder", "policyholder", "proposer", "insured name", "name of the insured"], kind: .name)),
                Rule(label: "Persons covered", strategy: .cued(cues: ["persons covered", "members covered", "lives assured", "insured members", "no. of members", "relationship to policy holder", "relationship to policyholder"], kind: .freeText), confidence: 0.75),
                Rule(label: "Sum assured / cover", strategy: .cued(cues: ["sum assured", "sum insured", "cover amount", "basic sum assured", "coverage"], kind: .money), confidence: 0.88),
                Rule(label: "Premium amount", strategy: .cued(cues: ["premium amount", "total premium", "instalment premium", "installment premium", "premium payable", "gross premium"], kind: .money), confidence: 0.85),
                Rule(label: "Premium frequency", strategy: .cued(cues: ["premium frequency", "mode of payment", "payment mode", "premium mode"], kind: .freeText), confidence: 0.8),
                Rule(label: "Start date", strategy: .cued(cues: ["date of commencement", "commencement date", "policy start", "risk commencement", "period of insurance from", "policy period from"], kind: .date)),
                Rule(label: "Maturity date", strategy: .cued(cues: ["date of maturity", "maturity date", "policy end", "expiry date", "period of insurance to"], kind: .date)),
                // "Policy Period From … 30/06/2026 To … 29/06/2027" states both
                // ends on one line, so the closing date is the last one on it.
                Rule(label: "Maturity date", strategy: .cued(cues: ["policy period"], kind: .lastDate), confidence: 0.8),
                Rule(label: "Nominee", strategy: .cued(cues: ["nominee", "name of nominee", "nominee name", "beneficiary"], kind: .name), confidence: 0.88),
                // Brokers are "intermediary" on most Indian policy schedules.
                Rule(label: "Agent / advisor", strategy: .cued(cues: ["agent mobile", "agent contact", "advisor contact", "agent name", "intermediary contact", "intermediary name", "intermediary"], kind: .phone), confidence: 0.8),
                Rule(label: "Claim helpline", strategy: .cued(cues: ["toll free", "toll-free", "helpline number", "helpline", "customer care no", "customer care", "call center number", "call centre number", "claim intimation", "contact us"], kind: .phone), confidence: 0.8),
                Rule(label: "Claim helpline", strategy: .pattern(phonePattern), confidence: 0.55)
            ]

        case .loan:
            [
                Rule(label: "Loan account number", strategy: .cued(cues: ["loan account", "loan a/c", "account no", "loan number", "agreement no"], kind: .alphanumeric), confidence: 0.9),
                Rule(label: "Loan type", strategy: .vocabulary(loanTypeVocabulary), confidence: 0.8),
                Rule(label: "Lender", strategy: .vocabulary(bankVocabulary), confidence: 0.85),
                Rule(label: "Lender", strategy: .cued(cues: ["lender", "bank name", "financed by", "issued by"], kind: .name), confidence: 0.7),
                Rule(label: "Borrower", strategy: .cued(cues: ["name of borrower", "borrower name", "applicant name"], kind: .name)),
                Rule(label: "Borrower", strategy: .addressee, confidence: 0.75),
                Rule(label: "Borrower", strategy: .cued(cues: ["borrower"], kind: .name), confidence: 0.7),
                Rule(label: "Principal amount", strategy: .cued(cues: ["loan amount", "sanctioned amount", "principal", "amount financed", "disbursed amount"], kind: .money), confidence: 0.88),
                Rule(label: "Outstanding amount", strategy: .cued(cues: ["outstanding", "balance principal", "principal outstanding"], kind: .money)),
                Rule(label: "Interest rate", strategy: .cued(cues: ["rate of interest", "interest rate", "roi"], kind: .percentage), confidence: 0.85),
                Rule(label: "EMI amount", strategy: .cued(cues: ["emi amount", "monthly instalment", "monthly installment", "emi"], kind: .money), confidence: 0.88),
                Rule(label: "EMI date", strategy: .cued(cues: ["first emi due on", "first emi due", "first emi", "emi due on", "emi date", "due date", "instalment date", "installment date", "repayment date", "monthly due"], kind: .date), confidence: 0.8),
                Rule(label: "Tenure", strategy: .cued(cues: ["tenure", "loan period", "number of instalments", "no. of emis"], kind: .freeText)),
                Rule(label: "Loan end date", strategy: .cued(cues: ["last emi", "loan end", "maturity date", "final instalment"], kind: .date), confidence: 0.75),
                Rule(label: "Debit account", strategy: .cued(cues: ["debit account", "auto debit", "nach", "ecs account", "repayment account"], kind: .alphanumeric), confidence: 0.75),
                Rule(label: "Customer care", strategy: .cued(cues: ["helpline number", "helpline", "toll free", "toll-free", "customer care no", "customer care", "call us on"], kind: .phone), confidence: 0.8),
                // Letters often print the number on its own line above the
                // sentence that names it, so the cue can't reach it.
                Rule(label: "Customer care", strategy: .pattern(phonePattern), confidence: 0.55)
            ]

        case .bankAccount:
            [
                Rule(label: "IFSC code", strategy: .pattern(ifscPattern), confidence: 0.95),
                Rule(label: "IFSC code", strategy: .cued(cues: ["ifsc", "ifs code"], kind: .alphanumeric), confidence: 0.9),
                Rule(label: "UPI ID", strategy: .pattern(upiPattern), confidence: 0.9),
                Rule(label: "Account number", strategy: .cued(cues: ["account no", "a/c no", "ac no", "account number", "account #"], kind: .alphanumeric), confidence: 0.9),
                Rule(label: "Bank", strategy: .vocabulary(bankVocabulary), confidence: 0.85),
                Rule(label: "Bank", strategy: .cued(cues: ["bank name", "issued by", "name of bank"], kind: .name), confidence: 0.7),
                Rule(label: "Branch", strategy: .cued(cues: ["branch name", "home branch", "branch"], kind: .freeText), confidence: 0.75),
                Rule(label: "Account holder", strategy: .cued(cues: ["account holder", "name of account holder", "customer name", "account name"], kind: .name)),
                Rule(label: "Account type", strategy: .cued(cues: ["account type", "scheme", "product name"], kind: .freeText), confidence: 0.7),
                Rule(label: "Customer ID", strategy: .cued(cues: ["customer id", "cif no", "cif", "crn"], kind: .alphanumeric)),
                Rule(label: "Registered mobile", strategy: .cued(cues: ["registered mobile", "mobile no", "mobile number", "registered number"], kind: .phone), confidence: 0.8),
                Rule(label: "Nominee", strategy: .cued(cues: ["nomination", "nominee"], kind: .name), confidence: 0.7)
            ]

        case .investment:
            [
                Rule(label: "Folio / account number", strategy: .cued(cues: ["folio no", "folio number", "account no", "certificate no"], kind: .alphanumeric), confidence: 0.88),
                Rule(label: "Instrument", strategy: .vocabulary(instrumentVocabulary), confidence: 0.8),
                Rule(label: "Institution / AMC", strategy: .vocabulary(amcVocabulary), confidence: 0.85),
                Rule(label: "Institution / AMC", strategy: .vocabulary(bankVocabulary), confidence: 0.82),
                Rule(label: "Institution / AMC", strategy: .cued(cues: ["mutual fund", "amc", "issued by", "bank name"], kind: .name), confidence: 0.7),
                Rule(label: "Held in the name of", strategy: .cued(cues: ["held in the name of", "investor name", "unit holder", "unitholder", "depositor name", "first holder", "account holder"], kind: .name), confidence: 0.8),
                Rule(label: "Amount invested", strategy: .cued(cues: ["amount invested", "investment amount", "deposit amount", "principal"], kind: .money)),
                Rule(label: "Current value", strategy: .cued(cues: ["current value", "maturity amount", "market value"], kind: .money)),
                Rule(label: "Interest / return rate", strategy: .cued(cues: ["rate of interest", "interest rate"], kind: .percentage)),
                Rule(label: "Start date", strategy: .cued(cues: ["date of deposit", "deposit date", "investment date", "start date", "date of investment", "opened on"], kind: .date), confidence: 0.8),
                Rule(label: "Maturity date", strategy: .cued(cues: ["maturity date", "date of maturity"], kind: .date)),
                Rule(label: "Nominee", strategy: .cued(cues: ["nominee", "beneficiary"], kind: .name))
            ]

        case .identity:
            [
                Rule(label: "Document type", strategy: .vocabulary(identityTypeVocabulary), confidence: 0.85),
                Rule(label: "Document number", strategy: .pattern(panPattern), confidence: 0.9),
                Rule(label: "Document number", strategy: .pattern(aadhaarPattern), confidence: 0.8),
                Rule(label: "Document number", strategy: .pattern(passportPattern), confidence: 0.78),
                Rule(label: "Document number", strategy: .cued(cues: ["number", "no.", "id no", "licence no", "license no", "passport no"], kind: .alphanumeric), confidence: 0.7),
                Rule(label: "Name on document", strategy: .cued(cues: ["name"], kind: .name), confidence: 0.65),
                Rule(label: "Date of birth", strategy: .cued(cues: ["date of birth", "dob"], kind: .date), confidence: 0.9),
                Rule(label: "Issued on", strategy: .cued(cues: ["date of issue", "issued on", "issue date"], kind: .date)),
                Rule(label: "Valid until", strategy: .cued(cues: ["valid until", "valid upto", "date of expiry", "expiry", "valid till"], kind: .date), confidence: 0.88),
                Rule(label: "Issuing authority", strategy: .vocabulary(authorityVocabulary), confidence: 0.85),
                Rule(label: "Issuing authority", strategy: .cued(cues: ["issuing authority", "issued by", "authority"], kind: .name), confidence: 0.7)
            ]

        case .document:
            // Same paperwork as `.identity`, but a different template: this one
            // asks for "Issued by" and "In the name of", so the labels have to
            // match those or the values land in invented extra fields.
            [
                Rule(label: "Document type", strategy: .vocabulary(documentTypeVocabulary), confidence: 0.8),
                Rule(label: "Reference number", strategy: .cued(cues: ["reference no", "ref no", "certificate no", "registration no", "document no", "serial no"], kind: .alphanumeric), confidence: 0.8),
                Rule(label: "Issued by", strategy: .cued(cues: ["issued by", "issuing authority", "authority", "registrar"], kind: .name), confidence: 0.75),
                Rule(label: "Issued by", strategy: .vocabulary(authorityVocabulary), confidence: 0.8),
                Rule(label: "In the name of", strategy: .cued(cues: ["in the name of", "name of", "issued to", "name"], kind: .name), confidence: 0.65),
                Rule(label: "Issued on", strategy: .cued(cues: ["date of issue", "issued on", "issue date", "dated"], kind: .date)),
                Rule(label: "Valid until", strategy: .cued(cues: ["valid until", "valid upto", "date of expiry", "expiry", "valid till"], kind: .date), confidence: 0.88)
            ]

        case .card:
            // A card *statement* is a different document from the card itself.
            // It never prints the full number, the CVV or the PIN — but it does
            // carry the things that are tedious to type and easy to forget.
            [
                Rule(label: "Card type", strategy: .vocabulary(cardTypeVocabulary), confidence: 0.8),
                Rule(label: "Issuer", strategy: .vocabulary(bankVocabulary), confidence: 0.85),
                Rule(label: "Issuer", strategy: .cued(cues: ["issued by", "bank name", "statement from"], kind: .name), confidence: 0.7),
                Rule(label: "Name on card", strategy: .cued(cues: ["name on card", "card member", "cardmember", "customer name"], kind: .name), confidence: 0.8),
                Rule(label: "Card number", strategy: .cued(cues: ["card no", "card number", "credit card number", "account number"], kind: .alphanumeric), confidence: 0.8),
                Rule(label: "Expiry (MM/YY)", strategy: .cued(cues: ["valid thru", "valid through", "expires end", "expiry date", "valid upto"], kind: .freeText), confidence: 0.85),
                Rule(label: "Expiry (MM/YY)", strategy: .pattern(expiryPattern), confidence: 0.6),
                Rule(label: "Credit limit", strategy: .cued(cues: ["total credit limit", "credit limit", "sanctioned limit"], kind: .money), confidence: 0.9),
                Rule(label: "Statement date", strategy: .cued(cues: ["statement date", "statement generated on", "bill date"], kind: .date), confidence: 0.88),
                Rule(label: "Payment due date", strategy: .cued(cues: ["payment due date", "due date", "pay by"], kind: .date), confidence: 0.9),
                Rule(label: "Customer care", strategy: .cued(cues: ["customer care", "toll free", "toll-free", "helpline", "contact us"], kind: .phone), confidence: 0.8),
                Rule(label: "Customer care", strategy: .pattern(phonePattern), confidence: 0.55),
                Rule(label: "Linked bank account", strategy: .cued(cues: ["auto debit", "linked account", "debit account"], kind: .alphanumeric), confidence: 0.6)
            ]

        case .property:
            [
                Rule(label: "Asset type", strategy: .vocabulary(assetTypeVocabulary), confidence: 0.8),
                Rule(label: "Registration / document number", strategy: .cued(cues: ["registration no", "document no", "deed no", "survey no", "khata no", "registration number"], kind: .alphanumeric), confidence: 0.85),
                Rule(label: "Owner", strategy: .cued(cues: ["owner", "purchaser", "vendee", "transferee", "in favour of", "buyer"], kind: .name), confidence: 0.75),
                Rule(label: "Purchase date", strategy: .cued(cues: ["date of registration", "date of purchase", "executed on", "dated", "date of sale"], kind: .date), confidence: 0.8),
                Rule(label: "Purchase value", strategy: .cued(cues: ["consideration", "sale consideration", "purchase price", "market value", "agreement value"], kind: .money), confidence: 0.8),
                Rule(label: "Current value", strategy: .cued(cues: ["current value", "present value", "guidance value", "circle rate"], kind: .money), confidence: 0.7),
                Rule(label: "Description", strategy: .cued(cues: ["schedule of property", "property description", "situated at", "address of property"], kind: .freeText), confidence: 0.65)
            ]

        case .login:
            [
                Rule(label: "Website / app", strategy: .pattern(urlPattern), confidence: 0.8),
                Rule(label: "Registered email", strategy: .pattern(emailPattern), confidence: 0.85),
                Rule(label: "Registered mobile", strategy: .cued(cues: ["registered mobile", "mobile no", "mobile number"], kind: .phone), confidence: 0.8),
                Rule(label: "Username", strategy: .cued(cues: ["username", "user id", "user name", "login id", "customer id"], kind: .freeText), confidence: 0.75)
            ]

        case .note:
            []
        }
    }

    // MARK: - Matching

    private static func match(rule: Rule, lines: [String], whole: String) -> ExtractedField? {
        switch rule.strategy {
        case .cued(let cues, let kind):
            return firstCuedMatch(rule: rule, cues: cues, kind: kind, lines: lines)
        case .vocabulary(let entries):
            return vocabularyMatch(rule: rule, entries: entries, whole: whole)
        case .pattern(let pattern):
            return patternMatch(rule: rule, pattern: pattern, lines: lines, whole: whole)
        case .addressee:
            return addresseeMatch(rule: rule, lines: lines)
        }
    }

    /// The name under a letter's "To,".
    private static func addresseeMatch(rule: Rule, lines: [String]) -> ExtractedField? {
        // Only the opening of the letter — a "To" further down is part of a
        // sentence, not an address block.
        for (index, line) in lines.prefix(12).enumerated() {
            let bare = line.trimmingCharacters(in: CharacterSet(charactersIn: " ,:.")).lowercased()
            guard bare == "to" else { continue }
            guard index + 1 < lines.count,
                  let value = value(from: lines[index + 1], kind: .name)
            else { continue }
            return field(rule: rule, value: value, confidence: rule.confidence, evidence: "\(line) → \(lines[index + 1])")
        }
        return nil
    }

    private static func firstCuedMatch(rule: Rule, cues: [String], kind: ValueKind, lines: [String]) -> ExtractedField? {
        for (index, line) in lines.enumerated() {
            // Whole-word only: "emi" must not be answered by "PREMIER".
            // Longest cue first, so "nominee name" claims the line ahead of
            // the bare "nominee" and the value starts after the whole label.
            guard let hit = TextMatching.firstMatch(of: cues.sorted { $0.count > $1.count }, in: line) else { continue }

            // Value on the same line, after the cue and any separator…
            if let tail = trailing(of: line, after: hit.range),
               let value = value(from: tail, kind: kind),
               let match = field(rule: rule, value: value, confidence: rule.confidence, evidence: line) {
                return match
            }
            // …or on the line below, which is how tables usually come out of
            // OCR. A next line carrying its own `Label: value` is skipped: it
            // is the next field, not this one's value. Without that guard
            // "Lives Assured: 2" reached past its own short value and took
            // "Basic Sum Assured: Rs. 1,00,00,000" as the persons covered.
            // A name taken off the next line is only safe when the cue really
            // is a table label — i.e. nothing follows it on its own line.
            // Otherwise a sentence mentioning "the Borrower(S) as issued in
            // favour of…" reaches into the following line and files whatever
            // it starts with as somebody's name. Money, dates and phone
            // numbers are shape-checked, so they keep the looser fallback.
            let labelEndsLine = kind != .name || isLabelOnly(line, after: hit.range)
            if index + 1 < lines.count,
               labelEndsLine,
               !lines[index + 1].contains(":"),
               let value = value(from: lines[index + 1], kind: kind),
               let match = field(
                   rule: rule,
                   value: value,
                   confidence: max(rule.confidence - 0.15, 0.4),
                   evidence: "\(line) → \(lines[index + 1])"
               ) {
                return match
            }
            // A rejected candidate (e.g. a "Card number" that fails Luhn)
            // doesn't end the search — a later, better line still might work.
        }
        return nil
    }

    /// The document says `VISA` somewhere and nothing introduces it. Longest
    /// terms are tried first within each entry so "two wheeler loan" is not
    /// beaten to the answer by a bare "loan".
    private static func vocabularyMatch(
        rule: Rule,
        entries: [(terms: [String], value: String)],
        whole: String
    ) -> ExtractedField? {
        for entry in entries {
            let ordered = entry.terms.sorted { $0.count > $1.count }
            for term in ordered where TextMatching.contains(term, in: whole) {
                let evidence = line(containing: term, in: whole) ?? term
                return field(rule: rule, value: entry.value, confidence: rule.confidence, evidence: evidence)
            }
        }
        return nil
    }

    /// A shape that needs no cue: an IFSC code is an IFSC code wherever it sits.
    private static func patternMatch(rule: Rule, pattern: String, lines: [String], whole: String) -> ExtractedField? {
        guard let value = firstMatch(in: whole, pattern: pattern) else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespaces)
        let evidence = lines.first { $0.localizedCaseInsensitiveContains(cleaned) } ?? cleaned
        return field(rule: rule, value: cleaned, confidence: rule.confidence, evidence: evidence)
    }

    private static func line(containing term: String, in whole: String) -> String? {
        whole
            .components(separatedBy: .newlines)
            .first { $0.localizedCaseInsensitiveContains(term) }?
            .trimmingCharacters(in: .whitespaces)
    }

    /// Statements print numbers half-hidden — `XXXXXXXX3417`, `**** 3417`.
    /// That is a genuine reading of the document, but it is not the number, so
    /// it is knocked down below the auto-fill line and shows up for review with
    /// the reason attached rather than quietly becoming your card number.
    ///
    /// A card number that *isn't* masked is a separate risk: a statement
    /// should never print one in full, so a "full" 13–19 digit read here is
    /// far more likely a misread than a genuine, PCI-violating printout —
    /// unlike `CardScanner`, nothing upstream of this has checked its
    /// checksum. Run the same Luhn test the plastic-card path trusts, and
    /// discard rather than offer a candidate that fails it, so a bad OCR read
    /// on a statement can't get auto-filled into a card number that's wrong.
    private static func field(rule: Rule, value: String, confidence: Double, evidence: String) -> ExtractedField? {
        if isMasked(value) {
            return ExtractedField(
                label: rule.label,
                value: value,
                confidence: min(confidence, 0.45),
                evidence: "\(evidence)  ·  partly hidden on the statement",
                isMasked: true
            )
        }
        if rule.label == "Card number" {
            let digits = value.filter(\.isNumber)
            if (13...19).contains(digits.count), !CardScanner.passesLuhn(digits) {
                return nil
            }
        }
        return ExtractedField(label: rule.label, value: value, confidence: confidence, evidence: evidence)
    }

    private static func isMasked(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.contains("****") || lowered.contains("••••") { return true }
        // Three or more consecutive masking-style characters — x's, stars or
        // bullets — is masking, not a real identifier. OCR renders the same
        // masked run inconsistently (mixed case, dots vs. stars, a stray
        // "0" for a smudged glyph), so this checks for a run of any of the
        // characters actually seen on statements rather than one exact string.
        return lowered.range(of: "[x*•●]{3,}", options: .regularExpression) != nil
    }

    /// True when nothing but punctuation follows the cue on its own line.
    private static func isLabelOnly(_ line: String, after cueRange: Range<String.Index>) -> Bool {
        let rest = line[cueRange.upperBound...]
        return rest.allSatisfy { !$0.isLetter && !$0.isNumber }
    }

    private static func trailing(of line: String, after cueRange: Range<String.Index>) -> String? {
        var tail = String(line[cueRange.upperBound...])
        tail = tail.trimmingCharacters(in: CharacterSet(charactersIn: " :\t-–—=.#"))
        return tail.isEmpty ? nil : tail
    }

    private static func value(from text: String, kind: ValueKind) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        switch kind {
        case .alphanumeric:
            // At least six characters of number-ish identifier. The class
            // also admits `*`/`•` at the edges (not just in the middle) so a
            // wholly-masked run like "****3417" — with no letters to anchor
            // on, only the four trailing digits — is captured as one token
            // rather than falling below the minimum length and vanishing
            // before `isMasked` ever gets a chance to see it and demote it.
            guard let match = firstMatch(in: trimmed, pattern: "[A-Z0-9*•][A-Z0-9\\-/ *•]{5,29}[A-Z0-9*•]") else { return nil }
            let cleaned = match.trimmingCharacters(in: .whitespaces)
            return cleaned.contains(where: \.isNumber) ? cleaned : nil

        case .money:
            // The amount is captured on its own, away from the currency word.
            // Filtering the whole match down to "digits and dots" instead
            // keeps the full stop out of "Rs." and turns 24,500.00 into
            // ".24500" — a leading-dot value that looked like a number and
            // was written straight into the field.
            guard let match = firstMatch(
                in: trimmed,
                pattern: "(?:₹|rs\\.?|inr)?\\s?([0-9][0-9,]{2,}(?:\\.[0-9]{1,2})?)",
                group: 1
            ) else { return nil }
            let digits = match.filter { $0.isNumber || $0 == "." }
            guard let amount = Decimal(string: digits), amount > 0 else { return nil }
            return digits.hasSuffix(".00") ? String(digits.dropLast(3)) : digits

        case .percentage:
            guard let match = firstMatch(in: trimmed, pattern: "[0-9]{1,2}(?:\\.[0-9]{1,2})?\\s?%?") else { return nil }
            let cleaned = match.trimmingCharacters(in: .whitespaces)
            return cleaned.hasSuffix("%") ? cleaned : cleaned + "%"

        case .date, .lastDate:
            return dateValue(in: trimmed, takingLast: kind == .lastDate)

        case .name:
            // A name is capitalised and made of letters, and it ends where the
            // next label begins. Requiring capitals is what stops a sentence
            // fragment — "to modify the eKYC ID", "details have been updated"
            // — being filed as somebody's name.
            var words: [String] = []
            for raw in trimmed.split(separator: " ") {
                let bare = String(raw).trimmingCharacters(in: CharacterSet.letters.inverted)
                guard !bare.isEmpty,
                      bare.allSatisfy(\.isLetter),
                      !labelWords.contains(bare.lowercased()),
                      let initial = bare.first,
                      initial.isUppercase
                else { break }
                words.append(bare)
                if words.count == 5 { break }
            }
            guard words.count >= 2 else { return nil }
            return words.joined(separator: " ")

        case .phone:
            guard let match = firstMatch(in: trimmed, pattern: phonePattern) else { return nil }
            return match.trimmingCharacters(in: .whitespaces)

        case .email:
            guard let match = firstMatch(in: trimmed, pattern: emailPattern) else { return nil }
            return match.trimmingCharacters(in: .whitespaces)

        case .freeText:
            // "Tenure (months) 180" puts the unit between the label and the
            // value. Read as-is it becomes "(months) 180"; the unit belongs
            // after the number, where a person would write it.
            if let unit = firstMatch(in: trimmed, pattern: "^\\(([A-Za-z]{1,12})\\)\\s*(.+)$", group: 1),
               let rest = firstMatch(in: trimmed, pattern: "^\\(([A-Za-z]{1,12})\\)\\s*(.+)$", group: 2) {
                return String("\(rest) \(unit)".prefix(60))
            }
            let value = String(trimmed.prefix(60))
            // A bare count — "Lives assured: 2" — is a legitimate one-character
            // answer, so digits are kept where a single letter would not be.
            if value.count == 1 { return value.allSatisfy(\.isNumber) ? value : nil }
            guard value.count >= 2 else { return nil }
            // "Insured Person Details" is a heading with the word "Details"
            // after the cue, not a value. A lone label word is not an answer.
            let bare = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
            return labelWords.contains(bare) ? nil : value
        }
    }

    /// The first — or last — date on a line, across every format we read.
    private static func dateValue(in text: String, takingLast: Bool) -> String? {
        let patterns = [
            "[0-9]{1,2}[/\\-\\.][0-9]{1,2}[/\\-\\.][0-9]{2,4}",
            // "05-SEP-2026", "31-JUL-26" — a named month joined by hyphens or
            // slashes rather than spaces, which is how loan schedules print it.
            "[0-9]{1,2}[\\-/\\s][A-Za-z]{3,9}[\\-/\\s][0-9]{2,4}",
            "[0-9]{1,2}\\s+[A-Za-z]{3,9}\\s+[0-9]{4}",
            "[A-Za-z]{3,9}\\s+[0-9]{1,2},?\\s+[0-9]{4}"
        ]

        var best: (position: String.Index, value: String)?
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let whole = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, options: [], range: whole) {
                guard let range = Range(match.range, in: text) else { continue }
                let value = String(text[range])
                guard let current = best else {
                    best = (range.lowerBound, value)
                    continue
                }
                let wins = takingLast
                    ? range.lowerBound > current.position
                    : range.lowerBound < current.position
                if wins { best = (range.lowerBound, value) }
            }
        }
        return best?.value
    }

    private static func firstMatch(in text: String, pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              group < match.numberOfRanges,
              let matchRange = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[matchRange])
    }
}
