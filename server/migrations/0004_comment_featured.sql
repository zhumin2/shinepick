-- 0004_comment_featured.sql（MySQL 8 / utf8mb4）
-- 留言卡片展示：作者可指定哪几条在打卡卡片上预览（产品 4.6「小便签」的可读性补足）。
-- 不改变「不显示留言总数」原则：卡片只展示内容，不展示数量。

ALTER TABLE `comments`
  ADD COLUMN `is_featured` TINYINT NOT NULL DEFAULT 0 COMMENT '1=作者指定在卡片展示' AFTER `status`,
  ADD KEY `idx_checkin_featured` (`checkin_id`, `is_featured`, `id`);
