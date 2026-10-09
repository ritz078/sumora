# Sample API integration

Implement a TypeScript Hono Worker with `GET /health` and `GET /v1/demo/portfolio?scenario=complete`. The versioned demo endpoint returns the existing snapshot JSON unchanged. Supported scenarios are complete, partial, stale, empty, unavailable and failure. Failure returns 503; invalid scenarios return 400; errors use `{ "error": { "code": "...", "message": "..." } }`. All sample responses use no-store and retain fixed timestamps and decimal strings.

The iOS URLSession client decodes ISO dates and decimal strings, validates HTTP status, rejects unreadable responses, and propagates network failures to the existing store. No silent offline fallback. Settings lets users select API or offline sample data; test launches default to offline fixtures. App builds default to the deployed HTTPS Worker; debug builds also accept localhost:8787 for development. Localhost HTTP is permitted only for debug development.

Execution: first test route contracts against fixtures, then implement Hono routes. Test Swift HTTP decoding and errors, then implement transport and settings selection. Verify Worker runtime locally, attempt deployment with existing Cloudflare credentials, run iOS unit/UI tests and launch the simulator against the working endpoint. Authentication and user-specific data are the next milestone; this endpoint contains only public sample data.
