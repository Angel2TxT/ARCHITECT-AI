-- MySQL dump 10.13  Distrib 8.0.46, for Linux (x86_64)
--
-- Host: localhost    Database: architect
-- ------------------------------------------------------
-- Server version	8.0.46

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
-- Current Database: `architect`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `architect` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `architect`;

--
-- Table structure for table `analyses`
--

DROP TABLE IF EXISTS `analyses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analyses` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `chat_id` varchar(36) DEFAULT NULL,
  `original_filename` varchar(255) NOT NULL,
  `source_path` varchar(512) NOT NULL,
  `annotated_path` varchar(512) DEFAULT NULL,
  `weights_path` varchar(512) NOT NULL,
  `pixels_per_meter` float NOT NULL,
  `confidence` float NOT NULL,
  `user_prompt` text NOT NULL,
  `status_text` varchar(255) NOT NULL,
  `is_demo_model` tinyint(1) NOT NULL,
  `detections_json` json DEFAULT NULL,
  `issues_json` json DEFAULT NULL,
  `counts_json` json DEFAULT NULL,
  `corrections_json` json DEFAULT NULL,
  `training_eligible` tinyint(1) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`),
  KEY `chat_id` (`chat_id`),
  KEY `ix_analyses_user_id` (`user_id`),
  KEY `ix_analyses_created_at` (`created_at`),
  CONSTRAINT `analyses_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `analyses_ibfk_2` FOREIGN KEY (`chat_id`) REFERENCES `chats` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `analyses`
--

