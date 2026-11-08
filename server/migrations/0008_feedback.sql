-- 0008_feedback.sql（MySQL 8 / utf8mb4）
-- v0.6.0 T8：意见反馈（设置页提交 → 运营面板查看处理）。

CREATE TABLE `feedback` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `content`    VARCHAR(200)    NOT NULL,
  `status`     TINYINT         NOT NULL DEFAULT 0 COMMENT '0待处理 1已处理',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`, `id`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB COMMENT='意见反馈';
