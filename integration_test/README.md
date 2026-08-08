# Integration test boundary

Identity and authorized-home flows are now composed in the application, but
this directory does not yet contain a live Flutter/backend integration test.
Use the manual smoke workflow in
[docs/local-development.md](../docs/local-development.md) to verify password
login, home creation/selection, changing home, and sign-out against the local
backend.

The inventory, purchasing, and shopping screens are currently backed mostly by
local Drift repositories. Exercising those screens does not prove the matching
backend API. A future automated suite must state explicitly which assertions
are local-only and which cross the pinned server contract.
