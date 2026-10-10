# Gold & Bullion reference

Stitch project `7332412299640222202`, screen `e616c9a3bb7e46d5a6cb35c2b969347d` (Sumora — Gold & Bullion), downloaded with `curl -fL` on 10 October 2026.

The screen directory contains the original `reference.html` and full-resolution `reference.jpg` (780 × 2730 pixels). The image URL uses the `=s0` suffix to retrieve the original rather than a thumbnail. These are design references; example holdings, prices, providers, and returns are not live portfolio data.

The native Gold & Bullion page follows the reference's compact valuation card, dark daily-performance card with amber glow, amber trajectory and value marker, and tagged gold rows. It opens from homepage allocation and uses the existing portfolio and instrument-history APIs. Value sorting, refresh, privacy masking, and unavailable-price/baseline/cost states remain functional. The refresh button reloads saved account data; it does not claim a live IBJA tick.

Source labels reflect recorded data. Gullak purchase cost remains unknown, and gold benchmarks are explicitly distinguished from redemption quotes. SGB units retain their source unit rather than being relabelled as grams. Provider tags are derived from instrument/account metadata; sample providers are not fabricated in live accounts. Dedicated pages follow the app's existing navigation behavior, with the main dock hidden while drilling into an instrument.

`gold.json` is a compact UI-test-only sample containing SGB, digital bullion, and Gullak rows, including an unknown purchase cost and known daily baseline. Normal demo and live portfolio loading do not select this fixture.
