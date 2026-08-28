# Vault web editor

A single page that reads and writes the same encrypted vault the iPhone app
uses, so entries can be edited from a keyboard. It talks to the same iCloud
private database over CloudKit JS and does the same crypto in the browser with
WebCrypto — there is no server, and nothing new holds your data.

## What it does and does not do

It joins the vault the way a second phone does: fetch the key material record,
derive the wrapping key from your passphrase, unwrap the data key, then open
each entry's `payload`. Saving re-seals with a fresh nonce and writes the record
back; the phone picks it up on its next sync.

It edits entries — name, description, holder, every field, notes. It does not
create or delete entries, and does not handle documents, reminders or payments.
Do those on the phone.

## The security trade-off, stated plainly

The iPhone app keeps your passphrase out of reach: the derived key lives in the
Keychain, protected by the Secure Enclave, and the plaintext never leaves the
device. This page necessarily asks you to type that passphrase into a browser —
an environment with extensions, other tabs and a far weaker key store. The
passphrase is never sent anywhere and never stored, but it is typed into a
document that could in principle be tampered with.

Use it on your own machine, on a page you serve yourself, and prefer the phone
for anything sensitive.

## Setting it up

You need a CloudKit JS API token. It is free and takes a minute.

1. Go to <https://icloud.developer.apple.com/dashboard/> and pick the
   **iCloud.com.abhinavjain.vault** container.
2. **Settings → Tokens & Sharing → API Tokens → New Token**.
3. Name it (e.g. `web-editor`). Under **Sign in Callback / allowed origins**,
   add the exact origin you will serve the page from — for local use that is
   `http://localhost:8000`.
4. Copy the token.

Then serve the page from that origin. From the repository root:

```
cd web
python3 -m http.server 8000
```

and open <http://localhost:8000>. Opening the file directly with `file://` will
not work: CloudKit JS checks the origin against the token.

Paste the token, choose the environment, and connect:

- **Development** — matches a build installed from Xcode, which is what you are
  running now.
- **Production** — matches TestFlight or the App Store.

They are separate databases with separate data. Pick the wrong one and the page
will connect happily and find no vault.

## If it says there is no vault

The container must have the schema. It is created automatically the first time
the app writes to it, so open the app and add an entry before using this page.
For the production environment you must also promote the schema in CloudKit
Console (**Schema → Deploy to Production**).

## Keeping it in step with the app

These constants must match `CloudKitService` and `CloudRecordMapper`:

| Web page | App |
| --- | --- |
| `ZONE_NAME = "VaultZone"` | `CloudKitService.zoneName` |
| `META_RECORD = "vault-meta"` | `CloudKitService.metaRecordName` |
| `TYPE_ITEM = "VaultItem"` | `CloudRecordType.item` |
| `SCHEMA_VERSION = 1` | `CloudRecordMapper.schemaVersion` |
| `GCM_IV_BYTES = 12` | `AES.GCM.SealedBox(combined:)` |
| ISO-8601 dates | `JSONEncoder.vault` |

If the payload format or the item shape changes in the app, change it here too.
