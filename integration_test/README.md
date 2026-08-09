# Integration test boundary

Identity and authorized-home flows are now composed in the application, but
this directory does not yet contain a live Flutter/backend integration test.
Use the manual smoke workflow in
[docs/local-development.md](../docs/local-development.md) to verify the
email-only login-link flow, automatic first-home ownership, multi-home
selection, changing home, device-session revocation, and sign-out against the
local backend. Production testing must not enable the development-only
password compatibility route.

The inventory, purchasing, and shopping screens are currently backed mostly by
local Drift repositories. Exercising those screens does not prove the matching
backend API. A future automated suite must state explicitly which assertions
are local-only and which cross the pinned server contract.
