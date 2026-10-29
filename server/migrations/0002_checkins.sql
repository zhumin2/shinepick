-- 0002_checkins.sql（MySQL 8 / utf8mb4）
-- S3：打卡 + 拾光树进度（结构对齐技术设计文档 §4.2）。
-- 验证码走 Redis；留言/互动/通知等表在 S5/S6 迁移中补充。

CREATE TABLE `checkins` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`      BIGINT UNSIGNED NOT NULL,
  `category`     TINYINT         NOT NULL COMMENT '1运动 2阅读 3旅行 4社交 5宠物 6自定义',
  `content`      VARCHAR(500)    NOT NULL DEFAULT '',
  `image_urls`   JSON            NULL COMMENT '最多9张（URL 数组）',
  `video_url`    VARCHAR(255)    NULL,
  `visibility`   TINYINT         NOT NULL DEFAULT 2 COMMENT '1仅自己 2同路人 3小树洞',
  `extra`        JSON            NULL COMMENT '运动:{km,duration} 阅读:{book,page} 旅行:{location}',
  `checkin_date` DATE            NOT NULL COMMENT '打卡归属日(东八区)',
  `status`       TINYINT         NOT NULL DEFAULT 0 COMMENT '0正常 1已删 2审核中 3审核拒绝',
  `created_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_user_date`  (`user_id`, `checkin_date`),
  KEY `idx_cat_date`   (`category`, `checkin_date`, `status`),
  KEY `idx_date_status`(`checkin_date`, `status`)
) ENGINE=InnoDB COMMENT='打卡';

CREATE TABLE `tree_progress` (
  `user_id`      BIGINT UNSIGNED NOT NULL,
  `level`        TINYINT         NOT NULL DEFAULT 1 COMMENT '树阶段 1-12',
  `points`       INT UNSIGNED    NOT NULL DEFAULT 0 COMMENT '累计光点数=打卡数',
  `season`       TINYINT         NOT NULL DEFAULT 1 COMMENT '1春 2夏 3秋 4冬(服务端按日期算)',
  `year_count`   INT UNSIGNED    NOT NULL DEFAULT 0 COMMENT '今年打卡数',
  `year_target`  INT UNSIGNED    NOT NULL DEFAULT 300 COMMENT '今年目标(可调整)',
  `updated_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB COMMENT='拾光树进度';
