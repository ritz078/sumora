# NPS and Fixed Deposit instrument pages

Homepage allocation opens dedicated NPS and Fixed Deposit pages using the Indian Stocks page layout: valuation summary, saved instrument trajectory, and value-sorted holdings. Both pages omit daily performance. They retain the shared Inter typography, back navigation, pull to refresh, balance masking, and retained-data behavior on refresh errors.

NPS displays recorded scheme units, tier/code, and statement NAV. Contributions and gains remain unavailable when acquisition cost is unknown. It does not invent a live NAV feed.

Fixed Deposits displays statement maturity amounts, original principal, stated annual rate, maturity date, and projected interest (maturity amount minus original principal). Summary returns are labelled “At maturity”; the page explains that future interest is included and this is not a current withdrawal value. Missing deposit terms leave aggregate principal and projected return unavailable.

Live trajectories use saved NPS or Fixed Deposit snapshots from the existing history API. No earlier history is fabricated. The compact `statements.json` fixture is selected only with both `--ui-testing` and `--statement-fixture`; it verifies that maturity values differ from the recorded current amount, that NPS unknown costs remain unavailable, and that both pages filter out other instruments.
