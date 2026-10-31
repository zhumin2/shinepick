-- 0007_custom_category.sql（MySQL 8 / utf8mb4）
-- 自定义品类（产品 §3.2「自定义 | 需审核」）：category=6 时存用户起的名字。
-- 名称在服务端走内容审核（技术文档预留的 categories 表待品类体系丰富后再引入）。

ALTER TABLE `checkins`
  ADD COLUMN `custom_name` VARCHAR(20) NULL COMMENT '自定义品类名（category=6 时必填，已审核）' AFTER `category`;
