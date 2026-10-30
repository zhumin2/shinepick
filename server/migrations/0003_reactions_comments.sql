-- 0003_reactions_comments.sql（MySQL 8 / utf8mb4）
-- S5：情绪互动 + 小便签留言 + 同路人关系（结构对齐技术设计文档 §4.2）。

CREATE TABLE `reactions` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `checkin_id`  BIGINT UNSIGNED NOT NULL,
  `user_id`     BIGINT UNSIGNED NOT NULL,
  `type`        TINYINT         NOT NULL COMMENT '1点亮 2拥抱 3同路',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_target` (`checkin_id`, `user_id`, `type`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB COMMENT='情绪互动';

CREATE TABLE `comments` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `checkin_id`  BIGINT UNSIGNED NOT NULL,
  `user_id`     BIGINT UNSIGNED NOT NULL,
  `content`     VARCHAR(80)     NOT NULL,
  `status`      TINYINT         NOT NULL DEFAULT 0 COMMENT '0正常 1已删 2审核拒绝',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_checkin` (`checkin_id`, `id`)
) ENGINE=InnoDB COMMENT='留言';

CREATE TABLE `companion_relations` (
  `id`               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_a`           BIGINT UNSIGNED NOT NULL,
  `user_b`           BIGINT UNSIGNED NOT NULL COMMENT '约定 user_a < user_b',
  `source_checkin_id` BIGINT UNSIGNED NULL COMMENT '由哪条打卡建立',
  `status`           TINYINT         NOT NULL DEFAULT 0 COMMENT '0已同路 1已解除',
  `created_at`       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_pair` (`user_a`, `user_b`),
  KEY `idx_b` (`user_b`, `status`)
) ENGINE=InnoDB COMMENT='同路人关系';
