# Count evidence and photo ordering

Client issues #28 and #32 use the existing backend count and synchronization
commands. No server routes or eligibility rules are introduced here.

Manual and photo counts start with unassessed evidence. Finishing opens a review
of the actual physical observation timestamp, including an explicit UTC or
numeric timezone offset, completeness of the selected scope, and reliability.
The device does not silently substitute entry or finishing time. The backend
verifies and captures the household's IANA timezone; an already captured timezone
is shown independently from the timestamp. A reliable claim requires explicit
complete scope. A selected-location count remains a location observation and
cannot become a whole-home checkpoint. Omitted products stay unchanged.

Finishing saves observations and queues the ordinary close command. It does not
replace a balance locally or certify pending observations. Count history labels
server acceptance separately from locally queued work. Historical unassessed
counts retain their evidence state until deliberately reviewed.

An authorized inventory writer can review an accepted closed count, explain the
reason, correct its observation evidence, and correct existing quantities. The
queued command retains session and line IDs and their exact expected revisions.
It cannot change product identities or invent omitted lines. Previous accepted
evidence and balances remain visible while the review awaits server readback;
the server keeps its immutable previous/next audit snapshots. A validation or
revision failure in the form retains the typed values. Synchronization and its
existing conflict/recovery controls expose blocked queued operations; submitting
a second review does not bypass an unresolved first one.

Purchasing a product saves and queues that purchase before the receipt is
finished. Finishing the receipt does not add its stock effect again. When no
checkpoint anchors the local balance, the existing immediate estimate remains
available and is explicitly labelled as a local estimate. When a checkpoint
exists, local purchase changes are kept as a separate pending amount and do not
alter current stock. Only the server has the authoritative household calendar
and chronology needed to place late and same-day facts. In particular, entering
a purchase from before a trusted count cannot inflate current stock locally.
Authoritative readback replaces these temporary local markers and retains the
server's uncertainty, pending quantities, limitations and checkpoint metadata.

Cloud stock-photo analysis first awaits the foreground synchronization attempt
for the original count ID and verifies acknowledgement of its creation under
the original account/home/device binding, or an already synchronized server-origin open
count. An offline, delayed or interrupted attempt shows a retryable waiting
state. Retrying retains the same count, prepared ephemeral photos and explicit
consent; it does not create another count or begin extraction early. Closing or
cancelling the count while waiting prevents subsequent transmission. Strict-local
photo analysis remains independent of server acknowledgement.

An AI response, including a typed home-denial problem, does not itself authorize
purging saved household work. Production independently lists homes through the
current authenticated home transport and rechecks the account/device/home
binding after the response. Only a successful complete listing which omits the
selected home confirms revocation. Continued membership, offline/service
failures, expired authentication, malformed responses and a changed binding
preserve saved records and operations while AI remains blocked. Independently
verified synchronization revocations retain their established cleanup path.

Synthetic native and widget tests exercise these boundaries, revisions, retries,
restart visibility, late purchases and zero quantities. They do not establish
deployment acceptance or recovery of a real household's installed database.
