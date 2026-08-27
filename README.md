# Vault — a private financial record book for two iPhones

A native iOS app that keeps bank accounts, cards, insurance policies,
investments, loans, identity documents and logins in one place, shared between
exactly two phones — yours and your wife's — and readable by nobody else.

Nothing here is stored on anyone's server. iCloud carries the data between the
two phones, but only as ciphertext: the key is derived from a master passphrase
that never leaves your devices, so Apple (or anyone who obtains the iCloud
account) sees nothing but noise.

---

## What it does

### Records

Nine categories, each with a ready-made form so you fill in blanks instead of
inventing them:

| Category | Fields it starts with |
| --- | --- |
| Bank Accounts | account number, IFSC, branch, customer ID, net-banking and transaction passwords, UPI ID, nominee |
| Cards | card number, expiry, CVV, PIN, credit limit, statement and due dates, customer care |
| Insurance | policy number, cover, premium and frequency, start/maturity dates, nominee, agent, claim helpline |
| Investments | FD/RD/MF/PPF/NPS folio, amount, current value, rate, maturity, nominee |
| Loans & EMIs | loan account, principal, outstanding, rate, EMI amount and date, tenure |
| Identity Documents | PAN, Aadhaar, passport, licence — number, issue/expiry, authority |
| Logins | site, username, password, registered email/mobile, 2FA backup codes |
| Property & Assets | registration number, purchase value, where the papers are kept, locker details |
| Personal Documents | any paperwork that belongs to no account — certificates, agreements, records |
| Secure Notes | anything else |

- Every field can be renamed, removed or added to, and any new field can be
  marked secret so it stays masked until tapped.
- **Belongs to** — tag each entry as yours, your wife's, or joint, then filter
  any list by person with one tap. New entries inherit whichever filter you're
  looking at.
- **Pin** the handful you reach for constantly to the top of the home screen.
- **Sort** any category by name, most recently changed, or what's due next.
- Each entry records **who changed it last and when** — "last changed 3 Aug on
  Priya's iPhone" — so a surprise edit has an explanation.

### Documents & scanning

Attach photos and PDFs to any entry — and scan straight from the camera.

Four ways in, from the **Scan document** button and the **Add** menu on any entry:

- **Scan document** uses Apple's document camera: edge detection, perspective
  correction, multi-page. The pages become one PDF, compressed to a few
  hundred KB rather than the 8 MB a raw scan costs. Right for paperwork.
- **Take a photo** is the plain camera, with a crop step, and what it saves
  stays a photo. Right for the things that aren't paperwork — the locker key,
  a dented bumper for a motor claim, the boundary of a plot.
- **Choose from Photos** takes up to five images from the camera roll.
- **Choose a PDF or file** takes a PDF or anything else from Files, iCloud
  Drive, Google Drive, WhatsApp — wherever the insurer's email put it.
- **Personal Documents** is its own category for paperwork that belongs to no
  particular account — a degree certificate, the rent agreement, medical
  records.
- **The Documents library** lists every file in the vault in one place,
  filterable by category and searchable by file name *or by the text inside*.
  Swipe any row to send it on — to an insurer, a bank, an accountant.
- Encrypted with the same key as everything else. What iCloud stores is the
  ciphertext file, byte for byte.
- Viewed **inside** the app — PDFs and images are decrypted into memory and
  rendered from there, so a readable copy only ever hits disk at the moment
  you explicitly share one.
- 20 MB per file; larger ones are refused rather than silently truncated.

### Reading a document into the fields

Add a policy bond or a loan sanction letter and Vault reads it on the phone —
the embedded text layer if the PDF has one, Apple's on-device OCR if it
doesn't — then fills in what it recognises: policy or loan number, insurer or
lender, sum assured, premium, EMI, interest rate, dates, nominee, helpline.

**Scan a card** and the same machinery reads the number, expiry, name and
network off the plastic. The card number is checked against the Luhn checksum
that every real card satisfies, so an OCR misread is discarded rather than
saved — and the photograph itself is deliberately *not* kept, because storing
a picture of the card next to its CVV would put both in one place for nothing.

