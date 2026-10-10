# Manual real estate

Settings → Manual assets → Real estate lets the signed-in user add, edit, and remove properties. Enter a name, full estimated INR value, ownership percentage (100% by default), and valuation date. Full purchase cost is optional and for reference.

Net worth and asset allocation include estimated value × ownership percentage / 100. Values are manually maintained; there is no automatic appreciation or invented daily performance. Loan balances are not collected or deducted. Removing a property does not create cash proceeds.

Entries are owner-scoped, persisted in D1, and limited to 50 per owner. Failed edits preserve saved values. Authentication changes clear the editor and cached entries. Migration 0019 creates the properties table.
