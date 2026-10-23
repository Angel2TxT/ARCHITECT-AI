-- ARCHITECT — Base de datos MySQL completa (Esquema + Datos iniciales + Proyecto Demo)
-- Generado automáticamente con soporte para todas las funcionalidades
-- Compatible con MySQL 8.0+

SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';
SET time_zone = '+00:00';

CREATE DATABASE IF NOT EXISTS `architect` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `architect`;

-- ========================================================
-- 1. ESTRUCTURA DE TABLAS (DDL)
-- ========================================================

DROP TABLE IF EXISTS `plans`;
CREATE TABLE plans (
	id INTEGER NOT NULL AUTO_INCREMENT, 
	slug VARCHAR(32) NOT NULL, 
	name VARCHAR(80) NOT NULL, 
	description TEXT NOT NULL, 
	price_monthly_cents INTEGER NOT NULL, 
	analyses_limit_monthly INTEGER NOT NULL, 
	allow_real_model BOOL NOT NULL, 
	max_file_mb INTEGER NOT NULL, 
	sort_order INTEGER NOT NULL, 
	is_public BOOL NOT NULL, 
	features JSON, 
	PRIMARY KEY (id)
);

DROP TABLE IF EXISTS `users`;
CREATE TABLE users (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	email VARCHAR(255) NOT NULL, 
	password_hash VARCHAR(255), 
	full_name VARCHAR(120) NOT NULL, 
	`role` ENUM('admin','support','user') NOT NULL, 
	is_active BOOL NOT NULL, 
	oauth_provider VARCHAR(32), 
	oauth_subject VARCHAR(128), 
	avatar_url VARCHAR(512), 
	created_at DATETIME NOT NULL DEFAULT now(), 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	CONSTRAINT uq_users_oauth UNIQUE (oauth_provider, oauth_subject)
);

DROP TABLE IF EXISTS `guest_trials`;
CREATE TABLE guest_trials (
	id VARCHAR(36) NOT NULL, 
	analyses_count INTEGER NOT NULL, 
	asks_count INTEGER NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	last_seen_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id)
);