Three rules make this safe rather than merely clever:

1. **A value is only written on its own into a field that is empty.** Anything
   that would overwrite what you typed is shown to you first, with the
   document's version and yours side by side.
2. **Anything the parser isn't confident about is proposed, never applied** —
   listed under "not sure about these", with the line it came from as evidence.
3. **Everything applied can be undone in one tap**, from the review sheet.

**Statements are a different document from the thing they're about.** A bank
statement carries the account number, IFSC, branch, holder and customer ID —
most of what that entry needs. A credit card statement carries the issuer,
credit limit, statement and due dates and the customer care number, but it
prints the card number **half-hidden** (`XXXXXXXX3417`) and never prints the
CVV or PIN at all. Masked values are recognised as masked: they drop below the
auto-fill line and appear for review with "partly hidden on the statement"
attached, rather than quietly becoming your card number. Only scanning the
plastic gives you the full number.

Neither imports **transactions**. This is a record book, not an expense
tracker — a statement's line items go stale in a month and would bury the
things that don't.

Be realistic about the accuracy: Indian insurers and banks lay documents out
however they like, and OCR on a phone photo is imperfect. Expect a good policy
PDF to fill most fields and a crumpled photocopy to fill few. The design above
is what makes a bad read a minor annoyance instead of corrupted records.

### What a policy actually gives you

Policies, loans and investments get a plain-language summary at the top of the
entry, assembled automatically:

> **Pays ₹25,00,000 to Priya Jain**
> · Priya Jain receives ₹25,00,000 on a valid claim.
> · Costs ₹42,318 yearly.
> · Next premium due 14 Sep 2026.
> · To claim, call 1800 425 9876 at LIC.
> · Includes an accidental death benefit. *(from the attached document)*

Lines drawn from the attached document are marked as such, so they're never
mistaken for something that was checked and typed in. The whole summary can be
shared as text — for the person who has to act on the policy and was never the
one who bought it.

### Knowing what you've got

- **At a glance** — total life and health cover, premiums per year and per
  month, amount invested vs. current value, outstanding borrowings, monthly EMI
  outgo, and total credit limit. Built entirely from the amounts you typed;
  nothing is fetched from any bank. Monthly, quarterly and half-yearly premiums
  are normalised to a yearly figure so the total means something. Understands
  "5L" and "1.2 Cr" as well as "500000". Once there are two months of history,
  a **net worth over time** chart appears above the totals — investments at
  current value minus loans outstanding, recorded once a month straight from
  what's in the vault, with nothing new to type in.
- **Check-up** — a standing audit that surfaces what quietly rots:
  - renewals and EMIs that have already lapsed,
  - anything due in the next 30 days,
  - cards past (or two months from) their expiry,
  - identity documents past their validity,
  - policies, investments and accounts with **no nominee recorded**,
  - weak passwords, and the same password used across several logins,
  - the **same account or policy number entered twice**, usually a sign an
    import or a scan created a duplicate rather than updating the original.

### Reminders

Bank loans, insurance premiums and card bills don't come round once — so
reminders repeat. Set the first due date and a cadence (**monthly**,
quarterly, half-yearly, **yearly**, or once), choose how far ahead you want
telling, and the app takes it from there. New loans and cards default to
monthly, policies to yearly.

Notifications name what's due and whose it is:

> **HDFC Bank EMI due in 3 days**
> Home loan
> Priya · ₹45,000 · due 5 Sep

The bank or insurer comes from the entry's Lender / Insurer / Issuer field,
the person from its **Belongs to** tag, and the amount from EMI or premium.
Anything missing is simply left out.

That detail is readable on the lock screen, which is the point — and also the
trade-off. **Settings → Notifications** has a switch to fall back to a discreet
*"An EMI is due soon"* with no names or amounts, and shows you a preview of
your own next reminder either way, so the choice is made by looking at it.

The same screen handles permission: it asks the first time, tells you plainly
if iOS is blocking notifications, and links straight to the system setting that
fixes it. The app icon carries a badge for anything already overdue.

