# Home overview and report navigation

Home overview uses independent, home-validated local streams. Its counters mean:

- **Household products**: distinct household product IDs, including private and
  catalog-linked products added to this home. A global catalog pack that has not
  been added is excluded. Two home products linked to one pack remain two items.
- **Products with a balance**: household products with a recorded ledger quantity,
  including zero, signed and fractional values. This counts records, never sums
  unlike units, and does not certify a physical count or trusted chronology.
- **Finished receipts**: distinct committed receipt IDs across all saved calendar
  purchase dates. Missing prices and header-only receipts remain eligible. Drafts
  and cancellations are excluded. Older product-only sources are explicitly
  labeled **Saved purchase lines**, including missing prices; they do not claim
  to count receipts or implement an unstated recent time window.

A first read is loading until data arrives. A failed initial read is unavailable,
not zero. A subsequent failed read retains and labels the last known successful
view. A successful empty read can show zero. Inventory and purchase failures do
not erase or zero each other's figures. The synchronization status separately
identifies saved/offline/unverified data and unresolved local changes; none of
these counts promises server acceptance.

Reports and Account/settings are named links in the same workspace toolbar on
phone, tablet and desktop. The primary Stock, Purchases and Lists destinations
remain available. These links push the existing routes; returning keeps the
workspace, typed filters and controllers mounted. They do not rebuild storage,
reset the queue or create new synchronization identities.

The Reports link uses the existing production guard for the selected home,
report permission, authenticated identity and online availability. The report
route shows the selected home name and retains its existing protected-route
registration and state clearing. Unavailable/offline routes explain the state;
account management does not imply household reporting permission.

Report sections expand to their content in one page scroll. There are no clipped
fixed-height cards with hidden independent lists. A visible page scrollbar, page
hint, ordinary touch/pointer scrolling and keyboard page navigation expose all
rows. Synthetic tests exercise 60 inventory rows, keyboard navigation, phone/tablet/desktop
layout links, route ownership and returning to typed workspace input.