DROP TABLE IF EXISTS `subscriptions`;
CREATE TABLE subscriptions (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	user_id BIGINT NOT NULL, 
	plan_id INTEGER NOT NULL, 
	status ENUM('active','trialing','past_due','canceled','expired') NOT NULL, 
	current_period_start DATETIME NOT NULL, 
	current_period_end DATETIME NOT NULL, 
	stripe_customer_id VARCHAR(64), 
	stripe_subscription_id VARCHAR(64), 
	canceled_at DATETIME, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	UNIQUE (user_id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(plan_id) REFERENCES plans (id)
);

DROP TABLE IF EXISTS `billing_receipts`;
CREATE TABLE billing_receipts (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	receipt_number VARCHAR(32) NOT NULL, 
	user_id BIGINT NOT NULL, 
	plan_id INTEGER, 
	plan_slug VARCHAR(32) NOT NULL, 
	plan_name VARCHAR(80) NOT NULL, 
	amount_cents INTEGER NOT NULL, 
	currency VARCHAR(8) NOT NULL, 
	billing_mode VARCHAR(16) NOT NULL, 
	payment_ref VARCHAR(128), 
	period_start DATETIME, 
	period_end DATETIME, 
	email_sent_at DATETIME, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(plan_id) REFERENCES plans (id)
);

DROP TABLE IF EXISTS `usage_records`;
CREATE TABLE usage_records (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	user_id BIGINT NOT NULL, 
	period_key VARCHAR(7) NOT NULL, 
	analyses_count INTEGER NOT NULL, 
	asks_count INTEGER NOT NULL, 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	CONSTRAINT uq_usage_period UNIQUE (user_id, period_key), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS `chats`;
CREATE TABLE chats (
	id VARCHAR(36) NOT NULL, 
	user_id BIGINT NOT NULL, 
	title VARCHAR(120) NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS `messages`;
CREATE TABLE messages (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	chat_id VARCHAR(36) NOT NULL, 
	`role` VARCHAR(16) NOT NULL, 
	content JSON NOT NULL, 
	analysis_id BIGINT, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(chat_id) REFERENCES chats (id) ON DELETE CASCADE, 
	FOREIGN KEY(analysis_id) REFERENCES analyses (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `analyses`;
CREATE TABLE analyses (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	user_id BIGINT NOT NULL, 
	chat_id VARCHAR(36), 
	original_filename VARCHAR(255) NOT NULL, 
	source_path VARCHAR(512) NOT NULL, 
	annotated_path VARCHAR(512), 
	weights_path VARCHAR(512) NOT NULL, 
	pixels_per_meter FLOAT NOT NULL, 
	confidence FLOAT NOT NULL, 
	user_prompt TEXT NOT NULL, 
	status_text VARCHAR(255) NOT NULL, 
	is_demo_model BOOL NOT NULL, 
	detections_json JSON, 
	issues_json JSON, 
	counts_json JSON, 
	corrections_json JSON, 
	training_eligible BOOL NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(chat_id) REFERENCES chats (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `home_projects`;
CREATE TABLE home_projects (
	id VARCHAR(36) NOT NULL, 
	user_id BIGINT NOT NULL, 
	name VARCHAR(160) NOT NULL, 
	client_name VARCHAR(120) NOT NULL, 
	location VARCHAR(200) NOT NULL, 
	latitude FLOAT, 
	longitude FLOAT, 
	description TEXT NOT NULL, 
	status ENUM('active','on_hold','completed','canceled') NOT NULL, 
	current_stage INTEGER NOT NULL, 
	metadata_json JSON, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS `home_project_stages`;
CREATE TABLE home_project_stages (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	project_id VARCHAR(36) NOT NULL, 
	stage_number INTEGER NOT NULL, 
	slug VARCHAR(40) NOT NULL, 
	title VARCHAR(120) NOT NULL, 
	status ENUM('pending','in_progress','completed','blocked') NOT NULL, 
	checklist_json JSON, 
	notes TEXT NOT NULL, 
	ai_guidance TEXT NOT NULL, 
	analysis_id BIGINT, 
	started_at DATETIME, 
	completed_at DATETIME, 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	CONSTRAINT uq_home_project_stage UNIQUE (project_id, stage_number), 
	FOREIGN KEY(project_id) REFERENCES home_projects (id) ON DELETE CASCADE, 
	FOREIGN KEY(analysis_id) REFERENCES analyses (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `home_project_sections`;
CREATE TABLE home_project_sections (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	project_id VARCHAR(36) NOT NULL, 
	stage_number INTEGER NOT NULL, 
	title VARCHAR(200) NOT NULL, 
	description TEXT NOT NULL, 
	catalog_key VARCHAR(80), 
	slots_json JSON, 
	sort_order INTEGER NOT NULL, 
	status ENUM('pending','in_progress','needs_details','needs_correction','completed') NOT NULL, 
	created_by BIGINT, 
	assigned_to_user_id BIGINT, 
	is_catalog BOOL NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(project_id) REFERENCES home_projects (id) ON DELETE CASCADE, 
	FOREIGN KEY(created_by) REFERENCES users (id) ON DELETE SET NULL, 
	FOREIGN KEY(assigned_to_user_id) REFERENCES users (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `home_project_section_comments`;
CREATE TABLE home_project_section_comments (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	section_id BIGINT NOT NULL, 
	user_id BIGINT NOT NULL, 
	body TEXT NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(section_id) REFERENCES home_project_sections (id) ON DELETE CASCADE, 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS `home_project_documents`;
CREATE TABLE home_project_documents (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	project_id VARCHAR(36) NOT NULL, 
	user_id BIGINT NOT NULL, 
	stage_number INTEGER NOT NULL, 
	section_id BIGINT, 
	slot_key VARCHAR(80), 
	original_filename VARCHAR(255) NOT NULL, 
	stored_path VARCHAR(512) NOT NULL, 
	mime_type VARCHAR(120) NOT NULL, 
	file_size INTEGER NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(project_id) REFERENCES home_projects (id) ON DELETE CASCADE, 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(section_id) REFERENCES home_project_sections (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `home_project_members`;
CREATE TABLE home_project_members (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	project_id VARCHAR(36) NOT NULL, 
	user_id BIGINT NOT NULL, 
	`role` ENUM('editor','viewer') NOT NULL, 
	joined_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	CONSTRAINT uq_home_project_member UNIQUE (project_id, user_id), 
	FOREIGN KEY(project_id) REFERENCES home_projects (id) ON DELETE CASCADE, 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS `home_project_invites`;
CREATE TABLE home_project_invites (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	project_id VARCHAR(36) NOT NULL, 
	email VARCHAR(255) NOT NULL, 
	`role` ENUM('editor','viewer') NOT NULL, 
	token VARCHAR(64) NOT NULL, 
	invited_by BIGINT NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	expires_at DATETIME NOT NULL, 
	accepted_at DATETIME, 
	PRIMARY KEY (id), 
	FOREIGN KEY(project_id) REFERENCES home_projects (id) ON DELETE CASCADE, 
	FOREIGN KEY(invited_by) REFERENCES users (id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS `home_project_events`;
CREATE TABLE home_project_events (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	project_id VARCHAR(36) NOT NULL, 
	actor_user_id BIGINT, 
	event_type ENUM('section_assigned','section_status_changed','section_reopened','section_comment_added','section_comment_deleted','document_uploaded','document_deleted','member_invited','member_joined','member_removed','stage_completed','stage_reopened','stage_advanced','ai_review_created','ai_finding_updated','budget_updated') NOT NULL, 
	section_id BIGINT, 
	document_id BIGINT, 
	comment_id BIGINT, 
	metadata_json JSON, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(project_id) REFERENCES home_projects (id) ON DELETE CASCADE, 
	FOREIGN KEY(actor_user_id) REFERENCES users (id) ON DELETE SET NULL, 
	FOREIGN KEY(section_id) REFERENCES home_project_sections (id) ON DELETE SET NULL, 
	FOREIGN KEY(document_id) REFERENCES home_project_documents (id) ON DELETE SET NULL, 
	FOREIGN KEY(comment_id) REFERENCES home_project_section_comments (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `home_project_ai_reviews`;
CREATE TABLE home_project_ai_reviews (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	project_id VARCHAR(36) NOT NULL, 
	stage_number INTEGER NOT NULL, 
	section_id BIGINT, 
	document_id BIGINT, 
	analysis_id BIGINT, 
	created_by BIGINT, 
	status ENUM('open','resolved','dismissed') NOT NULL, 
	scope_json JSON, 
	exclusions_json JSON, 
	verdict_json JSON, 
	findings_json JSON, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(project_id) REFERENCES home_projects (id) ON DELETE CASCADE, 
	FOREIGN KEY(section_id) REFERENCES home_project_sections (id) ON DELETE SET NULL, 
	FOREIGN KEY(document_id) REFERENCES home_project_documents (id) ON DELETE SET NULL, 
	FOREIGN KEY(analysis_id) REFERENCES analyses (id) ON DELETE SET NULL, 
	FOREIGN KEY(created_by) REFERENCES users (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `refund_requests`;
CREATE TABLE refund_requests (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	user_id BIGINT NOT NULL, 
	receipt_id BIGINT, 
	amount_cents INTEGER NOT NULL, 
	currency VARCHAR(8) NOT NULL, 
	status ENUM('pending','approved','rejected') NOT NULL, 
	eligible_at_request BOOL NOT NULL, 
	reason TEXT NOT NULL, 
	admin_note TEXT NOT NULL, 
	eligibility_json JSON, 
	reviewed_by BIGINT, 
	reviewed_at DATETIME, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(receipt_id) REFERENCES billing_receipts (id) ON DELETE SET NULL, 
	FOREIGN KEY(reviewed_by) REFERENCES users (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `support_tickets`;
CREATE TABLE support_tickets (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	user_id BIGINT NOT NULL, 
	assigned_to BIGINT, 
	subject VARCHAR(160) NOT NULL, 
	status ENUM('open','pending','resolved','closed') NOT NULL, 
	priority ENUM('normal','high') NOT NULL, 
	related_chat_id VARCHAR(36), 
	related_analysis_id BIGINT, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(assigned_to) REFERENCES users (id) ON DELETE SET NULL, 
	FOREIGN KEY(related_analysis_id) REFERENCES analyses (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `support_messages`;
CREATE TABLE support_messages (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	ticket_id BIGINT NOT NULL, 
	author_id BIGINT NOT NULL, 
	body TEXT NOT NULL, 
	is_staff BOOL NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	FOREIGN KEY(ticket_id) REFERENCES support_tickets (id) ON DELETE CASCADE, 
	FOREIGN KEY(author_id) REFERENCES users (id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS `user_notifications`;
CREATE TABLE user_notifications (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	user_id BIGINT NOT NULL, 
	kind VARCHAR(48) NOT NULL, 
	title VARCHAR(160) NOT NULL, 
	body VARCHAR(500) NOT NULL, 
	link VARCHAR(512), 
	entity_type VARCHAR(48), 
	entity_id VARCHAR(64), 
	actor_user_id BIGINT, 
	metadata_json JSON, 
	is_read BOOL NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	read_at DATETIME, 
	PRIMARY KEY (id), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE, 
	FOREIGN KEY(actor_user_id) REFERENCES users (id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS `user_device_tokens`;
CREATE TABLE user_device_tokens (
	id BIGINT NOT NULL AUTO_INCREMENT, 
	user_id BIGINT NOT NULL, 
	token VARCHAR(512) NOT NULL, 
	platform VARCHAR(16) NOT NULL, 
	created_at DATETIME NOT NULL DEFAULT now(), 
	updated_at DATETIME NOT NULL DEFAULT now(), 
	PRIMARY KEY (id), 
	CONSTRAINT uq_user_device_tokens_token UNIQUE (token), 
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- ========================================================
-- 2. DATOS INICIALES (CATÁLOGOS, USUARIOS Y PROYECTO DEMO)
-- ========================================================

-- Catálogo de Planes
INSERT INTO `plans` (`id`, `slug`, `name`, `description`, `price_monthly_cents`, `analyses_limit_monthly`, `allow_real_model`, `max_file_mb`, `sort_order`, `is_active`, `features_json`) VALUES (1, 'free', 'Gratis', 'Ideal para conocer ARCHITECT sin compromiso.', 0, 5, 0, 5, 0, 1, '{"ideal_for": "Probar la plataforma", "support": "comunidad", "export": false, "mobile_app": false, "home_projects": true, "team_invites": false, "max_projects": 1, "asks_limit_monthly": 20, "storage_gb": 1, "benefits": ["5 análisis de planos al mes", "20 preguntas al chat / mes", "1 proyecto casa hogar · 1 GB docs", "Modelo demo", "Archivos hasta 5 MB por carga"]}');
INSERT INTO `plans` (`id`, `slug`, `name`, `description`, `price_monthly_cents`, `analyses_limit_monthly`, `allow_real_model`, `max_file_mb`, `sort_order`, `is_active`, `features_json`) VALUES (2, 'starter', 'Starter', 'Ideal para estudiantes y proyectos pequeños.', 30000, 30, 1, 10, 1, 1, '{"ideal_for": "Estudiantes y freelancers", "support": "email", "export": true, "mobile_app": false, "home_projects": true, "team_invites": false, "max_projects": 3, "asks_limit_monthly": 200, "storage_gb": 5, "benefits": ["30 análisis de planos al mes", "Hasta 3 proyectos casa hogar · 5 GB", "Análisis con modelo real (imagen y PDF)", "Exportar reportes PDF", "Archivos hasta 10 MB · Soporte por correo"]}');
INSERT INTO `plans` (`id`, `slug`, `name`, `description`, `price_monthly_cents`, `analyses_limit_monthly`, `allow_real_model`, `max_file_mb`, `sort_order`, `is_active`, `features_json`) VALUES (3, 'pro', 'Pro', 'Ideal para obra y despacho individual.', 50000, 150, 1, 20, 2, 1, '{"ideal_for": "Profesionales en obra", "recommended": true, "support": "prioritario", "export": true, "mobile_app": true, "home_projects": true, "team_invites": false, "max_projects": 20, "asks_limit_monthly": 9999, "storage_gb": 25, "benefits": ["150 análisis de planos al mes", "Hasta 20 proyectos · 25 GB docs", "IA con normas de Chiapas e indexación", "App móvil ARCHITECT incluida", "Archivos hasta 20 MB · Soporte prioritario"]}');
INSERT INTO `plans` (`id`, `slug`, `name`, `description`, `price_monthly_cents`, `analyses_limit_monthly`, `allow_real_model`, `max_file_mb`, `sort_order`, `is_active`, `features_json`) VALUES (4, 'enterprise', 'Enterprise', 'Ideal para equipos y despachos con alto volumen.', 90000, 9999, 1, 50, 3, 1, '{"ideal_for": "Equipos y constructoras", "support": "dedicado", "export": true, "mobile_app": true, "sla": true, "home_projects": true, "team_invites": true, "max_projects": 9999, "asks_limit_monthly": 9999, "storage_gb": 100, "benefits": ["Análisis y chat ilimitados", "Proyectos ilimitados · 100 GB docs", "Equipos, invitaciones y colaboración", "App móvil ARCHITECT incluida", "Archivos hasta 50 MB · Soporte dedicado con SLA"]}');

-- Usuarios iniciales
INSERT INTO `users` (`id`, `email`, `password_hash`, `full_name`, `role`, `is_active`, `created_at`, `updated_at`, `oauth_provider`, `oauth_subject`, `avatar_url`) VALUES (1, 'admin@architect.local', '$2b$12$4I0E4lF74sXVhFfiR5yCR.2A9XoiJsMrb3t8OUGd1r3qbHsUFJLxS', 'Administrador del Sistema', 'admin', 1, '2026-08-01 10:00:00', '2026-08-01 10:00:00', NULL, NULL, NULL);
INSERT INTO `users` (`id`, `email`, `password_hash`, `full_name`, `role`, `is_active`, `created_at`, `updated_at`, `oauth_provider`, `oauth_subject`, `avatar_url`) VALUES (2, 'lopeztrujilloxd@gmail.com', '$2b$12$xTi3eokazQdizO8EqpoYsufiop1Rq40QTrTzeNbsRlLGFk94/jNmG', 'Angel Emmanuel Trujillo Lopez', 'user', 1, '2026-08-01 10:00:00', '2026-08-01 10:00:00', NULL, NULL, NULL);
INSERT INTO `users` (`id`, `email`, `password_hash`, `full_name`, `role`, `is_active`, `created_at`, `updated_at`, `oauth_provider`, `oauth_subject`, `avatar_url`) VALUES (3, 'arq.morales@architect.local', '$2b$12$SeAUdg5b2nk6TDM/x16OuujH7TlFGjSWHXIKJst.TtUI/fgz11NnW', 'Arq. Ana Morales', 'user', 1, '2026-08-01 10:00:00', '2026-08-01 10:00:00', NULL, NULL, NULL);
INSERT INTO `users` (`id`, `email`, `password_hash`, `full_name`, `role`, `is_active`, `created_at`, `updated_at`, `oauth_provider`, `oauth_subject`, `avatar_url`) VALUES (4, 'ing.ruiz@architect.local', '$2b$12$yTz2UIVzl61RG5WqQ7VP0.R725u2MgNFgva0KjID0RpmiHogSp4gi', 'Ing. Carlos Ruiz', 'user', 1, '2026-08-01 10:00:00', '2026-08-01 10:00:00', NULL, NULL, NULL);
INSERT INTO `users` (`id`, `email`, `password_hash`, `full_name`, `role`, `is_active`, `created_at`, `updated_at`, `oauth_provider`, `oauth_subject`, `avatar_url`) VALUES (5, 'residente.vega@architect.local', '$2b$12$FmcnvJQHo7VAPgvbZmE6QORPMjs5y7DiuKqA1OTvZpB.BMUYuvaji', 'Arq. Roberto Vega', 'user', 1, '2026-08-01 10:00:00', '2026-08-01 10:00:00', NULL, NULL, NULL);

-- Suscripciones activas
INSERT INTO `subscriptions` (`id`, `user_id`, `plan_id`, `status`, `current_period_start`, `current_period_end`, `stripe_customer_id`, `stripe_subscription_id`, `canceled_at`, `created_at`) VALUES (1, 1, 4, 'active', '2026-01-01 00:00:00', '2027-12-31 23:59:59', 'cus_admin_demo', 'sub_admin_demo', NULL, '2026-01-01 00:00:00');
INSERT INTO `subscriptions` (`id`, `user_id`, `plan_id`, `status`, `current_period_start`, `current_period_end`, `stripe_customer_id`, `stripe_subscription_id`, `canceled_at`, `created_at`) VALUES (2, 2, 4, 'active', '2026-01-01 00:00:00', '2027-12-31 23:59:59', 'cus_angel_demo', 'sub_angel_demo', NULL, '2026-01-01 00:00:00');

-- Proyectos Casa Hogar
INSERT INTO `home_projects` (`id`, `user_id`, `name`, `client_name`, `location`, `latitude`, `longitude`, `description`, `status`, `current_stage`, `metadata_json`, `created_at`, `updated_at`) VALUES ('96513baa-ca57-4316-88ce-3192492bf343', 2, 'Residencia Bosques — Simulación Completa (100%)', 'Familia Morales López', 'Ocosingo, Chiapas', 16.9072, -92.0942, 'Proyecto integral de autoconstrucción de 180 m² con las 9 etapas ejecutadas al 100%. Incluye expediente de planos técnicos, cálculo estructural, instalaciones, bitácora de obra y presupuesto final auditado.', 'completed', 9, '{"budget": {"total_estimated": 1850000, "currency": "MXN", "stages": {"1": {"allocated": 35000, "spent": 32000, "notes": "Brief, programa arquitectónico y validación con cliente."}, "2": {"allocated": 65000, "spent": 65000, "notes": "Estudio topográfico, mecánica de suelos y deslinde catastral."}, "3": {"allocated": 50000, "spent": 48500, "notes": "Zonificación y esquemas funcionales de distribución."}, "4": {"allocated": 85000, "spent": 85000, "notes": "Anteproyecto volumétrico y renders de aprobación final."}, "5": {"allocated": 160000, "spent": 155000, "notes": "Plantas arquitectónicas, cortes, fachadas y detalles constructivos."}, "6": {"allocated": 220000, "spent": 220000, "notes": "Memorias de cálculo estructural, planos eléctricos e hidrosanitarios."}, "7": {"allocated": 45000, "spent": 40000, "notes": "Catálogo de conceptos, números generadores y contratación."}, "8": {"allocated": 1120000, "spent": 1110000, "notes": "Ejecución física de cimentación, estructura, muros y acabados."}, "9": {"allocated": 70000, "spent": 68500, "notes": "Revisión final, punch list, actas de entrega y póliza de garantía."}}}}', '2026-05-10 09:30:00', '2026-10-13 16:45:00');
INSERT INTO `home_projects` (`id`, `user_id`, `name`, `client_name`, `location`, `latitude`, `longitude`, `description`, `status`, `current_stage`, `metadata_json`, `created_at`, `updated_at`) VALUES ('269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 2, 'Casa López — Ocosingo', 'Familia López Gómez', 'Ocosingo, Centro, Chiapas', 16.9045, -92.092, 'Vivienda progresiva de dos niveles en lote urbano.', 'active', 2, '{}', '2026-09-01 11:00:00', '2026-09-01 11:00:00');

-- Etapas de los proyectos
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (1, '96513baa-ca57-4316-88ce-3192492bf343', 1, 'programacion', 'Programación', 'completed', 'Brief y necesidades validadas con el cliente. Programa de 180 m² aprobado.', '[]', '2026-05-24 09:30:00', '2026-06-05 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (2, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'investigacion', 'Investigación', 'completed', 'Levantamiento topográfico y estudio de mecánica de suelos completados.', '[]', '2026-06-07 09:30:00', '2026-06-19 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (3, '96513baa-ca57-4316-88ce-3192492bf343', 3, 'esquematizacion', 'Esquematización', 'completed', 'Esquema funcional y zonificación de áreas pública/privada/servicio definidos.', '[]', '2026-06-21 09:30:00', '2026-07-03 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (4, '96513baa-ca57-4316-88ce-3192492bf343', 4, 'anteproyecto', 'Anteproyecto', 'completed', 'Anteproyecto arquitectónico volumétrico aprobado por el cliente.', '[]', '2026-07-05 09:30:00', '2026-07-17 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (5, '96513baa-ca57-4316-88ce-3192492bf343', 5, 'proyecto_arquitectonico', 'Proyecto Arquitectónico', 'completed', 'Planos arquitectónicos ejecutivos y cuadro de especificaciones listos.', '[]', '2026-07-19 09:30:00', '2026-07-31 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (6, '96513baa-ca57-4316-88ce-3192492bf343', 6, 'proyecto_ejecutivo', 'Proyecto Ejecutivo', 'completed', 'Memorias de cálculo estructural e ingenierías (hidrosanitaria y eléctrica) aprobadas.', '[]', '2026-08-02 09:30:00', '2026-08-14 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (7, '96513baa-ca57-4316-88ce-3192492bf343', 7, 'presupuesto_programacion', 'Presupuesto y Programación de Obra', 'completed', 'Presupuesto base de $1.85 MDP y cronograma de obra acordados.', '[]', '2026-08-16 09:30:00', '2026-08-28 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (8, '96513baa-ca57-4316-88ce-3192492bf343', 8, 'construccion', 'Construcción o Ejecución', 'completed', 'Construcción física finalizada al 100%. Bitácora de obra con supervisión continua.', '[]', '2026-08-30 09:30:00', '2026-09-11 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (9, '96513baa-ca57-4316-88ce-3192492bf343', 9, 'entrega_evaluacion', 'Entrega y Evaluación', 'completed', 'Recepción de obra, punch list cerrado y expediente digital entregado.', '[]', '2026-09-13 09:30:00', '2026-09-25 09:30:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (10, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 1, 'programacion', 'Programación', 'completed', '', '[]', '2026-09-01 11:00:00', '2026-09-11 11:00:00', NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (11, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 2, 'investigacion', 'Investigación', 'in_progress', '', '[]', '2026-09-01 11:00:00', NULL, NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (12, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 3, 'esquematizacion', 'Esquematización', 'pending', '', '[]', NULL, NULL, NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (13, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 4, 'anteproyecto', 'Anteproyecto', 'pending', '', '[]', NULL, NULL, NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (14, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 5, 'proyecto_arquitectonico', 'Proyecto Arquitectónico', 'pending', '', '[]', NULL, NULL, NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (15, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 6, 'proyecto_ejecutivo', 'Proyecto Ejecutivo', 'pending', '', '[]', NULL, NULL, NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (16, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 7, 'presupuesto_programacion', 'Presupuesto y Programación de Obra', 'pending', '', '[]', NULL, NULL, NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (17, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 8, 'construccion', 'Construcción o Ejecución', 'pending', '', '[]', NULL, NULL, NULL);
INSERT INTO `home_project_stages` (`id`, `project_id`, `stage_number`, `slug`, `title`, `status`, `notes`, `checklist_json`, `started_at`, `completed_at`, `analysis_id`) VALUES (18, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 9, 'entrega_evaluacion', 'Entrega y Evaluación', 'pending', '', '[]', NULL, NULL, NULL);

-- Apartados de etapas (Sections)
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (1, '96513baa-ca57-4316-88ce-3192492bf343', 1, 'Necesidades del cliente', 'Evidencia del brief y prioridades del cliente.', 0, 'completed', 2, 1, '[{"key": "brief", "title": "Brief / entrevista", "accept": [".pdf", ".doc", ".docx"], "required": true}, {"key": "restricciones", "title": "Restricciones y presupuesto orientativo", "accept": [".pdf", ".doc", ".docx", ".xlsx", ".xls"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (2, '96513baa-ca57-4316-88ce-3192492bf343', 1, 'Programa arquitectónico', 'Espacios requeridos y aprobación formal.', 1, 'completed', 2, 1, '[{"key": "cuadro_espacios", "title": "Cuadro de espacios", "accept": [".pdf", ".xlsx", ".xls", ".doc", ".docx"], "required": true}, {"key": "acta_programa", "title": "Acta de aprobación del programa", "accept": [".pdf", ".doc", ".docx", ".png", ".jpg", ".jpeg"], "required": true}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (3, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'Estudio de sitio', 'Terreno, entorno y evidencia fotográfica.', 0, 'completed', 2, 1, '[{"key": "estudio_sitio", "title": "Estudio de sitio (PDF)", "accept": [".pdf"], "required": true}, {"key": "fotos_sitio", "title": "Fotos del predio", "accept": [".png", ".jpg", ".jpeg", ".webp", ".pdf"], "required": true}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (4, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'Normativa y uso de suelo', 'Reglamentos locales y coeficientes aplicables.', 1, 'completed', 2, 1, '[{"key": "uso_suelo", "title": "Uso de suelo / coeficientes", "accept": [".pdf", ".doc", ".docx", ".png", ".jpg", ".jpeg"], "required": true}, {"key": "normas_locales", "title": "Notas de normativa aplicable", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (5, '96513baa-ca57-4316-88ce-3192492bf343', 3, 'Diagramas y zonificación', 'Burbujas, zonas y circulaciones.', 0, 'completed', 2, 1, '[{"key": "diagramas", "title": "Diagramas de funcionamiento", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true}, {"key": "zonificacion", "title": "Zonificación (pública / privada / servicio)", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true}, {"key": "validacion_cliente", "title": "Validación del cliente", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".doc", ".docx"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (6, '96513baa-ca57-4316-88ce-3192492bf343', 4, 'Plantas preliminares', 'Plantas orientativas para revisión.', 0, 'completed', 2, 1, '[{"key": "planta", "title": "Planta preliminar", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true, "ai_plan_review": true}, {"key": "alternativas", "title": "Alternativas comparadas", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (7, '96513baa-ca57-4316-88ce-3192492bf343', 4, 'Volumetría y aprobación', '', 1, 'completed', 2, 1, '[{"key": "volumetria", "title": "Volumetría / renders", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": false}, {"key": "acta_anteproyecto", "title": "Acta de aprobación del anteproyecto", "accept": [".pdf", ".doc", ".docx", ".png", ".jpg", ".jpeg"], "required": true}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (8, '96513baa-ca57-4316-88ce-3192492bf343', 5, 'Planos arquitectónicos', 'Planta y documentación gráfica principal.', 0, 'completed', 2, 1, '[{"key": "planta", "title": "Planta arquitectónica", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true, "ai_plan_review": true}, {"key": "fachadas_cortes", "title": "Fachadas y cortes", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true}, {"key": "detalles", "title": "Detalles generales", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp", ".dwg", ".dxf"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (9, '96513baa-ca57-4316-88ce-3192492bf343', 5, 'Áreas y especificaciones', '', 1, 'completed', 2, 1, '[{"key": "cuadro_areas", "title": "Cuadro de áreas", "accept": [".pdf", ".xlsx", ".xls", ".doc", ".docx"], "required": true}, {"key": "especificaciones", "title": "Especificaciones arquitectónicas", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (10, '96513baa-ca57-4316-88ce-3192492bf343', 6, 'Planos constructivos', '', 0, 'completed', 2, 1, '[{"key": "planta_constructiva", "title": "Planta constructiva", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp", ".dwg", ".dxf"], "required": true, "ai_plan_review": true}, {"key": "detalles_ejecutivos", "title": "Detalles ejecutivos", "accept": [".pdf", ".dwg", ".dxf", ".png", ".jpg", ".jpeg"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (11, '96513baa-ca57-4316-88ce-3192492bf343', 6, 'Instalaciones', '', 1, 'completed', 2, 1, '[{"key": "hidrosanitario", "title": "Hidráulico / sanitario", "accept": [".pdf", ".dwg", ".dxf", ".png", ".jpg", ".jpeg"], "required": true}, {"key": "electrico", "title": "Eléctrico", "accept": [".pdf", ".dwg", ".dxf", ".png", ".jpg", ".jpeg"], "required": true}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (12, '96513baa-ca57-4316-88ce-3192492bf343', 6, 'Estructura y memorias', '', 2, 'completed', 2, 1, '[{"key": "estructural", "title": "Proyecto estructural", "accept": [".pdf", ".dwg", ".dxf"], "required": true}, {"key": "memorias", "title": "Memorias / especificaciones técnicas", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (13, '96513baa-ca57-4316-88ce-3192492bf343', 7, 'Presupuesto', '', 0, 'completed', 2, 1, '[{"key": "presupuesto", "title": "Presupuesto por partidas", "accept": [".xlsx", ".xls", ".pdf"], "required": true}, {"key": "proveedores", "title": "Proveedores / materiales", "accept": [".xlsx", ".xls", ".pdf", ".doc", ".docx"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (14, '96513baa-ca57-4316-88ce-3192492bf343', 7, 'Programación', '', 1, 'completed', 2, 1, '[{"key": "cronograma", "title": "Cronograma de obra", "accept": [".xlsx", ".xls", ".pdf"], "required": true}, {"key": "hitos_pago", "title": "Hitos de pago", "accept": [".pdf", ".xlsx", ".xls", ".doc", ".docx"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (15, '96513baa-ca57-4316-88ce-3192492bf343', 8, 'Bitácora y supervisión', '', 0, 'completed', 2, 1, '[{"key": "bitacora", "title": "Bitácora / minutas", "accept": [".pdf", ".doc", ".docx"], "required": true}, {"key": "fotos_avance", "title": "Fotos de avance", "accept": [".png", ".jpg", ".jpeg", ".webp", ".pdf"], "required": true}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (16, '96513baa-ca57-4316-88ce-3192492bf343', 8, 'Cambios de obra', '', 1, 'completed', 2, 1, '[{"key": "ordenes_cambio", "title": "Órdenes de cambio", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (17, '96513baa-ca57-4316-88ce-3192492bf343', 9, 'Cierre técnico', '', 0, 'completed', 2, 1, '[{"key": "punch_list", "title": "Punch list / pendientes", "accept": [".pdf", ".xlsx", ".xls", ".doc", ".docx"], "required": true}, {"key": "evaluacion", "title": "Evaluación vs objetivos", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (18, '96513baa-ca57-4316-88ce-3192492bf343', 9, 'Entrega al cliente', '', 1, 'completed', 2, 1, '[{"key": "acta_entrega", "title": "Acta de entrega-recepción", "accept": [".pdf", ".doc", ".docx", ".png", ".jpg", ".jpeg"], "required": true}, {"key": "expediente_cierre", "title": "Expediente de cierre", "accept": [".pdf", ".zip"], "required": false}]', '2026-05-10 09:30:00', '2026-05-10 09:30:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (19, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 1, 'Necesidades del cliente', 'Evidencia del brief y prioridades del cliente.', 0, 'completed', 2, 1, '[{"key": "brief", "title": "Brief / entrevista", "accept": [".pdf", ".doc", ".docx"], "required": true}, {"key": "restricciones", "title": "Restricciones y presupuesto orientativo", "accept": [".pdf", ".doc", ".docx", ".xlsx", ".xls"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (20, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 1, 'Programa arquitectónico', 'Espacios requeridos y aprobación formal.', 1, 'completed', 2, 1, '[{"key": "cuadro_espacios", "title": "Cuadro de espacios", "accept": [".pdf", ".xlsx", ".xls", ".doc", ".docx"], "required": true}, {"key": "acta_programa", "title": "Acta de aprobación del programa", "accept": [".pdf", ".doc", ".docx", ".png", ".jpg", ".jpeg"], "required": true}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (21, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 2, 'Estudio de sitio', 'Terreno, entorno y evidencia fotográfica.', 0, 'pending', 2, 1, '[{"key": "estudio_sitio", "title": "Estudio de sitio (PDF)", "accept": [".pdf"], "required": true}, {"key": "fotos_sitio", "title": "Fotos del predio", "accept": [".png", ".jpg", ".jpeg", ".webp", ".pdf"], "required": true}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (22, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 2, 'Normativa y uso de suelo', 'Reglamentos locales y coeficientes aplicables.', 1, 'pending', 2, 1, '[{"key": "uso_suelo", "title": "Uso de suelo / coeficientes", "accept": [".pdf", ".doc", ".docx", ".png", ".jpg", ".jpeg"], "required": true}, {"key": "normas_locales", "title": "Notas de normativa aplicable", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (23, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 3, 'Diagramas y zonificación', 'Burbujas, zonas y circulaciones.', 0, 'pending', 2, 1, '[{"key": "diagramas", "title": "Diagramas de funcionamiento", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true}, {"key": "zonificacion", "title": "Zonificación (pública / privada / servicio)", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true}, {"key": "validacion_cliente", "title": "Validación del cliente", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".doc", ".docx"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (24, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 4, 'Plantas preliminares', 'Plantas orientativas para revisión.', 0, 'pending', 2, 1, '[{"key": "planta", "title": "Planta preliminar", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true, "ai_plan_review": true}, {"key": "alternativas", "title": "Alternativas comparadas", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (25, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 4, 'Volumetría y aprobación', '', 1, 'pending', 2, 1, '[{"key": "volumetria", "title": "Volumetría / renders", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": false}, {"key": "acta_anteproyecto", "title": "Acta de aprobación del anteproyecto", "accept": [".pdf", ".doc", ".docx", ".png", ".jpg", ".jpeg"], "required": true}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (26, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 5, 'Planos arquitectónicos', 'Planta y documentación gráfica principal.', 0, 'pending', 2, 1, '[{"key": "planta", "title": "Planta arquitectónica", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true, "ai_plan_review": true}, {"key": "fachadas_cortes", "title": "Fachadas y cortes", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp"], "required": true}, {"key": "detalles", "title": "Detalles generales", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp", ".dwg", ".dxf"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (27, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 5, 'Áreas y especificaciones', '', 1, 'pending', 2, 1, '[{"key": "cuadro_areas", "title": "Cuadro de áreas", "accept": [".pdf", ".xlsx", ".xls", ".doc", ".docx"], "required": true}, {"key": "especificaciones", "title": "Especificaciones arquitectónicas", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (28, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 6, 'Planos constructivos', '', 0, 'pending', 2, 1, '[{"key": "planta_constructiva", "title": "Planta constructiva", "accept": [".pdf", ".png", ".jpg", ".jpeg", ".webp", ".dwg", ".dxf"], "required": true, "ai_plan_review": true}, {"key": "detalles_ejecutivos", "title": "Detalles ejecutivos", "accept": [".pdf", ".dwg", ".dxf", ".png", ".jpg", ".jpeg"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (29, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 6, 'Instalaciones', '', 1, 'pending', 2, 1, '[{"key": "hidrosanitario", "title": "Hidráulico / sanitario", "accept": [".pdf", ".dwg", ".dxf", ".png", ".jpg", ".jpeg"], "required": true}, {"key": "electrico", "title": "Eléctrico", "accept": [".pdf", ".dwg", ".dxf", ".png", ".jpg", ".jpeg"], "required": true}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (30, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 6, 'Estructura y memorias', '', 2, 'pending', 2, 1, '[{"key": "estructural", "title": "Proyecto estructural", "accept": [".pdf", ".dwg", ".dxf"], "required": true}, {"key": "memorias", "title": "Memorias / especificaciones técnicas", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (31, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 7, 'Presupuesto', '', 0, 'pending', 2, 1, '[{"key": "presupuesto", "title": "Presupuesto por partidas", "accept": [".xlsx", ".xls", ".pdf"], "required": true}, {"key": "proveedores", "title": "Proveedores / materiales", "accept": [".xlsx", ".xls", ".pdf", ".doc", ".docx"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (32, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 7, 'Programación', '', 1, 'pending', 2, 1, '[{"key": "cronograma", "title": "Cronograma de obra", "accept": [".xlsx", ".xls", ".pdf"], "required": true}, {"key": "hitos_pago", "title": "Hitos de pago", "accept": [".pdf", ".xlsx", ".xls", ".doc", ".docx"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (33, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 8, 'Bitácora y supervisión', '', 0, 'pending', 2, 1, '[{"key": "bitacora", "title": "Bitácora / minutas", "accept": [".pdf", ".doc", ".docx"], "required": true}, {"key": "fotos_avance", "title": "Fotos de avance", "accept": [".png", ".jpg", ".jpeg", ".webp", ".pdf"], "required": true}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (34, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 8, 'Cambios de obra', '', 1, 'pending', 2, 1, '[{"key": "ordenes_cambio", "title": "Órdenes de cambio", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (35, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 9, 'Cierre técnico', '', 0, 'pending', 2, 1, '[{"key": "punch_list", "title": "Punch list / pendientes", "accept": [".pdf", ".xlsx", ".xls", ".doc", ".docx"], "required": true}, {"key": "evaluacion", "title": "Evaluación vs objetivos", "accept": [".pdf", ".doc", ".docx"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');
INSERT INTO `home_project_sections` (`id`, `project_id`, `stage_number`, `title`, `description`, `sort_order`, `status`, `created_by`, `is_catalog`, `slots_json`, `created_at`, `updated_at`) VALUES (36, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 9, 'Entrega al cliente', '', 1, 'pending', 2, 1, '[{"key": "acta_entrega", "title": "Acta de entrega-recepción", "accept": [".pdf", ".doc", ".docx", ".png", ".jpg", ".jpeg"], "required": true}, {"key": "expediente_cierre", "title": "Expediente de cierre", "accept": [".pdf", ".zip"], "required": false}]', '2026-09-01 11:00:00', '2026-09-01 11:00:00');

-- Colaboradores asignados al proyecto demo
INSERT INTO `home_project_members` (`id`, `project_id`, `user_id`, `role`, `joined_at`) VALUES (1, '96513baa-ca57-4316-88ce-3192492bf343', 3, 'editor', '2026-05-15 09:30:00');
INSERT INTO `home_project_members` (`id`, `project_id`, `user_id`, `role`, `joined_at`) VALUES (2, '96513baa-ca57-4316-88ce-3192492bf343', 4, 'editor', '2026-05-17 09:30:00');
INSERT INTO `home_project_members` (`id`, `project_id`, `user_id`, `role`, `joined_at`) VALUES (3, '96513baa-ca57-4316-88ce-3192492bf343', 5, 'viewer', '2026-05-20 09:30:00');
INSERT INTO `home_project_members` (`id`, `project_id`, `user_id`, `role`, `joined_at`) VALUES (4, '269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910', 3, 'editor', '2026-09-04 11:00:00');

-- Documentación técnica cargada en el expediente
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (1, '96513baa-ca57-4316-88ce-3192492bf343', 2, 1, 1, 'doc', 'brief_necesidades_cliente.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/brief_necesidades_cliente.pdf', 'application/pdf', 145000, 'Documento técnico correspondiente a la etapa 1', NULL, '2026-05-22 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (2, '96513baa-ca57-4316-88ce-3192492bf343', 2, 2, 3, 'doc', 'estudio_topografico_deslinde.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/estudio_topografico_deslinde.pdf', 'application/pdf', 280000, 'Documento técnico correspondiente a la etapa 2', NULL, '2026-06-03 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (3, '96513baa-ca57-4316-88ce-3192492bf343', 2, 3, 5, 'doc', 'esquema_zonificacion.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/esquema_zonificacion.pdf', 'application/pdf', 95000, 'Documento técnico correspondiente a la etapa 3', NULL, '2026-06-15 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (4, '96513baa-ca57-4316-88ce-3192492bf343', 2, 4, 6, 'doc', 'anteproyecto_planta_arquitectonica.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/anteproyecto_planta_arquitectonica.pdf', 'application/pdf', 450000, 'Documento técnico correspondiente a la etapa 4', NULL, '2026-06-27 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (5, '96513baa-ca57-4316-88ce-3192492bf343', 2, 5, 8, 'doc', 'plano_arquitectonico_ejecutivo.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/plano_arquitectonico_ejecutivo.pdf', 'application/pdf', 820000, 'Documento técnico correspondiente a la etapa 5', NULL, '2026-07-09 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (6, '96513baa-ca57-4316-88ce-3192492bf343', 2, 6, 10, 'doc', 'memoria_calculo_estructural.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/memoria_calculo_estructural.pdf', 'application/pdf', 610000, 'Documento técnico correspondiente a la etapa 6', NULL, '2026-07-21 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (7, '96513baa-ca57-4316-88ce-3192492bf343', 2, 6, 10, 'doc', 'instalaciones_hidrosanitarias_electricas.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/instalaciones_hidrosanitarias_electricas.pdf', 'application/pdf', 540000, 'Documento técnico correspondiente a la etapa 6', NULL, '2026-07-21 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (8, '96513baa-ca57-4316-88ce-3192492bf343', 2, 7, 13, 'doc', 'catalogo_conceptos_presupuesto.xlsx', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/catalogo_conceptos_presupuesto.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 112000, 'Documento técnico correspondiente a la etapa 7', NULL, '2026-08-02 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (9, '96513baa-ca57-4316-88ce-3192492bf343', 2, 7, 13, 'doc', 'cronograma_ruta_critica.xlsx', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/cronograma_ruta_critica.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 88000, 'Documento técnico correspondiente a la etapa 7', NULL, '2026-08-02 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (10, '96513baa-ca57-4316-88ce-3192492bf343', 2, 8, 15, 'doc', 'bitacora_supervision_obra.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/bitacora_supervision_obra.pdf', 'application/pdf', 730000, 'Documento técnico correspondiente a la etapa 8', NULL, '2026-08-14 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (11, '96513baa-ca57-4316-88ce-3192492bf343', 2, 8, 15, 'doc', 'fotos_avance_fachada_final.jpg', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/fotos_avance_fachada_final.jpg', 'image/jpeg', 320000, 'Documento técnico correspondiente a la etapa 8', NULL, '2026-08-14 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (12, '96513baa-ca57-4316-88ce-3192492bf343', 2, 9, 17, 'doc', 'acta_entrega_recepcion_firmada.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/acta_entrega_recepcion_firmada.pdf', 'application/pdf', 210000, 'Documento técnico correspondiente a la etapa 9', NULL, '2026-08-26 09:30:00');
INSERT INTO `home_project_documents` (`id`, `project_id`, `user_id`, `stage_number`, `section_id`, `slot_key`, `original_filename`, `stored_path`, `mime_type`, `file_size`, `description`, `analysis_id`, `created_at`) VALUES (13, '96513baa-ca57-4316-88ce-3192492bf343', 2, 9, 17, 'doc', 'expediente_cierre_digital.pdf', 'data/home_projects/96513baa-ca57-4316-88ce-3192492bf343/expediente_cierre_digital.pdf', 'application/pdf', 950000, 'Documento técnico correspondiente a la etapa 9', NULL, '2026-08-26 09:30:00');

-- Comentarios técnicos de revisión en apartados
INSERT INTO `home_project_section_comments` (`id`, `section_id`, `user_id`, `body`, `created_at`) VALUES (1, 1, 3, 'Brief validado con la familia: se aprueba la zonificación con patio central y recámara en planta baja.', '2026-05-24 09:30:00');
INSERT INTO `home_project_section_comments` (`id`, `section_id`, `user_id`, `body`, `created_at`) VALUES (2, 3, 4, 'Estudio topográfico y mecánica de suelos concluidos: capacidad de carga óptima de 1.8 kg/cm².', '2026-06-07 09:30:00');
INSERT INTO `home_project_section_comments` (`id`, `section_id`, `user_id`, `body`, `created_at`) VALUES (3, 6, 3, 'Anteproyecto aprobado por el cliente sin observaciones. Pasamos al desarrollo del proyecto ejecutivo.', '2026-06-24 09:30:00');
INSERT INTO `home_project_section_comments` (`id`, `section_id`, `user_id`, `body`, `created_at`) VALUES (4, 10, 4, 'Cálculo estructural revisado conforme al código sísmico de Chiapas: zapatas aisladas y trabes de liga listas.', '2026-07-19 09:30:00');
INSERT INTO `home_project_section_comments` (`id`, `section_id`, `user_id`, `body`, `created_at`) VALUES (5, 13, 3, 'Catálogo de conceptos y presupuesto de $1.85 MDP cerrado favorablemente con contratistas.', '2026-08-03 09:30:00');
INSERT INTO `home_project_section_comments` (`id`, `section_id`, `user_id`, `body`, `created_at`) VALUES (6, 15, 5, 'Supervisión diaria en bitácora: colado de losas e instalaciones concluidas con éxito.', '2026-09-07 09:30:00');
INSERT INTO `home_project_section_comments` (`id`, `section_id`, `user_id`, `body`, `created_at`) VALUES (7, 17, 2, 'Acta de entrega formal y recepción técnica firmada. Expediente cerrado al 100%.', '2026-09-27 09:30:00');

-- Línea de tiempo / Historial de eventos
INSERT INTO `home_project_events` (`id`, `project_id`, `actor_user_id`, `event_type`, `metadata_json`, `created_at`) VALUES (1, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'stage_completed', '{"description": "Etapa 1 inicializada y validada con cliente."}', '2026-05-24 09:30:00');
INSERT INTO `home_project_events` (`id`, `project_id`, `actor_user_id`, `event_type`, `metadata_json`, `created_at`) VALUES (2, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'member_invited', '{"description": "Arq. Ana Morales se unió como Editora técnica."}', '2026-05-25 09:30:00');
INSERT INTO `home_project_events` (`id`, `project_id`, `actor_user_id`, `event_type`, `metadata_json`, `created_at`) VALUES (3, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'member_invited', '{"description": "Ing. Carlos Ruiz se unió como Editor estructural."}', '2026-05-26 09:30:00');
INSERT INTO `home_project_events` (`id`, `project_id`, `actor_user_id`, `event_type`, `metadata_json`, `created_at`) VALUES (4, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'document_uploaded', '{"description": "Se cargaron los planos ejecutivos de la Etapa 5."}', '2026-07-09 09:30:00');
INSERT INTO `home_project_events` (`id`, `project_id`, `actor_user_id`, `event_type`, `metadata_json`, `created_at`) VALUES (5, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'stage_advanced', '{"description": "Etapa 6 completada con aprobación estructural e hidrosanitaria."}', '2026-07-24 09:30:00');
INSERT INTO `home_project_events` (`id`, `project_id`, `actor_user_id`, `event_type`, `metadata_json`, `created_at`) VALUES (6, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'stage_advanced', '{"description": "Presupuesto y contratos cerrados en Etapa 7."}', '2026-08-08 09:30:00');
INSERT INTO `home_project_events` (`id`, `project_id`, `actor_user_id`, `event_type`, `metadata_json`, `created_at`) VALUES (7, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'stage_advanced', '{"description": "Construcción física finalizada al 100% en Etapa 8."}', '2026-09-12 09:30:00');
INSERT INTO `home_project_events` (`id`, `project_id`, `actor_user_id`, `event_type`, `metadata_json`, `created_at`) VALUES (8, '96513baa-ca57-4316-88ce-3192492bf343', 2, 'stage_advanced', '{"description": "Expediente de obra concluido al 100% y entregado formalmente."}', '2026-10-02 09:30:00');

SET FOREIGN_KEY_CHECKS = 1;
-- Fin del dump ARCHITECT
