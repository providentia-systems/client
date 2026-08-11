# Strict-local AI platform boundary

Direct Ollama and OpenAI-compatible LAN requests are enabled only when the
platform supplies a transport that can pin a request to pre-validated DNS
answers, expose the connected peer address, and disable redirects. The gateway
rechecks the peer after every request and rejects DNS rebinding, public or
metadata addresses, alternate schemes, user info, queries, fragments, and any
redirect.

Browser networking APIs do not expose the connected peer or provide reliable
redirect control. The default composition therefore denies direct strict-local
AI on Flutter web. The production native composition supplies the strict-local
boundary for stock-photo counting. When a local profile is selected, an
unavailable, dangling, or misconfigured route fails closed before consent and
never sends bytes through the server proxy. The user must explicitly switch
back to the disclosed server-proxy route. A native shell enables local routing
by supplying the `StrictLocalHttpTransport`, `StrictLocalNameResolver`, and
(when authentication is configured) OS-backed
`StrictLocalCredentialReader` ports. Secrets must not be stored in browser
storage or in ordinary application configuration.

Receipt intake does not use this direct-local production route. An Ollama
receipt profile may be configured through the server AI workspace, but those
receipt bytes travel through the server proxy and must be disclosed as such.

Allowed targets are loopback, RFC1918 IPv4, IPv6 loopback, IPv6 unique-local,
and `.local` names whose complete DNS answer set is allowed. Link-local,
carrier-grade NAT, mixed private/public DNS, IPv4-mapped IPv6, known metadata
addresses, and public addresses are rejected. Generic compatible endpoints use
HTTPS unless the route is one of those explicitly local targets; all direct
routes remain subject to peer verification.