Dates roll forward on their own. A monthly EMI due on the 5th keeps reading
"overdue" for a week afterwards, then moves to next month — and the 31st lands
on the last day of a short month rather than drifting into the next one.

*Under the hood:* iOS holds at most 64 pending local notifications per app, so
Vault schedules the 60 soonest across every entry and rebuilds that list each
time you open it. A handful of monthly EMIs covers well over a year ahead.
Reminders are marked time-sensitive; to have iOS honour that during a Focus,
add the **Time Sensitive Notifications** capability in Xcode.

### Payments

Loans, policies and cards get a **Mark this one as paid** button on the due
card. Recording a payment logs the amount, the date and which phone entered it
— and the reminder moves on to the next instalment by itself, so nothing has to
be re-dated by hand. The entry keeps its payment history; removing a record
puts the due date back.

### Cross-cutting views

Records are filed by category, but the useful questions cut across it:

- **Year ahead** — every premium, EMI, bill and maturity for the next twelve
  months, grouped by month, with each month's total where the amounts are
  known. The answer to "what does the year cost?"
- **Important numbers** — every phone number in the vault on one screen, tap to
  call, message or WhatsApp. The moment you need a claim helpline is the moment
  you least want to be hunting for it.
- **Nominees** — who inherits what, roughly how much, and — listed first —
  **what has nobody named on it**. A missing nominee is the most expensive
  blank in this app: it turns a claim into a court matter.
- **Tags** — free-form labels that ignore categories: "tax saving", "Dad",
  "review in April".
- **Recent activity** — what changed, when, and on which phone. In a vault two
  people share, this is how you notice your partner rotated the net-banking
  password without being told.

Phone, email and website fields are tappable everywhere they appear — a
helpline you have to copy-paste into the dialler is a helpline you won't use.

### History

Every entry keeps a log: created, edited, paid, document added, deleted,
restored — each stamped with the time and the phone it came from. Edits record
*which fields* moved, never their values, so the log never becomes a second
copy of the secrets.

### Getting things in (and out)

- **Spreadsheet import** — point it at a CSV whose first row is column names
  and each row becomes an entry. Columns matching a category's own fields
  ("Policy number", "CVV") arrive already marked secret, and anything else that
  looks sensitive is marked secret too. Retyping forty policies by thumb is why
  apps like this get abandoned in week one.
- **Spreadsheet export** — the same in reverse, with secrets masked by default.
  It's plain text with no password on it, so the unmasked option carries a
  warning and the encrypted backup remains the copy worth keeping.
- **Payments and activity as CSV** — two narrower exports alongside the full
  one: every payment you've logged (for reconciling against a bank statement),
  and the full change log (for reviewing who did what, and when).
- **Documents can be shared** out of the viewer — a policy PDF you can't send
  to the insurer isn't much use.

### Finding things

One search box across every entry — insurer, nominee, the last four digits of a
card, an agent's name, even an attachment's filename — plus a scoped search
inside each category.

### Passwords

A generator built on the system's cryptographic random source, with length,
capitals, digits, symbols, and an option to avoid look-alike characters
(l/I/1/O/0) so a password can be read aloud. Reachable from the dice icon next
to any secret field.

### Handling secrets carefully

- Values stay masked until tapped, and optionally require a **second Face ID
  check** before they're shown or copied.
- Copying puts the value on the clipboard with an expiry (45 seconds by
  default), so a card number doesn't sit there for the rest of the day.
- The app blurs itself in the app switcher and auto-locks when it leaves the
  foreground.
- If a screen recording or a mirrored display starts while the vault is
  unlocked, a privacy shield covers the screen immediately — a screenshot
  itself can't be blocked by any app, but a live recording or AirPlay mirror
  can, and now is.
- On a device Vault finds signs of being jailbroken on, it says so with a
  dismissible banner rather than silently trusting a sandbox that may no
  longer be one. It never blocks the app outright — false positives on this
  kind of check are common enough that locking someone out entirely would
  cause more harm than the check prevents.
