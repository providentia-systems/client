# Bounded native offline startup

## Policy and scope

The product requirements (master implementation prompt, sections 14.1–14.3)
require durable local work and idempotent synchronization, while membership and
role changes stay server-authoritative and are unavailable as offline grants.
The previous startup implementation required the network even when a native
installation had an intact secure session and durable pending work.

The native client now retains a local-access lease only after a successful
session grant and strictly validated current-user response, plus a separately
verified active home. This is a conservative implementation policy, not an
owner-selected duration or a new backend authorization grant:

- Default and maximum local-access window: 24 hours from online verification.
  `IdentitySessionManager.offlineAccessWindow` may shorten the bound. The lease
  also ends at either finite server session deadline, whichever is earlier.
- A secure native refresh credential must still exist and match the exact
  account, session, device and installation. Historical saved credentials
  without an account binding must first refresh online.
- Leases are held in OS secure storage, namespaced to the configured backend
  origin, and contain no bearer or refresh credentials. They are separate from
  encrypted household records and ordinary active-home preferences.
- Cold-start fallback is allowed only for network/unavailable failures or a
  transport timeout. Authentication rejection, forbidden access, rate limits,
  invalid responses, different identities and secure-store failures do not
  enable fallback. Browser cookie sessions never use native offline leases.
- Only the exact previously active home is opened. Its permission set is
  intersected with local inventory, purchasing and shopping capabilities.
  Membership/role management, home switching, AI, contributions, account
  changes, reports, exports, erasure and billing remain online-only.

The offline banner explains the limitation and provides Reconnect and Sign out.
Ordinary local commands keep their account/device/home-bound operation IDs and
are stored transactionally with the optimistic projection. An offline session
cannot send an authenticated HTTP request. Reconnect restores the online
session, remounts the home chooser and revalidates current home access before
creating an online workspace or sending pending work. Server synchronization
still independently authorizes each operation.

## Expiry, clocks and access loss

A high-water UTC observation is persisted before opening a lease and every
minute while it is open. Backward clock movement below a persisted observation
fails closed. During the process lifetime, a monotonic stopwatch bounds elapsed
access independently of wall-clock changes; a five-second drift allowance
avoids rejecting routine scheduling jitter. Local mutation guards and app
lifecycle transitions also check validity. The expiry timer closes cached
presentation and retires the secure lease. If lease deletion fails, the
existing durable logout journal and native-credential deletion are attempted
as independent barriers. A compromised OS/profile capable of rewriting its
secure store and clock remains outside this application boundary.

Explicit sign-out, replacement sign-in and authoritative session rejection
retire the local-access lease along with native credentials. The pre-existing
logout journal prevents a late response or restart from reviving a signed-out
session. Explicit home revocation removes its cached access and runs the
existing quiesced revoked-home purge. Known permission loss invalidates cached
home access; it is not silently reused on the next offline start.

Native offline sign-out removes local credentials and access immediately, but
cannot confirm server revocation without a connection. The refresh credential is
discarded, so the client does not promise to retry remote revocation later. The
UI states that remote sign-out could not be confirmed; an authorized online
session can review/revoke the remaining device session through Account & access.
A restart must still remain signed out. Browser logout retains its separate
cookie-cleanup journal and must finish that cleanup before restoring cookies.

Sign-out does not delete the installation encryption key or pending household
work. This preserves the repository's existing pending-data policy without
exposing records to the next account: a new account requires its own online
session and verified home access, and the sync gateway rejects operations from
a different or unknown originating account. See
[local database security](local-database-security.md) for SQLCipher migration,
key loss and the separate browser-passphrase encryption/recovery policy. Web
local-data unlock never grants native offline identity authority or substitutes
for email-code account authentication.

## Verification

Regression tests cover network and unavailable restoration, forbidden/invalid/
rate-limit rejection, expiry, rollback, origin and account isolation, missing
account bindings, blocked HTTP transmission, logout, secure-store failures,
permission filtering, mismatched homes and delayed restoration after session
loss. The receipt suite separately exercises durable commit/readback recovery
and immutable operation IDs across process restart. These automated tests are
not evidence of physical-device keystore, browser-profile or installer-upgrade
acceptance.
