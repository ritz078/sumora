# NPS and Fixed Deposit instrument pages

Homepage allocation opens dedicated NPS and Fixed Deposit pages using the Indian Stocks page layout: valuation summary, saved instrument trajectory, and value-sorted holdings. Both pages omit daily performance. They retain the shared Inter typography, back navigation, pull to refresh, balance masking, and retained-data behavior on refresh errors.

NPS displays recorded scheme units, tier/code, and statement NAV. Contributions and gains remain unavailable when acquisition cost is unknown. It does not invent a live NAV feed.

Fixed Deposits displays the statement maturity amount, stated annual rate, and maturity date. The same maturity amount counts toward net worth. The FD page omits interest and return figures. Portfolio totals treat original principal as known invested cost, assuming no withdrawals before maturity, and include maturity value minus original principal in gains. These gains include future interest.

Live trajectories use saved NPS or Fixed Deposit snapshots from the existing history API. No earlier history is fabricated. The compact `statements.json` fixture is selected only with both `--ui-testing` and `--statement-fixture`; it verifies that maturity values differ from the recorded current amount and can be below original principal following withdrawals, that NPS unknown costs remain unavailable, and that both pages filter out other instruments.
