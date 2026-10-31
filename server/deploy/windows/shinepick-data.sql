-- MySQL dump 10.13  Distrib 8.0.28, for Win64 (x86_64)
--
-- Host: 127.0.0.1    Database: shinepick
-- ------------------------------------------------------
-- Server version	8.0.28

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Dumping data for table `badges`
--

LOCK TABLES `badges` WRITE;
/*!40000 ALTER TABLE `badges` DISABLE KEYS */;
REPLACE INTO `badges` (`id`, `code`, `name`, `icon`, `description`, `condition_json`) VALUES (1,'first_light','第一颗光点','wb_sunny','完成第一次打卡','{\"type\": \"total\", \"threshold\": 1}'),(2,'streak_3','三日小苗','local_florist','连续打卡 3 天','{\"type\": \"streak\", \"threshold\": 3}'),(3,'streak_7','七日不辍','eco','连续打卡 7 天','{\"type\": \"streak\", \"threshold\": 7}'),(4,'streak_30','整月同行','forest','连续打卡 30 天','{\"type\": \"streak\", \"threshold\": 30}'),(5,'total_50','拾光五十','auto_awesome','累计打卡 50 次','{\"type\": \"total\", \"threshold\": 50}'),(6,'sport_10','风里跑了十次','directions_run','运动打卡累计 10 次','{\"type\": \"category\", \"category\": 1, \"threshold\": 10}'),(7,'read_10','十本闲书','menu_book','阅读打卡累计 10 次','{\"type\": \"category\", \"category\": 2, \"threshold\": 10}'),(8,'travel_10','十个新地方','flight_takeoff','旅行打卡累计 10 次','{\"type\": \"category\", \"category\": 3, \"threshold\": 10}');
/*!40000 ALTER TABLE `badges` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `blocks`
--

LOCK TABLES `blocks` WRITE;
/*!40000 ALTER TABLE `blocks` DISABLE KEYS */;
REPLACE INTO `blocks` (`id`, `blocker_id`, `blocked_id`, `created_at`) VALUES (4,25,24,'2026-10-30 23:26:23.593');
/*!40000 ALTER TABLE `blocks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `checkins`
--

LOCK TABLES `checkins` WRITE;
/*!40000 ALTER TABLE `checkins` DISABLE KEYS */;
REPLACE INTO `checkins` (`id`, `user_id`, `category`, `custom_name`, `content`, `image_urls`, `video_url`, `visibility`, `extra`, `checkin_date`, `status`, `created_at`) VALUES (1,2,1,NULL,'Off work ran 3 km, the riverside wind felt great.',NULL,'',2,NULL,'2026-10-30',0,'2026-10-30 06:50:38.275'),(2,2,2,NULL,'Finished half of the book, the part about the old man and the sea is great.',NULL,'',1,NULL,'2026-10-30',1,'2026-10-30 06:50:38.288'),(4,6,5,NULL,'The cat played with a new toy today.','[\"http://127.0.0.1:8080/static/images/u2_1793314238486_5.png\"]','',2,NULL,'2026-10-30',0,'2026-10-30 06:55:39.802'),(5,2,2,NULL,'今天读了《一本书》','[\"http://127.0.0.1:8080/static/images/u2_1793315233748_34.png\"]','',2,NULL,'2026-10-30',0,'2026-10-30 07:07:15.491'),(6,2,4,NULL,'今天和彭友吃了麻辣烫','[\"http://127.0.0.1:8080/static/images/u2_1793315275659_34.png\"]','',2,NULL,'2026-10-30',0,'2026-10-30 07:08:00.008'),(7,8,1,NULL,'Morning jog by the river, the wind felt great.','null','',2,NULL,'2026-10-30',0,'2026-10-30 07:37:24.228'),(8,8,2,NULL,'Read 20 pages at the cafe this afternoon.','null','',2,NULL,'2026-10-30',0,'2026-10-30 07:37:24.231'),(9,9,3,NULL,'Went to a new bookstore by the lake today.','null','',2,NULL,'2026-10-30',0,'2026-10-30 20:17:23.247'),(10,2,5,NULL,'和猫玩了一整天','[\"http://127.0.0.1:8080/static/images/u2_1793363201429_19.jpg\"]','',2,NULL,'2026-10-30',0,'2026-10-30 20:26:42.477'),(11,13,1,NULL,'evening walk, 2 km','null','',2,NULL,'2026-10-30',0,'2026-10-30 21:53:20.731'),(12,2,2,NULL,'有看了新书','[]','',2,NULL,'2026-10-30',0,'2026-10-30 22:39:20.185'),(13,2,2,NULL,'又看了一本新书','[]','',2,NULL,'2026-10-30',0,'2026-10-30 22:42:46.523'),(14,2,2,NULL,'又看了一本新书','[\"http://127.0.0.1:8080/static/images/u2_1793371380552_9.jpg\"]','',2,NULL,'2026-10-30',0,'2026-10-30 22:43:12.007'),(15,23,1,NULL,'s6 e2e run','null','',2,NULL,'2026-10-30',0,'2026-10-30 23:21:45.939'),(16,25,1,NULL,'s6 e2e run','null','',2,NULL,'2026-10-30',0,'2026-10-30 23:22:10.506'),(17,2,1,NULL,'今天跑了三公里，遇到了很棒的人','[\"http://127.0.0.1:8080/static/images/u2_1793428119820_11.png\"]','',2,NULL,'2026-10-31',0,'2026-10-31 14:28:41.656'),(20,28,6,'咖啡探店','今天去了一家新咖啡馆','null','',2,NULL,'2026-10-31',0,'2026-10-31 14:56:45.437');
/*!40000 ALTER TABLE `checkins` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `comments`
--

LOCK TABLES `comments` WRITE;
/*!40000 ALTER TABLE `comments` DISABLE KEYS */;
REPLACE INTO `comments` (`id`, `checkin_id`, `user_id`, `content`, `status`, `is_featured`, `created_at`) VALUES (1,10,12,'jiangbian running looks great, I will go tomorrow too',1,0,'2026-10-30 21:50:32.596'),(2,10,2,'welcome!',0,0,'2026-10-30 21:50:32.603'),(3,10,13,'ok',0,0,'2026-10-30 21:53:20.747'),(4,10,14,'nice one keep it up',0,1,'2026-10-30 21:53:29.952'),(5,11,17,'dart client e2e',0,0,'2026-10-30 22:00:53.375'),(6,11,2,'很棒啊',0,0,'2026-10-30 22:17:46.285'),(7,10,2,'可以一起来玩',0,0,'2026-10-30 22:18:02.217'),(8,14,18,'s6 notif test',0,0,'2026-10-30 23:17:45.334'),(9,14,18,'should fail',0,0,'2026-10-30 23:19:10.912'),(10,16,24,'hi from A',0,0,'2026-10-30 23:22:10.539'),(11,16,24,'unblocked hi',0,0,'2026-10-30 23:22:21.601'),(12,17,2,'有人一起跑步吗',0,0,'2026-10-31 14:29:05.971');
/*!40000 ALTER TABLE `comments` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `companion_relations`
--

LOCK TABLES `companion_relations` WRITE;
/*!40000 ALTER TABLE `companion_relations` DISABLE KEYS */;
REPLACE INTO `companion_relations` (`id`, `user_a`, `user_b`, `source_checkin_id`, `status`, `created_at`) VALUES (1,2,12,10,0,'2026-10-30 21:50:32.580'),(2,2,13,11,0,'2026-10-30 21:57:26.702'),(3,2,9,9,0,'2026-10-30 22:37:50.480'),(4,2,18,14,0,'2026-10-30 23:17:45.364'),(6,2,2,17,0,'2026-10-31 07:49:02.882');
/*!40000 ALTER TABLE `companion_relations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `notifications`
--

LOCK TABLES `notifications` WRITE;
/*!40000 ALTER TABLE `notifications` DISABLE KEYS */;
REPLACE INTO `notifications` (`id`, `user_id`, `type`, `actor_id`, `checkin_id`, `comment_id`, `agg_count`, `extra`, `is_read`, `created_at`) VALUES (5,2,1,18,14,NULL,1,'',1,'2026-10-30 23:19:10.849'),(6,2,2,18,14,NULL,1,'',1,'2026-10-30 23:19:10.854'),(7,2,1,NULL,14,NULL,1,'',1,'2026-10-30 23:19:10.875'),(8,2,3,18,14,NULL,1,'',1,'2026-10-30 23:19:10.902'),(9,2,4,18,14,9,1,'',1,'2026-10-30 23:19:10.914'),(10,25,1,NULL,16,NULL,2,'',1,'2026-10-30 23:22:10.533'),(11,25,4,24,16,10,1,'',1,'2026-10-30 23:22:10.541'),(12,25,4,24,16,11,1,'',0,'2026-10-30 23:22:21.603'),(13,2,5,NULL,NULL,NULL,1,'获得新徽章：「第一颗光点」，它只挂在你自己的树上',1,'2026-10-31 07:50:51.697'),(14,27,5,NULL,NULL,NULL,1,'获得新徽章：「第一颗光点」，它只挂在你自己的树上',0,'2026-10-31 14:55:04.174'),(15,28,5,NULL,NULL,NULL,1,'获得新徽章：「第一颗光点」，它只挂在你自己的树上',0,'2026-10-31 14:56:45.444');
/*!40000 ALTER TABLE `notifications` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `reactions`
--

LOCK TABLES `reactions` WRITE;
/*!40000 ALTER TABLE `reactions` DISABLE KEYS */;
REPLACE INTO `reactions` (`id`, `checkin_id`, `user_id`, `type`, `created_at`) VALUES (2,10,12,3,'2026-10-30 21:50:32.579'),(3,10,15,1,'2026-10-30 21:53:46.527'),(4,11,2,1,'2026-10-30 21:57:20.683'),(5,11,2,2,'2026-10-30 21:57:21.748'),(6,11,2,3,'2026-10-30 21:57:26.699'),(7,9,2,3,'2026-10-30 22:37:50.478'),(8,14,18,1,'2026-10-30 23:17:45.279'),(9,14,18,2,'2026-10-30 23:17:45.289'),(10,14,19,1,'2026-10-30 23:17:45.324'),(11,14,18,3,'2026-10-30 23:17:45.363'),(16,16,24,1,'2026-10-30 23:22:10.512'),(17,16,26,1,'2026-10-30 23:22:10.531'),(19,5,2,2,'2026-10-31 07:49:02.110'),(23,17,2,3,'2026-10-31 14:28:51.737'),(24,17,2,1,'2026-10-31 14:28:55.708'),(25,17,2,2,'2026-10-31 14:28:56.162');
/*!40000 ALTER TABLE `reactions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `reports`
--

LOCK TABLES `reports` WRITE;
/*!40000 ALTER TABLE `reports` DISABLE KEYS */;
REPLACE INTO `reports` (`id`, `reporter_id`, `target_type`, `target_id`, `reason`, `detail`, `status`, `created_at`) VALUES (1,26,1,16,1,'s6 e2e',0,'2026-10-30 23:22:10.585');
/*!40000 ALTER TABLE `reports` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `tree_progress`
--

LOCK TABLES `tree_progress` WRITE;
/*!40000 ALTER TABLE `tree_progress` DISABLE KEYS */;
REPLACE INTO `tree_progress` (`user_id`, `level`, `points`, `season`, `year_count`, `year_target`, `updated_at`) VALUES (2,3,9,0,9,300,'2026-10-31 14:28:41.658'),(6,1,1,0,1,300,'2026-10-30 06:55:39.804'),(8,1,2,0,2,300,'2026-10-30 07:37:24.231'),(9,1,1,0,1,300,'2026-10-30 20:17:23.250'),(13,1,1,0,1,300,'2026-10-30 21:53:20.732'),(23,1,1,0,1,300,'2026-10-30 23:21:45.941'),(25,1,1,0,1,300,'2026-10-30 23:22:10.507'),(28,1,1,0,1,300,'2026-10-31 14:56:45.439');
/*!40000 ALTER TABLE `tree_progress` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `user_badges`
--

LOCK TABLES `user_badges` WRITE;
/*!40000 ALTER TABLE `user_badges` DISABLE KEYS */;
REPLACE INTO `user_badges` (`id`, `user_id`, `badge_id`, `checkin_id`, `created_at`) VALUES (1,2,1,NULL,'2026-10-31 07:50:51.694'),(2,27,1,18,'2026-10-31 14:55:04.172'),(3,28,1,20,'2026-10-31 14:56:45.443');
/*!40000 ALTER TABLE `user_badges` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `user_secure`
--

LOCK TABLES `user_secure` WRITE;
/*!40000 ALTER TABLE `user_secure` DISABLE KEYS */;
REPLACE INTO `user_secure` (`user_id`, `phone_enc`, `salt`) VALUES (1,_binary 'OiOkYsS1w2xyYA2Ly9QOJ5J9k3KyuiI6ZwKkJzGznqNsYSvX5NPo','qEq3CLRU'),(2,_binary '8SmNSm0tkxqZ4G71YrGnxJNafLcKN4p6a4GfRe1MwJ+q28NUL0dm','Qtp9uQ15'),(3,_binary 'p5Iq4qoRtxfNqTVVjqnuC7t0olEmJhe1HYXKTPLMt7iXdX15kOaO','lauEMFfC'),(4,_binary 'DrRQTmWrDUwryOVWAth57SmzQ6qgjNh8VPDYSq4x02JDD13s1+ZB','XL3ba0H6'),(5,_binary 'OwcYm2mUvF4hmchwQpOFRWqSTmgzL75QWLPBo7H4x7Anc/we79kx','tXJP04nU'),(6,_binary 'iRSh8m1VWRQrX9kq+QrDL6dbbzOlID2rx5uV5KWh+0GaIXuOF2TU','kWBKvw3E'),(7,_binary 'KdEDxyL3RuNiLQGqNYjX4wJ5aUybgA30qjJeGzAonA2PRIjl/Te6','gYtBOZAI'),(8,_binary 'iAMZM1rN+/YtBJA6OfWIXo4XYUvENG1OZKjwRkzFiIdo377+bpDO','yObiSTct'),(9,_binary 'MsER1zI1Cy16V2lq2i7DdgobsvFKOYRoyjhqaKmbBK+8+jwvmrnM','hM6vie7y'),(10,_binary 'TqjaPJwG4Q5SdowiQPSfL7DQs/ZnrmE3n/sdx1leVDzrxxIQzBAg','QdON5fv7'),(11,_binary 'bx9I60x2t4HxlJZsyQNFgiBhrhCivrcBeeyVyj2CmTtGOWh2Iwht','dLJs6za3'),(12,_binary 'PhlN28gwlRH/Pf6m/deRlCLv6xgemZuRr17PHgntVU8QE0IFFQLO','0LVVARxd'),(13,_binary 'PSAchQM8zdIaWSeeizOixnWoRux+D0Su99h3qKVWr4LDZoiz2VvR','uucSXRTZ'),(14,_binary '+wutEjLQWL2MVg03u4vuJc+6fMOH1W2AJmTuyBybjo+wshtRRD8G','5AJrMs3N'),(15,_binary 'VIJZvP69ejzJ0CvX2FgwpqfViw/OvHi0Wgo2VKN1vrs8s9XhwcT1','gJyMIYMV'),(16,_binary 'ggEr7l5pjoMIEjnPKPXWlmwBBIyncWzGYIAFdYW+dBCrVoXqDxTM','YTxhteaR'),(17,_binary 'cbVDkKXlnIRlXdAR/Bo38bvsxu2QOIvEmtOsmgAJk7tlzK4gKF+b','uJnPiDlh'),(18,_binary 'C4jD722tiv9WZTEhVBgduUlppdN7y07zZQiZ+W2IdM9KkyWFP/Am','FbH9kfIU'),(19,_binary 'z50V9pZqSSEE+/6ZkXLYWo+zIVdLIj8fjmay/GP4aHqtFyRHHB7H','s4tIhRIW'),(20,_binary '/jSSi9Z+VbBlSpp9LXzHMgB38zW3vGAULiD7CVkKb85EDrM5dWCB','wdhZ46xs'),(21,_binary 'Kj8I09RojymkL4Y7+DF4haQM2zKS4T2jRogcggcsxrgPU06tt2oM','1nBbrIoj'),(22,_binary 'aGsrTDxw3yNYKV2oZwozoE3+c+5m53JakwrWDwzgpPlVL1jwBpHi','A6Djj0Ne'),(23,_binary '1y50oAQcxXQG8tl9bSTQVHIPcX0o5s/lKN0Oek7M+E0k7puqa/DI','7liZwFug'),(24,_binary 'xLwQQizXiOPRHUm3jmLcQSuWU4vkJ9eaIhCimq1desnM52ehYL1l','cxoO0Mj4'),(25,_binary 'QxMm19EsC9nIPcoFK+WOJGE1iyDf+qy9xYWT2o9zvYs1PE58PBx3','reLztL4M'),(26,_binary 's3A2aFjc9PSc0lbuxR0AaHcEwY/VlRy+nMcb0vyPs1r+OUmWpCbw','YSWRxspE'),(28,_binary 'zbhnrFZiS8/IMVpOPBpDt9uwq0gFHELQfH9+7pveh7SsbL8IuiLM','Wf259ERY'),(29,_binary '44fEPuLyH688n1OVpDZAngvYm7jzuBW1oOPsSkM7eUvltZeTBM8x','LMVjHgHJ');
/*!40000 ALTER TABLE `user_secure` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
REPLACE INTO `users` (`id`, `phone_hash`, `nickname`, `avatar_url`, `bio`, `gender`, `city`, `birthday`, `is_minor`, `status`, `created_at`, `updated_at`) VALUES (1,'ddeb5d3d4b367c0737657e9cad8ca030c3980c41020ef963dd5ed729f9b1fe29','拾光用户_1','','',0,'',NULL,0,0,'2026-10-29 21:13:02.909','2026-10-29 21:13:02.911'),(2,'003e8a111d227f9d3f1ac16bcaebf787eac1eb0d154de9de96ab2bbb33a9b89d','pig','http://127.0.0.1:8080/static/avatars/u2_1793285780639.png','诗人，认为诗是世界上最美的语言',0,'广州','1978-12-08',0,0,'2026-10-29 21:17:39.104','2026-10-29 22:56:35.855'),(3,'06d025cd1a07a5c2f7ae91d4ea172ed12f87ded764cb363a3c0a3c80d6be6e1d','拾光用户_3','','',0,'',NULL,0,0,'2026-10-29 21:22:36.806','2026-10-29 21:22:36.808'),(4,'afb50a922dfa316210bd9df002d796d506674c8c142ef32156d3dd2c89c1e172','拾光用户_4','','',0,'',NULL,0,0,'2026-10-30 06:50:38.447','2026-10-30 06:50:38.449'),(5,'7e0590b936db7dac8e354985a6134e9c7f4b80175d67b1626724c183642bb35d','拾光用户_5','','',0,'',NULL,0,0,'2026-10-30 06:52:49.899','2026-10-30 06:52:49.900'),(6,'683bc7d6791e55d7c4d468ec30ac9de205b2f0a28323da3870de9f24c60f9661','拾光用户_6','','',0,'',NULL,0,0,'2026-10-30 06:55:39.788','2026-10-30 06:55:39.790'),(7,'0b8125a09a8e0545710d468d2250c25bbaea56cfb5e702e117d585c7b5604832','拾光用户_7','','',0,'',NULL,0,0,'2026-10-30 06:56:05.874','2026-10-30 06:56:05.875'),(8,'1f210f2657959f5c1666f3abbbe4968fb55dd49dc5607550412acc077293a34d','拾光用户_8','','',0,'',NULL,0,0,'2026-10-30 07:37:24.214','2026-10-30 07:37:24.215'),(9,'adddf51ea7f9d22e80f0cf0c245f39223b05a7f433a65a7fa57230682bf79ad2','拾光用户_9','','',0,'',NULL,0,0,'2026-10-30 20:17:23.167','2026-10-30 20:17:23.170'),(10,'a491d17e108739b71c65208ffba0a1c4738fb5951e23a5b34cda6a702bbb036e','拾光用户_10','','',0,'',NULL,0,0,'2026-10-30 20:29:47.387','2026-10-30 20:29:47.389'),(11,'17586ab7db21f8ffd1906514e6288a2b555ae1a79241dcbbdffc09f5cf23a4a0','拾光用户_11','','',0,'',NULL,0,0,'2026-10-30 20:34:23.051','2026-10-30 20:34:23.052'),(12,'da2e6dc29e692b4d7f591e5d703bc1aac89e4e66cb1409e80a8d435e9081a8e5','拾光用户_12','','',0,'',NULL,0,0,'2026-10-30 21:50:32.548','2026-10-30 21:50:32.549'),(13,'31c2c10f510c07e87924d0add9e007e1cc8df97ca9012f89b769cd1ccb6dce68','拾光用户_13','','',0,'',NULL,0,0,'2026-10-30 21:53:20.705','2026-10-30 21:53:20.707'),(14,'6d86d2196430c91185150a8245eeb9541ae0c9895bd2245dc1687e91357c4f9c','拾光用户_14','','',0,'',NULL,0,0,'2026-10-30 21:53:29.877','2026-10-30 21:53:29.878'),(15,'07ca7c15d73e553fc9a548f41e87367fc48cf7b0a1df812185e682bf39943463','拾光用户_15','','',0,'',NULL,0,0,'2026-10-30 21:53:46.449','2026-10-30 21:53:46.450'),(16,'a841f7f5bce4e968040d58039d882b9acf85d29ac85e96337a2925503a964ff5','拾光用户_16','','',0,'',NULL,0,0,'2026-10-30 22:00:21.262','2026-10-30 22:00:21.264'),(17,'eb3cddcb6ff7fa6f559c948bd9c78ef9c3731ad556c70e307b96e1ed2cf10ec1','拾光用户_17','','',0,'',NULL,0,0,'2026-10-30 22:00:45.907','2026-10-30 22:00:45.909'),(18,'62f8df7f8336a4018395f372ba0ace5c431f0fb6ebd63d928493aba3a72a3587','拾光用户_18','','',0,'',NULL,0,0,'2026-10-30 23:17:45.248','2026-10-30 23:17:45.250'),(19,'db905cce9df863993f640dda4843b4eeb55c3006668f89d6dfe456d8bbe4efa8','拾光用户_19','','',0,'',NULL,0,0,'2026-10-30 23:17:45.318','2026-10-30 23:17:45.320'),(20,'2ebe9979f091ba6b642f7f24ac4cb955c080f63050c10276fe5db7672766743c','拾光用户_20','','',0,'',NULL,0,0,'2026-10-30 23:20:40.816','2026-10-30 23:20:40.818'),(21,'18d317a9b1b623885a9cf0f8b858cc7728c3a211868cbf67bb04ff1485d62883','拾光用户_21','','',0,'',NULL,0,0,'2026-10-30 23:20:40.824','2026-10-30 23:20:40.826'),(22,'089b8f36c48488c766a822907a3626256efd8e4bbd4b301f64806d38ff29468a','拾光用户_22','','',0,'',NULL,0,0,'2026-10-30 23:20:40.831','2026-10-30 23:20:40.833'),(23,'6d3f4fa33da504bb46506b2f33105e06d1a02ec75c7440bac0f9a79614857b28','拾光用户_23','','',0,'',NULL,0,0,'2026-10-30 23:21:45.856','2026-10-30 23:21:45.861'),(24,'c1812fb5e08ecfdd1869312a6849bd9bc2164ccc2d73f3441117df932ba8ca35','拾光用户_24','','',0,'',NULL,0,0,'2026-10-30 23:22:10.475','2026-10-30 23:22:10.477'),(25,'9c3233cefdb46f3dd5239a1f7adce9250606332769498e6443e29cc8cd631950','拾光用户_25','','',0,'',NULL,0,0,'2026-10-30 23:22:10.484','2026-10-30 23:22:10.486'),(26,'cdf5ad165af4724643bdbff627eab381834c30e95185dca791a182be11894a58','拾光用户_26','','',0,'',NULL,0,0,'2026-10-30 23:22:10.489','2026-10-30 23:22:10.491'),(28,'f4647b344ae8553774fd63524a4e2689a7416e0dfa099753b7ddaccbb523f557','拾光用户_28','','',0,'',NULL,0,0,'2026-10-31 14:56:45.325','2026-10-31 14:56:45.327'),(29,'f17d68d286c38fe4d777c0ed6b5635981f28f8991ff6d35ceb950fcdc1b9ccaf','拾光用户_29','','',0,'',NULL,0,0,'2026-10-31 14:57:27.925','2026-10-31 14:57:27.927');
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-10-31 21:41:01
-- AUTO_INCREMENT bump (generated by export_local_db.bat)
