-- 0005_notifications_blocks_reports.sql（MySQL 8 / utf8mb4）
-- S6：通知（应用内；极光推送待凭据）、拉黑、举报。

CREATE TABLE `notifications` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '接收者',
  `type`       TINYINT         NOT NULL COMMENT '1点亮 2拥抱 3同路 4留言 5系统',
  `actor_id`   BIGINT UNSIGNED NULL COMMENT '触发者（匿名互动时 NULL）',
  `checkin_id` BIGINT UNSIGNED NULL,
  `comment_id` BIGINT UNSIGNED NULL,
  `agg_count`  INT UNSIGNED    NOT NULL DEFAULT 1 COMMENT '10 分钟同类聚合数',
  `is_read`    TINYINT         NOT NULL DEFAULT 0,
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_user_read` (`user_id`, `is_read`, `id`)
) ENGINE=InnoDB COMMENT='通知';

CREATE TABLE `blocks` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `blocker_id` BIGINT UNSIGNED NOT NULL,
  `blocked_id` BIGINT UNSIGNED NOT NULL,
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_pair` (`blocker_id`, `blocked_id`),
  KEY `idx_blocked` (`blocked_id`)
) ENGINE=InnoDB COMMENT='拉黑';

CREATE TABLE `reports` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reporter_id` BIGINT UNSIGNED NOT NULL,
  `target_type` TINYINT         NOT NULL COMMENT '1打卡 2留言 3用户',
  `target_id`   BIGINT UNSIGNED NOT NULL,
  `reason`      TINYINT         NOT NULL DEFAULT 0 COMMENT '理由枚举',
  `detail`      VARCHAR(255)    NOT NULL DEFAULT '',
  `status`      TINYINT         NOT NULL DEFAULT 0 COMMENT '0待处理 1已处理 2驳回',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`, `id`),
  KEY `idx_reporter` (`reporter_id`)
) ENGINE=InnoDB COMMENT='举报';
