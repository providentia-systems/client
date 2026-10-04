# Local database security

## Native policy

The production database opener requires SQLCipher 4 on Android, iOS, Linux,
macOS and Windows. The existing pinned `sqlite3 3.5.0` package's build hook is
configured with `source: sqlcipher`; its release binary hashes are verified by
the upstream hook. An ordinary SQLite library does not satisfy the runtime
`cipher_version` check. No plaintext fallback is permitted.

A cryptographically random 256-bit installation key is written to OS secure
storage and read back before database creation or migration. The key is never
stored in SQLite, preferences, build defines, application logs or exports. Apple
storage uses non-synchronizing, unlocked-this-device keychain items. Android
uses a dedicated storage namespace, authenticated storage encryption, and
`resetOnError: false`, preventing another session-store reset from deleting the
database key. Android cloud backup and device transfer exclude application data;
a device-bound key must not be separated from or restored alongside an
unreadable database. Linux requires an available, unlocked libsecret service.

Missing, malformed, inaccessible and wrong keys fail closed. They do not create
a replacement database or silently reset secure storage. Losing the OS key can
make unsynchronized work unrecoverable. Recovery therefore preserves the
original files for an authorized support/recovery flow; signing in again is not
claimed to recover lost cryptographic material. There is deliberately no
background key rotation or key-deletion-on-logout path.

Logout clears session/offline authorization, not the installation encryption
key. Otherwise signing out could permanently destroy unsynchronized work.
Membership revocation continues to purge the revoked home's projections,
operations and associated state through the existing authorized purge boundary;
other homes and the installation key remain intact. Access to decrypted data
must still be gated by account/home identity and permissions. Encryption is not
an authorization substitute.

## Plaintext upgrade and interrupted startup

The old native Drift database is `providentia.sqlite` in the platform application
documents directory. The encrypted database has a distinct name,
`providentia.encrypted.sqlite`. No schema bump or outbox payload rewrite is
necessary: the format migration happens before ordinary Drift migrations.

The production composition opens one database at startup. Preparation serializes
calls in the calling isolate, uses a Flutter isolate-name-server guard, and takes
a native process lock before loading or creating its key. A terminated isolate
that leaves its guard registered causes a safe startup failure until the whole
application restarts. Database copying runs on a background isolate.

1. Open and integrity-check the legacy source. Require a plaintext SQLite header
   (an empty, unused file is also supported). Acquire exclusive SQLite access,
   switch to DELETE journaling to checkpoint committed WAL contents, and keep
   the exclusive connection until export/verification completes. A concurrently
   running legacy app causes startup to fail rather than knowingly copy a moving
   source. Close old application versions before upgrading.
2. Export into a separate SQLCipher staging file using `sqlcipher_export`.
   Explicitly copy `user_version`, which SQLCipher's export does not copy.
3. Verify schema, schema version and every table's full typed values and row
   multiplicities in both directions. Run SQLite and SQLCipher integrity checks.
   The complete outbox, operation IDs, origin account, order, states, retry
   metadata, receipts, conflicts, cursors and tombstones remain unchanged.
4. Flush the encrypted file, then rename it to its final name on the same
   filesystem. Reopen it using the persisted key and verify it again.
5. Remove the legacy source and sidecars before returning the production
   connection. Failure to clean up blocks startup. Deleting an ordinary file is
   not claimed to securely erase old blocks, snapshots or pre-upgrade backups.

An interrupted partial export can be rebuilt only when the verified legacy
source still exists. An encrypted file published before plaintext cleanup is
compared against that source again before cleanup resumes. Divergent copies are
both preserved and startup is refused. If a staging file is the only remaining
copy, it must unlock and verify with an existing key; it is never reset on error.
Disk-full, corrupt-file and migration errors retain the source and present only
safe error codes, never SQLite statements, keys or paths.

## Web policy: separate local-data passphrase

The browser now requires a **separate local-data passphrase**, independent of
account authentication. Account sign-in is still the existing email-code flow;
unlocking local storage does not authorize an account or home. Native offline
identity leases remain disabled on web. A previously authenticated account
signing out or expiring locks the browser vault and removes the workspace.

Creation requires a repeated passphrase of at least 16 characters and an
explicit acknowledgement: losing the passphrase can permanently lose unsynced
local data. Email codes cannot recover cryptographic keys. There is no reset,
key replacement, automatic deletion, or silent plaintext/in-memory fallback.
Browser data clearing, eviction and profile loss can also destroy unsynced work.
Use a trusted password manager and synchronize important work promptly.

Browser-provided WebCrypto derives a non-extractable AES-256-GCM key using
PBKDF2-HMAC-SHA256, 600,000 iterations and a cryptographically random 128-bit
installation salt. Each full database checkpoint uses a new random 96-bit IV and
128-bit authentication tag. Version, algorithms, iteration count and salt are
authenticated as additional data. Salt, IV, ciphertext and format metadata are
stored together as one IndexedDB record in `providentia.encrypted.v1`. Neither
the passphrase nor a key is persisted, exported or sent to the server. The exact
format and size are validated before decryption (64 MiB plaintext limit).

