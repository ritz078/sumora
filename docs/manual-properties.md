# Manual real estate

The Real Estate page (also reachable from Settings) lets the signed-in user add, edit, and remove properties. Enter a name, classification, full estimated INR value, valuation date, and optional location. Full purchase cost is optional and supports unrealized gain on the instrument page. Missing purchase cost keeps gain unavailable.

Net worth and asset allocation include the full entered estimated value. Ownership percentages are not collected or calculated; legacy percentages are ignored when valuing saved properties. Values are manually maintained; there is no automatic appreciation or invented daily performance. Loan balances are not collected or deducted. Removing a property does not create cash proceeds.

Entries are owner-scoped, persisted in D1, and limited to 50 per owner. Failed edits preserve saved values. Authentication changes clear the editor and cached entries. Migration 0019 creates the properties table.
