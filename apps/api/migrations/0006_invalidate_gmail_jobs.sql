CREATE TRIGGER invalidate_gmail_jobs_on_unlink AFTER DELETE ON gmail_connections
BEGIN
 UPDATE gmail_documents SET status='awaiting_parser',processing_id=NULL,processing_until=0,processing_attempts=0,retry_at=0
 WHERE owner_id=OLD.owner_id AND status='processing';
END;