LOCK TABLES `analyses` WRITE;
/*!40000 ALTER TABLE `analyses` DISABLE KEYS */;
/*!40000 ALTER TABLE `analyses` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `billing_receipts`
--

DROP TABLE IF EXISTS `billing_receipts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_receipts` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `receipt_number` varchar(32) NOT NULL,
  `user_id` bigint NOT NULL,
  `plan_id` int DEFAULT NULL,
  `plan_slug` varchar(32) NOT NULL DEFAULT '',
  `plan_name` varchar(80) NOT NULL DEFAULT '',
  `amount_cents` int NOT NULL DEFAULT '0',
  `currency` varchar(8) NOT NULL DEFAULT 'MXN',
  `billing_mode` varchar(16) NOT NULL DEFAULT 'demo',
  `payment_ref` varchar(128) DEFAULT NULL,
  `period_start` datetime DEFAULT NULL,
  `period_end` datetime DEFAULT NULL,
  `email_sent_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_billing_receipt_number` (`receipt_number`),
  KEY `ix_billing_receipts_user_id` (`user_id`),
  KEY `ix_billing_receipts_created_at` (`created_at`),
  KEY `fk_br_plan` (`plan_id`),
  CONSTRAINT `fk_br_plan` FOREIGN KEY (`plan_id`) REFERENCES `plans` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_br_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `billing_receipts`
--

LOCK TABLES `billing_receipts` WRITE;
/*!40000 ALTER TABLE `billing_receipts` DISABLE KEYS */;
/*!40000 ALTER TABLE `billing_receipts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `chats`
--

DROP TABLE IF EXISTS `chats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `chats` (
  `id` varchar(36) NOT NULL,
  `user_id` bigint NOT NULL,
  `title` varchar(120) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  `updated_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`),
  KEY `ix_chats_updated_at` (`updated_at`),
  KEY `ix_chats_user_id` (`user_id`),
  CONSTRAINT `chats_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `chats`
--

LOCK TABLES `chats` WRITE;
/*!40000 ALTER TABLE `chats` DISABLE KEYS */;
/*!40000 ALTER TABLE `chats` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `guest_trials`
--

DROP TABLE IF EXISTS `guest_trials`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `guest_trials` (
  `id` varchar(36) NOT NULL,
  `analyses_count` int NOT NULL,
  `asks_count` int NOT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  `last_seen_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `guest_trials`
--

LOCK TABLES `guest_trials` WRITE;
/*!40000 ALTER TABLE `guest_trials` DISABLE KEYS */;
/*!40000 ALTER TABLE `guest_trials` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `home_project_documents`
--

DROP TABLE IF EXISTS `home_project_documents`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `home_project_documents` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `project_id` varchar(36) NOT NULL,
  `user_id` bigint NOT NULL,
  `stage_number` int NOT NULL,
  `original_filename` varchar(255) NOT NULL,
  `stored_path` varchar(512) NOT NULL,
  `mime_type` varchar(120) NOT NULL,
  `file_size` int NOT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  `section_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `ix_home_project_documents_stage_number` (`stage_number`),
  KEY `ix_home_project_documents_created_at` (`created_at`),
  KEY `ix_home_project_documents_project_id` (`project_id`),
  KEY `ix_home_project_documents_user_id` (`user_id`),
  KEY `ix_home_project_documents_section_id` (`section_id`),
  CONSTRAINT `fk_hpd_section` FOREIGN KEY (`section_id`) REFERENCES `home_project_sections` (`id`) ON DELETE SET NULL,
  CONSTRAINT `home_project_documents_ibfk_1` FOREIGN KEY (`project_id`) REFERENCES `home_projects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `home_project_documents_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `home_project_documents`
--

LOCK TABLES `home_project_documents` WRITE;
/*!40000 ALTER TABLE `home_project_documents` DISABLE KEYS */;
/*!40000 ALTER TABLE `home_project_documents` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `home_project_events`
--

DROP TABLE IF EXISTS `home_project_events`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `home_project_events` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `project_id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `actor_user_id` bigint DEFAULT NULL,
  `event_type` varchar(64) NOT NULL,
  `section_id` bigint DEFAULT NULL,
  `document_id` bigint DEFAULT NULL,
  `comment_id` bigint DEFAULT NULL,
  `metadata_json` json DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_hpe_project_id` (`project_id`),
  KEY `ix_hpe_actor_user_id` (`actor_user_id`),
  KEY `ix_hpe_event_type` (`event_type`),
  KEY `ix_hpe_section_id` (`section_id`),
  KEY `ix_hpe_document_id` (`document_id`),
  KEY `ix_hpe_comment_id` (`comment_id`),
  KEY `ix_hpe_created_at` (`created_at`),
  CONSTRAINT `fk_hpe_actor` FOREIGN KEY (`actor_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_hpe_comment` FOREIGN KEY (`comment_id`) REFERENCES `home_project_section_comments` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_hpe_document` FOREIGN KEY (`document_id`) REFERENCES `home_project_documents` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_hpe_project` FOREIGN KEY (`project_id`) REFERENCES `home_projects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_hpe_section` FOREIGN KEY (`section_id`) REFERENCES `home_project_sections` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=36 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `home_project_events`
--

LOCK TABLES `home_project_events` WRITE;
/*!40000 ALTER TABLE `home_project_events` DISABLE KEYS */;
/*!40000 ALTER TABLE `home_project_events` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `home_project_invites`
--

DROP TABLE IF EXISTS `home_project_invites`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `home_project_invites` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `project_id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `email` varchar(255) NOT NULL,
  `role` enum('editor','viewer') NOT NULL DEFAULT 'editor',
  `token` varchar(64) NOT NULL,
  `invited_by` bigint NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` datetime NOT NULL,
  `accepted_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_home_project_invite_token` (`token`),
  KEY `ix_home_project_invites_project_id` (`project_id`),
  KEY `ix_home_project_invites_email` (`email`),
  KEY `fk_hpi_invited_by` (`invited_by`),
  CONSTRAINT `fk_hpi_invited_by` FOREIGN KEY (`invited_by`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_hpi_project` FOREIGN KEY (`project_id`) REFERENCES `home_projects` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `home_project_invites`
--

LOCK TABLES `home_project_invites` WRITE;
/*!40000 ALTER TABLE `home_project_invites` DISABLE KEYS */;
/*!40000 ALTER TABLE `home_project_invites` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `home_project_members`
--

DROP TABLE IF EXISTS `home_project_members`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `home_project_members` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `project_id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `user_id` bigint NOT NULL,
  `role` enum('editor','viewer') NOT NULL DEFAULT 'editor',
  `joined_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_home_project_member` (`project_id`,`user_id`),
  KEY `ix_home_project_members_project_id` (`project_id`),
  KEY `ix_home_project_members_user_id` (`user_id`),
  CONSTRAINT `fk_hpm_project` FOREIGN KEY (`project_id`) REFERENCES `home_projects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_hpm_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `home_project_members`
--

LOCK TABLES `home_project_members` WRITE;
/*!40000 ALTER TABLE `home_project_members` DISABLE KEYS */;
/*!40000 ALTER TABLE `home_project_members` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `home_project_section_comments`
--

DROP TABLE IF EXISTS `home_project_section_comments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `home_project_section_comments` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `section_id` bigint NOT NULL,
  `user_id` bigint NOT NULL,
  `body` text NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_hpsc_section_id` (`section_id`),
  KEY `ix_hpsc_user_id` (`user_id`),
  KEY `ix_hpsc_created_at` (`created_at`),
  CONSTRAINT `fk_hpsc_section` FOREIGN KEY (`section_id`) REFERENCES `home_project_sections` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_hpsc_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `home_project_section_comments`
--

LOCK TABLES `home_project_section_comments` WRITE;
/*!40000 ALTER TABLE `home_project_section_comments` DISABLE KEYS */;
/*!40000 ALTER TABLE `home_project_section_comments` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `home_project_sections`
--

DROP TABLE IF EXISTS `home_project_sections`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `home_project_sections` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `project_id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `stage_number` int NOT NULL,
  `title` varchar(200) NOT NULL,
  `description` text NOT NULL,
  `sort_order` int NOT NULL DEFAULT '0',
  `status` enum('pending','in_progress','needs_details','needs_correction','completed') NOT NULL DEFAULT 'pending',
  `created_by` bigint DEFAULT NULL,
  `is_catalog` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `assigned_to_user_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `ix_home_project_sections_project_id` (`project_id`),
  KEY `ix_home_project_sections_stage_number` (`stage_number`),
  KEY `fk_hps_created_by` (`created_by`),
  KEY `ix_home_project_sections_assigned_to` (`assigned_to_user_id`),
  CONSTRAINT `fk_hps_assigned_to` FOREIGN KEY (`assigned_to_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_hps_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_hps_project` FOREIGN KEY (`project_id`) REFERENCES `home_projects` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=297 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `home_project_sections`
--

LOCK TABLES `home_project_sections` WRITE;
/*!40000 ALTER TABLE `home_project_sections` DISABLE KEYS */;
/*!40000 ALTER TABLE `home_project_sections` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `home_project_stages`
--

DROP TABLE IF EXISTS `home_project_stages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `home_project_stages` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `project_id` varchar(36) NOT NULL,
  `stage_number` int NOT NULL,
  `slug` varchar(40) NOT NULL,
  `title` varchar(120) NOT NULL,
  `status` enum('pending','in_progress','completed','blocked') NOT NULL,
  `checklist_json` json DEFAULT NULL,
  `notes` text NOT NULL,
  `ai_guidance` text NOT NULL,
  `analysis_id` bigint DEFAULT NULL,
  `started_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_home_project_stage` (`project_id`,`stage_number`),
  KEY `analysis_id` (`analysis_id`),
  KEY `ix_home_project_stages_stage_number` (`stage_number`),
  KEY `ix_home_project_stages_project_id` (`project_id`),
  CONSTRAINT `home_project_stages_ibfk_1` FOREIGN KEY (`project_id`) REFERENCES `home_projects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `home_project_stages_ibfk_2` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=46 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `home_project_stages`
--

LOCK TABLES `home_project_stages` WRITE;
/*!40000 ALTER TABLE `home_project_stages` DISABLE KEYS */;
/*!40000 ALTER TABLE `home_project_stages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `home_projects`
--

DROP TABLE IF EXISTS `home_projects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `home_projects` (
  `id` varchar(36) NOT NULL,
  `user_id` bigint NOT NULL,
  `name` varchar(160) NOT NULL,
  `client_name` varchar(120) NOT NULL,
  `location` varchar(200) NOT NULL,
  `description` text NOT NULL,
  `status` enum('active','on_hold','completed','canceled') NOT NULL,
  `current_stage` int NOT NULL,
  `metadata_json` json DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  `updated_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`),
  KEY `ix_home_projects_status` (`status`),
  KEY `ix_home_projects_user_id` (`user_id`),
  KEY `ix_home_projects_created_at` (`created_at`),
  CONSTRAINT `home_projects_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `home_projects`
--

LOCK TABLES `home_projects` WRITE;
/*!40000 ALTER TABLE `home_projects` DISABLE KEYS */;
/*!40000 ALTER TABLE `home_projects` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `messages`
--

DROP TABLE IF EXISTS `messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `messages` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `chat_id` varchar(36) NOT NULL,
  `role` varchar(16) NOT NULL,
  `content` json NOT NULL,
  `analysis_id` bigint DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`),
  KEY `analysis_id` (`analysis_id`),
  KEY `ix_messages_created_at` (`created_at`),
  KEY `ix_messages_chat_id` (`chat_id`),
  CONSTRAINT `messages_ibfk_1` FOREIGN KEY (`chat_id`) REFERENCES `chats` (`id`) ON DELETE CASCADE,
  CONSTRAINT `messages_ibfk_2` FOREIGN KEY (`analysis_id`) REFERENCES `analyses` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=28 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `messages`
--

LOCK TABLES `messages` WRITE;
/*!40000 ALTER TABLE `messages` DISABLE KEYS */;
/*!40000 ALTER TABLE `messages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `plans`
--

DROP TABLE IF EXISTS `plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `plans` (
  `id` int NOT NULL AUTO_INCREMENT,
  `slug` varchar(32) NOT NULL,
  `name` varchar(80) NOT NULL,
  `description` text NOT NULL,
  `price_monthly_cents` int NOT NULL,
  `analyses_limit_monthly` int NOT NULL,
  `allow_real_model` tinyint(1) NOT NULL,
  `max_file_mb` int NOT NULL,
  `sort_order` int NOT NULL,
  `is_public` tinyint(1) NOT NULL,
  `features` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ix_plans_slug` (`slug`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `plans`
--

LOCK TABLES `plans` WRITE;
/*!40000 ALTER TABLE `plans` DISABLE KEYS */;
INSERT INTO `plans` VALUES (1,'free','Gratis','Ideal para conocer ARCHITECT sin compromiso.',0,5,0,5,0,1,'{\"export\": false, \"support\": \"comunidad\", \"benefits\": [\"5 análisis de planos al mes\", \"20 preguntas al chat / mes\", \"1 proyecto casa hogar · 1 GB docs\", \"Modelo demo\", \"Archivos hasta 5 MB por carga\"], \"ideal_for\": \"Probar la plataforma\", \"mobile_app\": false, \"storage_gb\": 1, \"max_projects\": 1, \"team_invites\": false, \"home_projects\": true, \"asks_limit_monthly\": 20}'),(2,'starter','Starter','Ideal para estudiantes y proyectos pequeños.',30000,30,1,10,1,1,'{\"export\": true, \"support\": \"email\", \"benefits\": [\"30 análisis de planos al mes\", \"Hasta 3 proyectos casa hogar · 5 GB\", \"Análisis con modelo real (imagen, PDF, DXF/DWG)\", \"Exportar reportes PDF\", \"Archivos hasta 10 MB · Soporte por correo\"], \"ideal_for\": \"Estudiantes y freelancers\", \"mobile_app\": false, \"storage_gb\": 5, \"max_projects\": 3, \"team_invites\": false, \"home_projects\": true, \"asks_limit_monthly\": 200}'),(3,'pro','Pro','Ideal para obra y despacho individual.',50000,150,1,20,2,1,'{\"export\": true, \"support\": \"prioritario\", \"benefits\": [\"150 análisis de planos al mes\", \"Hasta 20 proyectos · 25 GB docs\", \"IA con normas de Chiapas e indexación\", \"App móvil ARCHITECT incluida\", \"Archivos hasta 20 MB · Soporte prioritario\"], \"ideal_for\": \"Profesionales en obra\", \"mobile_app\": true, \"storage_gb\": 25, \"recommended\": true, \"max_projects\": 20, \"team_invites\": false, \"home_projects\": true, \"asks_limit_monthly\": 9999}'),(4,'enterprise','Enterprise','Ideal para equipos y despachos con alto volumen.',90000,9999,1,50,3,1,'{\"sla\": true, \"export\": true, \"support\": \"dedicado\", \"benefits\": [\"Análisis y chat ilimitados\", \"Proyectos ilimitados · 100 GB docs\", \"Equipos, invitaciones y colaboración\", \"App móvil ARCHITECT incluida\", \"Archivos hasta 50 MB · Soporte dedicado con SLA\"], \"ideal_for\": \"Equipos y constructoras\", \"mobile_app\": true, \"storage_gb\": 100, \"max_projects\": 9999, \"team_invites\": true, \"home_projects\": true, \"asks_limit_monthly\": 9999}');
/*!40000 ALTER TABLE `plans` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `subscriptions`
--

DROP TABLE IF EXISTS `subscriptions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `subscriptions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `plan_id` int NOT NULL,
  `status` enum('active','trialing','past_due','canceled','expired') NOT NULL,
  `current_period_start` datetime NOT NULL,
  `current_period_end` datetime NOT NULL,
  `stripe_customer_id` varchar(64) DEFAULT NULL,
  `stripe_subscription_id` varchar(64) DEFAULT NULL,
  `canceled_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_id` (`user_id`),
  KEY `plan_id` (`plan_id`),
  CONSTRAINT `subscriptions_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `subscriptions_ibfk_2` FOREIGN KEY (`plan_id`) REFERENCES `plans` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `subscriptions`
--

LOCK TABLES `subscriptions` WRITE;
/*!40000 ALTER TABLE `subscriptions` DISABLE KEYS */;
INSERT INTO `subscriptions` VALUES (1,1,4,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_1',NULL,NULL,'2026-06-04 03:26:47'),(2,2,2,'active','2026-08-01 00:00:00','2026-08-31 23:59:59','demo_cus_2','demo_sub_gomxwEgEVPDJL12i',NULL,'2026-07-02 05:25:18'),(3,3,3,'active','2026-08-01 00:00:00','2026-08-31 23:59:59','demo_cus_3',NULL,NULL,'2026-07-02 06:16:29'),(4,4,1,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_4',NULL,NULL,'2026-07-05 00:51:44'),(5,5,1,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_5',NULL,NULL,'2026-07-05 00:53:11'),(6,6,1,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_6',NULL,NULL,'2026-07-05 01:52:35'),(7,7,1,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_7',NULL,NULL,'2026-07-05 01:53:05'),(8,8,2,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_8','demo_sub_OZ9XpZw_41V4Zrvg',NULL,'2026-07-05 01:59:43'),(9,9,1,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_9',NULL,NULL,'2026-07-05 02:01:34'),(10,10,2,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_10','demo_sub_1B9bsSZ4tOUAIMej',NULL,'2026-07-05 02:31:46'),(11,11,4,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_11','demo_sub_9YV8lJgJvTKaAF05',NULL,'2026-07-05 03:00:21'),(12,12,2,'active','2026-07-01 00:00:00','2026-07-31 23:59:59','demo_cus_12','demo_sub_7Bb05oPq16T8h5F4',NULL,'2026-07-05 03:06:41');
/*!40000 ALTER TABLE `subscriptions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `support_messages`
--

DROP TABLE IF EXISTS `support_messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `support_messages` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint NOT NULL,
  `author_id` bigint NOT NULL,
  `body` text NOT NULL,
  `is_staff` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_support_messages_ticket_id` (`ticket_id`),
  KEY `ix_support_messages_author_id` (`author_id`),
  KEY `ix_support_messages_created_at` (`created_at`),
  CONSTRAINT `fk_sm_author` FOREIGN KEY (`author_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_sm_ticket` FOREIGN KEY (`ticket_id`) REFERENCES `support_tickets` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `support_messages`
--

LOCK TABLES `support_messages` WRITE;
/*!40000 ALTER TABLE `support_messages` DISABLE KEYS */;
/*!40000 ALTER TABLE `support_messages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `support_tickets`
--

DROP TABLE IF EXISTS `support_tickets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `support_tickets` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `assigned_to` bigint DEFAULT NULL,
  `subject` varchar(160) NOT NULL,
  `status` enum('open','pending','resolved','closed') NOT NULL DEFAULT 'open',
  `priority` enum('normal','high') NOT NULL DEFAULT 'normal',
  `related_chat_id` varchar(36) DEFAULT NULL,
  `related_analysis_id` bigint DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_support_tickets_user_id` (`user_id`),
  KEY `ix_support_tickets_assigned_to` (`assigned_to`),
  KEY `ix_support_tickets_status` (`status`),
  KEY `ix_support_tickets_created_at` (`created_at`),
  KEY `ix_support_tickets_updated_at` (`updated_at`),
  KEY `fk_st_analysis` (`related_analysis_id`),
  CONSTRAINT `fk_st_analysis` FOREIGN KEY (`related_analysis_id`) REFERENCES `analyses` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_st_assignee` FOREIGN KEY (`assigned_to`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_st_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `support_tickets`
--

LOCK TABLES `support_tickets` WRITE;
/*!40000 ALTER TABLE `support_tickets` DISABLE KEYS */;
/*!40000 ALTER TABLE `support_tickets` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `usage_records`
--

DROP TABLE IF EXISTS `usage_records`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `usage_records` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `period_key` varchar(7) NOT NULL,
  `analyses_count` int NOT NULL,
  `updated_at` datetime NOT NULL DEFAULT (now()),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_usage_period` (`user_id`,`period_key`),
  KEY `ix_usage_records_period_key` (`period_key`),
  KEY `ix_usage_records_user_id` (`user_id`),
  CONSTRAINT `usage_records_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `usage_records`
--

LOCK TABLES `usage_records` WRITE;
/*!40000 ALTER TABLE `usage_records` DISABLE KEYS */;
/*!40000 ALTER TABLE `usage_records` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `email` varchar(255) NOT NULL,
  `password_hash` varchar(255) DEFAULT NULL,
  `full_name` varchar(120) NOT NULL,
  `role` enum('admin','support','user') NOT NULL DEFAULT 'user',
  `is_active` tinyint(1) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT (now()),
  `updated_at` datetime NOT NULL DEFAULT (now()),
  `oauth_provider` varchar(32) DEFAULT NULL,
  `oauth_subject` varchar(128) DEFAULT NULL,
  `avatar_url` varchar(512) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ix_users_email` (`email`),
  UNIQUE KEY `uq_users_oauth` (`oauth_provider`,`oauth_subject`),
  KEY `ix_users_role` (`role`)
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES (1,'admin@planoia.com','$2b$12$xndb.aQjF4IoProGSXZ.t.WSLoAMFkBK97GWuit1PHuQoUE0supDm','Administrador','admin',1,'2026-06-04 03:26:47','2026-06-04 03:26:47',NULL,NULL,NULL),(2,'godgosth12@gmail.com','$2b$12$pvA/0WffeVCxjXktWP8cceAslVSySZ3CPl7eB2xHGcyX5dzcBHOna','Angel','user',1,'2026-07-02 05:25:18','2026-08-03 09:02:34',NULL,NULL,'/media/avatars/2.jpg?v=1785747754'),(3,'admin@architect.local','$2b$12$iqBB/VGE8m.n.SVz.84nu.yVQrELAWs9oY3YZ./y37j.u.8nlT7sq','Administrador','admin',1,'2026-07-02 06:16:29','2026-08-04 16:37:06',NULL,NULL,NULL),(4,'billing-test@architect.local','$2b$12$SMhxQGihEOeyYvxocp6To.MiTaSD.KBS/UJd4UxR/SyWqwG5MZuna','Billing Test','user',1,'2026-07-05 00:51:44','2026-07-05 00:51:44',NULL,NULL,NULL),(5,'billing-test-1783212783@architect.local','$2b$12$2VxfXK3ys8/GmZCvjJOEHuFboo6pQpQhE1bWryx2vWzH0v5l1pH.e','Billing Test','user',1,'2026-07-05 00:53:11','2026-07-05 00:53:11',NULL,NULL,NULL),(6,'billing-test-1783216355@architect.local','$2b$12$ElgNLW5jbVzYMhEwL14JBuDoF22UmzU4jj9E3FHeWGttmWa/ZQ6ee','Billing Test','user',1,'2026-07-05 01:52:35','2026-07-05 01:52:35',NULL,NULL,NULL),(7,'billing-test-1783216374@architect.local','$2b$12$VbTfIbjBc3ToyzS5PR3JH.u13.5WeRllzGUI7ONqufWj/I80pHnRC','Billing Test','user',1,'2026-07-05 01:53:05','2026-07-05 01:53:05',NULL,NULL,NULL),(8,'pdf-test-1783216783.4494622@architect.local','$2b$12$EqGEpVFjo2oHA4Nkfsw5..3l54Lbd4/zQsIVJbzzIzlr0CAQUmCE6','PDF Test','user',1,'2026-07-05 01:59:43','2026-07-05 01:59:43',NULL,NULL,NULL),(9,'billing-test-1783216885@architect.local','$2b$12$hIJzAmr4MYtKU25niHSyDed/zkGisrVD7WbidA3ihZSGOobg6S21W','Billing Test','user',1,'2026-07-05 02:01:34','2026-07-05 02:01:34',NULL,NULL,NULL),(10,'lopezteujilloxd@gmail.com','$2b$12$OGZQ7JbydcWQo5KvElpyXOLnIWfcNtonasj5q5VeNYpkRtNwv2miy','Angel Emmanuel Trujillo Lopez','user',1,'2026-07-05 02:31:46','2026-07-05 02:31:46',NULL,NULL,NULL),(11,'wilberthlp4@gmail.com','$2b$12$GLsdV/ZiNCBa8SE/etYi3O7Hlo/6lyBs0.7D/sxJdkihvJa9.WI02','Wilberth De Jesús López Peñate','user',1,'2026-07-05 03:00:21','2026-07-05 03:00:21',NULL,NULL,NULL),(12,'lopeztrujilloxd@gmail.com','$2b$12$0C7dpw6Yqh3JVY5kEAqUouY1SE9kYfpMpC5KN/TvLwzYbCENr55Ly','Angel Emmanuel Trujillo Lopez','user',1,'2026-07-05 03:06:41','2026-07-05 03:06:41',NULL,NULL,NULL);
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping routines for database 'architect'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-08-06  4:58:13
