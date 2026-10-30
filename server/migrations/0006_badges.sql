-- 0006_badges.sql（MySQL 8 / utf8mb4）
-- S7：徽章定义 + 用户徽章（技术文档 4.2）。
-- 徽章不炫耀、只挂在自己的树上（产品 4.4）。

CREATE TABLE `badges` (
  `id`             INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `code`           VARCHAR(50)   NOT NULL,
  `name`           VARCHAR(30)   NOT NULL,
  `icon`           VARCHAR(30)   NOT NULL DEFAULT '' COMMENT '客户端图标名',
  `description`    VARCHAR(140)  NOT NULL DEFAULT '',
  `condition_json` JSON          NOT NULL COMMENT '{type:streak|total|category, category?, threshold}',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_code` (`code`)
) ENGINE=InnoDB COMMENT='徽章定义';

CREATE TABLE `user_badges` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `badge_id`   INT UNSIGNED    NOT NULL,
  `checkin_id` BIGINT UNSIGNED NULL COMMENT '触发来源打卡',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_badge` (`user_id`, `badge_id`),
  KEY `idx_badge` (`badge_id`)
) ENGINE=InnoDB COMMENT='用户徽章';

-- 系统通知需要可变文案（徽章名等）
ALTER TABLE `notifications`
  ADD COLUMN `extra` VARCHAR(140) NOT NULL DEFAULT '' COMMENT 'type=5 系统通知文案' AFTER `agg_count`;

-- 种子定义（第一版：连续 / 累计 / 品类累计 三类）
INSERT INTO `badges` (`code`, `name`, `icon`, `description`, `condition_json`) VALUES
  ('first_light', '第一颗光点', 'wb_sunny',   '完成第一次打卡',           '{"type":"total","threshold":1}'),
  ('streak_3',    '三日小苗',   'local_florist', '连续打卡 3 天',          '{"type":"streak","threshold":3}'),
  ('streak_7',    '七日不辍',   'eco',        '连续打卡 7 天',            '{"type":"streak","threshold":7}'),
  ('streak_30',   '整月同行',   'forest',     '连续打卡 30 天',           '{"type":"streak","threshold":30}'),
  ('total_50',    '拾光五十',   'auto_awesome', '累计打卡 50 次',         '{"type":"total","threshold":50}'),
  ('sport_10',    '风里跑了十次', 'directions_run', '运动打卡累计 10 次',  '{"type":"category","category":1,"threshold":10}'),
  ('read_10',     '十本闲书',   'menu_book',  '阅读打卡累计 10 次',       '{"type":"category","category":2,"threshold":10}'),
  ('travel_10',   '十个新地方', 'flight_takeoff', '旅行打卡累计 10 次',   '{"type":"category","category":3,"threshold":10}');