SQLite/WASM and all journals/temp storage operate only in an in-memory VFS.
Drift's sequential executor holds its lock across encryption and an atomic
IndexedDB read-write transaction with strict durability. An ordinary write is
acknowledged only after that transaction completes. During a Drift transaction,
including nested savepoints, nothing is checkpointed until the outer commit;
projections, the complete outbox and cursors therefore persist as one snapshot.
Initial schema creation/upgrades also produce only a completed checkpoint.
Rollback never publishes uncommitted records. A checkpoint failure preserves the
previous durable snapshot and poisons the current connection, refusing further
reads/writes until a fresh unlock. Close waits for an active checkpoint and
never publishes unfinished transactions or retries a failed checkpoint.

A browser Web Lock is held for the vault lifetime. A second tab fails closed
instead of opening an independently writable copy. Closing during preparation,
key derivation or loading cancels that operation; an in-flight unlock must finish
or observe cancellation before its lock/storage is released. Lock/sign-out
closes SQLite, zeroes accessible VFS/plaintext byte buffers and drops the key
reference. JavaScript/WebAssembly garbage collection does not guarantee physical
zeroization of all temporary copies; this is an at-rest protection boundary, not
a guarantee against a compromised running browser, same-origin script or OS.

### Legacy browser data and recovery

The former plaintext database may exist as IndexedDB `providentia` or OPFS
`drift_db/providentia`. Before creating or unlocking the encrypted vault, both
locations are checked without writing/deleting legacy data. **This release does
not automatically migrate a legacy browser database.** Either legacy location,
ambiguous/unreadable storage or an unsupported inspection API blocks startup.
No new empty database is substituted for old pending work.

The recovery screen tells the user to close this version, use a previous trusted
client version at the same origin to synchronize pending work, or contact
support for a verified export/encrypted migration. Do not clear the browser
profile or old storage while unsynced work remains. Any later deletion/migration
requires separately verified preservation of the old database and outbox; it is
not performed by this implementation. Old plaintext backups are not encrypted
retroactively.

### Browser requirements and evidence

Require a secure context (HTTPS, or browser-trusted loopback development),
WebCrypto, Web Locks, IndexedDB with database enumeration and strict transaction
durability, OPFS directory inspection, and compatible SQLite WASM. Missing or
inaccessible features fail closed; no plaintext or non-persistent fallback is
available. Browser-version promises are subordinate to these runtime checks.

`bash tool/browser_security/run_probe.sh` compiles a synthetic Dart harness and
runs the actual WASM/WebCrypto/IndexedDB adapter in a disposable Chromium profile
and localhost origin. The PR quality job requires this check. It exercises
ciphertext-only persistence, fresh IVs, cross-connection and cross-tab locking, full document destruction/reopen,
wrong passphrase, tamper rejection, pending prepare/unlock cancellation, nested
transaction/rollback preservation and
legacy IndexedDB/OPFS refusal. Local invocation in the October repair workspace
is blocked by browser process-socket restrictions and cloud-browser localhost
policy; compilation/unit tests are not represented as runtime browser proof.
The final PR CI result must supply that proof. Firefox/Safari/Edge, eviction,
private mode, browser termination, power loss and deployed HTTPS/offline asset
availability remain release acceptance work.

## Threat boundary and release evidence

Encryption protects database files at rest independently of the application
sandbox. It does not protect decrypted memory in a running authorized app,
a compromised OS account, a compromised native process, an unlocked OS keyring,
or previously copied plaintext files. Temporary SQLite storage is forced to
memory, key/page access is configured before any production schema query, and
SQLCipher internal diagnostic logging is disabled.

Automated fixtures cover new encrypted creation, plaintext/WAL migration,
all-table/outbox preservation, cold reopen, missing/wrong/unavailable keys,
interrupted exports/publication, divergent copies, and concurrent initialization
in the production calling isolate. These fixtures use synthetic data only.

Release acceptance still requires real native keystore and lock/unlock tests,
installer-upgrade/process-death tests, power-loss/filesystem testing, each native
platform's build and device/desktop acceptance, and review of SQLCipher Community
Edition plus statically linked OpenSSL licenses/SBOMs. A unit test or a successful
Linux build does not establish those device/platform outcomes.

Primary implementation references:

- [sqlite3 native build hooks](https://github.com/simolus3/sqlite3.dart/blob/sqlite3-3.5.0/sqlite3/doc/hook.md)
- [SQLCipher API, raw keys, export and integrity checks](https://www.zetetic.net/sqlcipher/sqlcipher-api/)
- [Drift encryption](https://drift.simonbinder.eu/platforms/encryption/)
