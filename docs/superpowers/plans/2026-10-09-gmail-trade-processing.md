# Contract-note subsystem retired; Gmail retained

User clarified Gmail remains needed for future gold imports. Generic Gmail read-only OAuth, encrypted credential storage, connection status, reconnect and disconnect controls are retained. Existing credentials and data are preserved.

Contract-note collection, historical backfill, PAN controls, PDF parsing, trade import/history API/UI/tools/dependencies remain removed. No background schedules or document storage bindings are enabled. Applied migrations remain as immutable schema history. Gold ingestion is not implemented by this change.

Production remains on the paused version pending rollout approval; the prior removal-only app build was not installed.

Validation: 27 backend tests, typecheck and 26 iOS unit tests pass with Gmail retained.
