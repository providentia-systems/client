# Email codes, profiles and scoped home access

This document records the API 2.1.0 pre-release alignment. Earlier phase
snapshots describe historical designs; this document and the current contract
supersede their login-link and administrator visibility rules.

## Sign-in and identity

The user enters an email and receives an eight-digit number from the backend.
The client keeps the challenge binding in protected pending-request storage,
enters the number through the verify endpoint, and establishes the session
only for the requesting installation. Codes expire in ten minutes, allow five
failed attempts, can be resent after 60 seconds, and are single use. Resending
retires the old code without resetting address/network rate limits. Codes and
binding values are not written to logs or rendered into callback URLs.

Web sessions use HttpOnly cookies and CSRF protection. Native refresh material
uses platform secure storage. Cancellation, sign-out, replacement login and
cross-tab events cannot let a late response restore an obsolete account.
Device management and revocation remain available through Account & access.

A person has one immutable identity and one or more verified email aliases.
Adding an alias requires its own emailed code; the primary address may change,
but the last verified address cannot be deleted. An address already owned by
another account is never silently merged. Pending invitations match verified
aliases. Name, optional Gravatar, cropped uploaded avatar and location/profile
settings are editable. Gravatar is explicitly selected for a verified address.

## Account and home groups

Accounts and homes each have one independently assigned group. Administrators
control those groups and their features and numeric limits in the separate
admin application; the backend is the final authority.

Country onboarding supplies name, country, optional region/city and agreement
acceptance. Only Namibia is published initially. The country's configuration
selects default account, invited-account and home groups, currency, timezone
and published policy version. The default standalone account may own one home;
the default invited-account group does not permit home creation. Creation is
explicit and copies country currency/timezone defaults into editable fields.

Each home has its own group even when a person belongs to several homes. Each
membership has a role: owner, manager, member or viewer. The backend computes
that membership's effective permissions from the home group, role defaults and
individual overrides. A permission from one home is never carried into another.
A more permissive home exposes its greater access when it is active.

Homeowners can delegate only the permissions administrators mark delegable.
Individual settings support inherit, allow and deny. A manager cannot grant a
permission they do not hold. The `permissions.manage` capability enables those
settings independently of role/removal management. Home role, membership and
ownership changes remain separate authorized commands.

Inviting is a home feature, initially disabled. Total and role limits control
additional owners, managers and members. Pending invitations can be accepted
or declined in the home chooser. Acceptance rechecks sender authority and
current quotas. Existing memberships remain usable after a downgrade; no
member is removed automatically. Likewise, lowering category/product limits
preserves current records while preventing additions beyond the new allowance.
Disabling an operational feature hides its surface and the backend rejects
further use. Owned-home limits are account-scoped, including additional owners.

## Profiles and data access

Home settings support name, description, image, country/region/city, optional
map position, currency and timezone. Coordinates are sent as numbers even when
a database returns decimal strings. A default home icon is shown without a
custom image. Home photos and metadata remain authorized home resources.

Ordinary clients see only homes where they hold an active authorized membership.
Catalog sharing means deliberately contributing selected product/category
metadata to defaults usable by other homes. It does not publish home quantities,
private histories or membership lists. Starter catalogs have no quantities.

The system owner can inspect all application records through the administrative
API and may delegate specific administrative permissions. Home inventory,
categories, products, membership and people data may be inspected by authorized
operators for support and product improvement as described in the published
policy. This is independent of optional public catalog sharing. Operator access
is audited; credentials and provider secrets remain protected. The homeowner
client has no operator browse or account/group administration surfaces.

## AI and future billing

Own-provider credentials are separately controlled by `ai.credentials.use`;
platform-provided AI has `ai.platform.use`. Existing read/use/manage permissions
still apply to their respective operations. Image input remains temporary and
reviewed proposals become stock only through ordinary authorized inventory
commands. Paid plan linking, query billing and store purchase integration are
future work; these manually assigned groups do not charge users.

## Verification

Run the pinned source, generated-contract, analysis, test and coverage gates,
then the platform CI builds. The release browser harness proves delivery to a
controlled TLS mailbox, challenge binding, code replay rejection, cookie
attributes, current-user/home bootstrap, cross-tab access, refresh rotation and
logout. Live deployment and store certification evidence must be recorded
separately; generated clients or local tests do not establish those outcomes.
