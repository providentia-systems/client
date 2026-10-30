# Client issues 28–46

The implementation scope is all Client issues **#28–#46**. The current
implementation matrix, supported canonical contract, reproducible checks and
installed acceptance boundary are in
[Client issues 28–46: acceptance scope and release evidence](client-28-46-acceptance.md).

This PR modifies the homeowner Flutter Client, its application-owned adapters,
local persistence, tests, build evidence and documentation. Backend and Admin
implementation remains in their independently managed repositories. The earlier
backend issue references identify API dependencies; they do not mean backend
code belongs in the Client.

No backend implementation from this thread was pushed. Client #46 remains open
until the exact installed native/browser pair and synthetic two-device workflows
have been exercised. Source tests and CI results are reported separately.
