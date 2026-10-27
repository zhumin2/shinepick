-- 0001_init.sql（MySQL 8 / utf8mb4）
-- S1：用户账号体系。验证码走 Redis，不建表。

CREATE TABLE `users` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `phone_hash`  CHAR(64)        NOT NULL COMMENT 'SHA256(phone+盐)',
  `nickname`    VARCHAR(30)     NOT NULL DEFAULT '',
  `avatar_url`  VARCHAR(255)    NOT NULL DEFAULT '',
  `bio`         VARCHAR(140)    NOT NULL DEFAULT '',
  `gender`      TINYINT         NOT NULL DEFAULT 0 COMMENT '0未知 1男 2女',
  `city`        VARCHAR(50)     NOT NULL DEFAULT '',
  `birthday`    DATE            NULL,
  `is_minor`    TINYINT         NOT NULL DEFAULT 0 COMMENT '是否未成年',
  `status`      TINYINT         NOT NULL DEFAULT 0 COMMENT '0正常 1封禁',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_phone_hash` (`phone_hash`)
) ENGINE=InnoDB COMMENT='用户';

CREATE TABLE `user_secure` (
  `user_id`     BIGINT UNSIGNED NOT NULL,
  `phone_enc`   VARBINARY(255)  NOT NULL COMMENT 'AES-GCM 加密手机号(base64)',
  `salt`        VARCHAR(32)     NOT NULL,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB COMMENT='用户敏感信息（加密隔离）';