- If the device has no passcode or biometry enrolled at all, Face ID gates now
  **refuse** rather than wave the request through — a locked-away secret with
  no way to prove who's asking stays locked away.
- Key material is zeroed in memory as soon as it's used rather than left for
  the allocator to reuse: the derived encryption key, the passphrase bytes fed
  into PBKDF2, and the raw key unwrapped for each encrypt/decrypt.

### Getting started

The home screen carries a three-step checklist — add an entry, invite your
partner, turn on notifications — and removes itself once all three are done.
Those are the three things the vault is useless without, and each is easy to
not get round to.

### Two devices, hard limit

The vault registers each phone. Once two are registered, a third is refused at
unlock — even with the invitation **and** the passphrase. Freeing a slot is a
deliberate act in Settings → Devices, which is also where you rename a phone or
retire an old one.

### Not losing anything

- **Recently Deleted** — deleting moves an entry to a 30-day holding area that
  syncs across both phones. Swipe to restore, or destroy it immediately. After
  30 days it and its documents are erased everywhere.
- **Encrypted backup** — export every entry *and every attached document* into
  one password-protected file (AirDrop it, or keep it in a safe). Independent
  of iCloud, so it is your way back in if the account is ever lost. Restoring
  merges: anything already in the vault with a newer change date is left alone.
- **Printable emergency sheet** — a plain PDF summary of what exists and who to
  call, for a nominee or a safe. Readable without the app or the passphrase.
  Account numbers print masked (••••3417) by default; the unmasked option
  carries the warning it deserves.

### Syncing

Changes appear on the other phone on their own, over a silent push. If iCloud
is unreachable, everything still works offline and syncs when it comes back —
the home screen says which state you're in, and how many changes are waiting.
A transient CloudKit hiccup (a busy zone, a rate limit, a dropped connection)
is retried on its own with backoff rather than surfaced as a sync failure;
only a genuine, non-recoverable error is shown to you.

## How the secrecy actually works

```
master passphrase  ──PBKDF2-HMAC-SHA256, 600,000 rounds──▶  wrapping key
                                                                 │
random 256-bit data key ◀──── AES-256-GCM unwrap ────────────────┘
        │
        ├──▶ every record, sealed with AES-256-GCM, before it is written
        │
        ├──▶ local file (vault.enc, iOS complete file protection)
        └──▶ iCloud record payloads (ciphertext only)
```

- The **passphrase is never stored, never uploaded, and never recoverable.**
  Both phones derive the same data key from the same passphrase, which is what
  lets two people read one vault.
- iCloud holds three things per record: an opaque ID, a last-changed timestamp
  (needed to resolve conflicts without decrypting), and the ciphertext blob.
- The data key is kept in the **Secure Enclave-backed keychain** behind
  `.userPresence` and `ThisDeviceOnly`, so reading it back *is* the Face ID
  prompt, and it never travels in a device backup.
- The app auto-locks when it leaves the foreground (configurable, default one
  minute) and blurs itself in the app switcher so secrets don't land in a
  snapshot.
- Optionally, **this iPhone erases its own copy after N wrong passphrases**
  (off by default). Nothing is lost when it fires — the other phone still has
  everything, and this one can be set up again from a fresh invitation.
- Sharing uses Apple's own CloudKit invitation, tied to your wife's Apple
  Account — not a link anyone could forward. Even so, the invitation alone is
  useless: it grants access to ciphertext.

The one real consequence: **if you both forget the passphrase, the data is
gone.** There is no reset, by design. Keep an exported backup, or write the
passphrase down somewhere physical.

---

## Building and installing it

You need a Mac with **Xcode 16+** and your paid Apple Developer account.

### 1. Open and set your identifiers

```bash
open FamilyVault.xcodeproj
```

Select the **FamilyVault** target → **Signing & Capabilities**:

1. **Team** — pick your developer team.
2. **Bundle Identifier** — change `com.example.familyvault` to something you
   own, e.g. `com.abhinavj.vault`.
3. **iCloud** capability → tick **CloudKit** → **+** to add a container named
   `iCloud.<your bundle id>` (e.g. `iCloud.com.abhinavj.vault`).
