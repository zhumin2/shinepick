-- 0009_admin_actions.sql（MySQL 8 / utf8mb4）
-- v0.6.0 T9：管理操作留底（封禁/下架/公告/举报处理等）。

CREATE TABLE `admin_actions` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `action`      VARCHAR(40)     NOT NULL COMMENT 'handle_report/user_status/delete_checkin/delete_comment/announce/set_selected',
  `target_type` VARCHAR(20)     NOT NULL DEFAULT '' COMMENT 'report/user/checkin/comment/feed',
  `target_id`   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `detail`      VARCHAR(255)    NOT NULL DEFAULT '',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_created` (`created_at`),
  KEY `idx_action` (`action`, `id`)
) ENGINE=InnoDB COMMENT='管理操作日志';
