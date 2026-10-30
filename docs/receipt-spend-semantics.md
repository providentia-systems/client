# Receipt spend and entered products

The Purchases workspace's Recent spend includes all saved **finished** receipt
calendar dates. It does not impose a hidden rolling date window. Compare it with
the household purchase report using the same inclusive purchase-date range,
finished status and currency. Backend summary requests can use a rolling
`recentDays` window; their amount is comparable only after matching that scope.
Draft and cancelled receipts do not contribute. Nonremoved lines count for
pricing whether approved, unresolved or unreviewed; pricing never authorizes stock.

For each receipt, an explicitly entered header total is the receipt spend,
including a genuine zero or discount. Without that header, use the complete
nonremoved product-line subtotal: explicit line total first, otherwise purchased
quantity multiplied by unit price, rounded independently per line to two decimal
places with HALF_UP and exact integer arithmetic. A receipt without a header and
without any lines has unknown spend. Missing prices produce a disclosed known
subtotal and incomplete spend, never a complete zero.

Currencies are shown separately. One physical header is counted once per receipt,
including header-only receipts and receipts whose last product line was removed.
Entered-product totals and their discrepancy from the header remain separate.
Changing prices or the header does not change stock. Pending local corrections
appear immediately and remain labeled as pending until authoritative readback.
Saved encrypted receipt and line projections rebuild the same summary on restart;
no separate money cache or replacement operation identity is introduced.

Legacy imported product-only groups remain inspectable as entered-products
subtotals. They are not added to receipt spend when no receipt header context is
available. Read-only household members receive the same receipt-aware read model;
editing permissions are independent of summary access.
