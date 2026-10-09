# Bond imports

Settings → Bonds · CDSL CAS → enter the first holder’s PAN → Enable bond imports. The PAN is encrypted server-side, never returned by status endpoints, and used to decrypt statement PDFs. Sync Gmail documents imports all enabled statement sources, including bonds. Existing scheduled statement processing rotates one configured source per run.

The initial parser supports the inspected CDSL CAS layout: one NSDL account containing NCDs. It reconciles the account summary, closing holdings, units × stated price and the entire CAS Debts allocation. Other account/layout combinations fail for review and retain the last successful balances. Transactions, equities and mutual funds are excluded. A complete newer snapshot replaces all prior bonds; explicit zero-debt / Nil Holding statements clear the balance. Older or duplicate PDFs cannot regress balances; conflicting same-date files require review.

Net worth uses the stated CAS market price or face value with its valuation date. The value is not a live quote, guaranteed sale/redemption value, or maturity payout. Purchase cost, coupon payments, accrued interest, daily gains and unrealized return are not inferred. Coupon and maturity metadata are displayed only when explicit in security names. A passed maturity date flags a redemption check and retains the dated balance until a newer statement confirms removal.

Migration 0016 stores owner-scoped encrypted settings, an account hash, latest holdings and a bounded-mailbox import ledger. Snapshot triggers record successful imports atomically; a failed ledger write rolls back the balance. No PAN or full demat identifier is stored in the holdings snapshot. Decrypted PDFs and statement text are processed in memory rather than retained.

Validation: synthetic encrypted PDF tests cover the real Gmail `bin` MIME type, strict sender/DMARC checks, decryption failures, reconciliation, deduplication, owner isolation, monotonic dates, cancellation and atomic rollback. The original encrypted CAS was privately parsed with the production extractor and reconciled to nine bonds / ₹448,845 as of 2026-08-31; it is not committed as a fixture.
