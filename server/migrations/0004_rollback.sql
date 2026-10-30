-- 0004_rollback.sql
ALTER TABLE `comments`
  DROP KEY `idx_checkin_featured`,
  DROP COLUMN `is_featured`;