4. **Push Notifications** capability — add it (used for silent sync nudges).
5. **Background Modes** capability → tick **Remote notifications**.

**There is no code to edit.** The app derives its container from its own bundle
identifier, so as long as the container is named `iCloud.` + your bundle id,
they match by construction. Adding it in Xcode also rewrites
`FamilyVault.entitlements` for you.

If you deliberately want a container whose name *doesn't* follow that pattern,
override `AppConfiguration.cloudContainerIdentifier` in
`FamilyVault/App/FamilyVaultApp.swift`.

### 2. Run it on your phone

Plug in your iPhone, pick it as the run destination, and press ⌘R. First launch
asks you to choose the master passphrase — this is the moment the vault is
created.

### 3. Publish the CloudKit schema

Development record types are created automatically the first time you save
something. Before your wife's phone (or a TestFlight build) can use it, promote
the schema:

1. Add one entry of any kind so the record types exist.
2. Add an attachment to it too, so the asset record type is created.
3. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard/) →
   your container → **Schema** → confirm `VaultItem`, `VaultMeta`,
   `VaultDevice` and `VaultAttachment` are listed.
4. **Deploy Schema Changes** → Production.

### 4. Get it onto the second phone

Distribute through **TestFlight** (Product → Archive → Distribute App → App
Store Connect, then add your wife as an internal tester), or **ad-hoc** with
both device UDIDs registered. TestFlight builds expire after 90 days; upload a
fresh build when they do.

### 5. Pair the two phones

1. On **your** phone: Settings → **Share with my partner** → **Send
   invitation** → choose her from Messages.
2. On **her** phone: install the app first, then open the invitation link. It
   opens the app and asks for the master passphrase.
3. Tell her the passphrase **in person** — not over the same iMessage thread.
   Sending the invitation and the passphrase through the same channel undoes
   the point of the design.

She should not tap "Create vault" on her own phone before accepting the
invitation, or the two phones end up with two separate vaults. If that happens,
Settings → Remove vault from this iPhone on her phone, then accept the
invitation.

---

## Layout of the code

```
FamilyVault/
  App/            entry point, app + scene delegates, VaultSession (lock state)
  Crypto/         AES-GCM box, PBKDF2 derivation, keychain, key manager,
                  password generator
  Model/          VaultItem + attachments, categories, field templates, devices,
                  money parsing, summary and health-check rules
  Store/          VaultStore (source of truth), encrypted local file,
                  encrypted attachment store
  Cloud/          CloudKit service, record mapping, change tokens, sharing UI
  Security/       settings, expiring clipboard, per-secret Face ID gate
  Notifications/  local reminder scheduling
  Backup/         password-protected export/restore, emergency-sheet PDF
  Views/          SwiftUI screens
```

The pieces worth understanding first are `Crypto/VaultKeyManager.swift` (how one
passphrase opens one vault on two phones) and `Store/VaultStore.swift` (how the
two copies reconcile — last change wins, per record, with tombstones for
deletions).

## Things it deliberately does not do

- **No passphrase recovery.** Adding one would mean storing a second copy of
  the key somewhere, which is exactly what this app exists to avoid. Keep an
  exported backup instead.
- **No third device, ever** — including an iPad or a Mac.
- **No home-screen widget, Shortcuts actions or Siri.** A widget would have to
  render while the vault is locked, and the key isn't available then; one that
  could show your balances on the lock screen would defeat the lock. Same
  reasoning rules out exposing entries to Siri or Spotlight.
- **No auto-fill into Safari or other apps.** It would mean running an
  extension outside the app's own lock, which is a materially larger attack
  surface than copy-and-paste with an expiring clipboard.
- **No cloud OCR or document AI.** Reading a document happens entirely on the
  phone, with Vision and PDFKit. Sending a policy bond to a server to be parsed
  more cleverly would undo the point of the app.
- **No bank or account connections.** Every figure here is one you typed. That
  is why nothing in this app can move money.
- **No analytics, no crash reporting, no network calls of any kind** other than
  CloudKit.
