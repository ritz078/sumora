-- Re-read already imported emails once to enrich legacy purchases with YTM.
-- Financial events remain intact and deduplicated; bounded Gmail batches resume.
DELETE FROM wint_imports WHERE status='imported';
UPDATE bonds_settings SET wint_cursor=NULL,scan_kind='wint',lease_until=0;
