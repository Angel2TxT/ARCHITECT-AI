"""Migraciones ligeras para bases MySQL ya existentes."""

from __future__ import annotations

from sqlalchemy import text

from db.database import engine


def _ensure_analysis_corrections_column() -> None:
    with engine.begin() as conn:
        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'analyses' AND COLUMN_NAME = 'corrections_json'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text("ALTER TABLE analyses ADD COLUMN corrections_json JSON NULL")
            )
            print("  Columna analyses.corrections_json añadida.")


def _ensure_user_oauth_columns() -> None:
    columns = {
        "oauth_provider": "VARCHAR(32) NULL",
        "oauth_subject": "VARCHAR(128) NULL",
        "avatar_url": "VARCHAR(512) NULL",
    }
    with engine.begin() as conn:
        for col, ddl in columns.items():
            r = conn.execute(
                text(
                    "SELECT COUNT(*) FROM information_schema.COLUMNS "
                    "WHERE TABLE_SCHEMA = DATABASE() "
                    "AND TABLE_NAME = 'users' AND COLUMN_NAME = :col"
                ),
                {"col": col},
            )
            if r.scalar() == 0:
                conn.execute(text(f"ALTER TABLE users ADD COLUMN {col} {ddl}"))
                print(f"  Columna users.{col} añadida.")

        r = conn.execute(
            text(
                "SELECT IS_NULLABLE FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'users' AND COLUMN_NAME = 'password_hash'"
            )
        )
        nullable = r.scalar()
        if nullable and nullable.upper() != "YES":
            conn.execute(
                text("ALTER TABLE users MODIFY password_hash VARCHAR(255) NULL")
            )
            print("  users.password_hash ahora permite NULL (cuentas Google).")

        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'users' AND CONSTRAINT_NAME = 'uq_users_oauth'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text(
                    "ALTER TABLE users ADD CONSTRAINT uq_users_oauth "
                    "UNIQUE (oauth_provider, oauth_subject)"
                )
            )
            print("  Índice único uq_users_oauth añadido.")


def _ensure_home_project_collab_tables() -> None:
    """Tablas de apartados, miembros e invitaciones para proyectos casa hogar."""
    collate = "utf8mb4_0900_ai_ci"
    tables = {
        "home_project_sections": f"""
            CREATE TABLE home_project_sections (
                id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                project_id VARCHAR(36) CHARACTER SET utf8mb4 COLLATE {collate} NOT NULL,
                stage_number INT NOT NULL,
                title VARCHAR(200) NOT NULL,
                description TEXT NOT NULL,
                sort_order INT NOT NULL DEFAULT 0,
                status ENUM('pending','in_progress','completed') NOT NULL DEFAULT 'pending',
                created_by BIGINT NULL,
                is_catalog TINYINT(1) NOT NULL DEFAULT 0,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX ix_home_project_sections_project_id (project_id),
                INDEX ix_home_project_sections_stage_number (stage_number),
                CONSTRAINT fk_hps_project FOREIGN KEY (project_id)
                    REFERENCES home_projects(id) ON DELETE CASCADE,
                CONSTRAINT fk_hps_created_by FOREIGN KEY (created_by)
                    REFERENCES users(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
        """,
        "home_project_members": f"""
            CREATE TABLE home_project_members (
                id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                project_id VARCHAR(36) CHARACTER SET utf8mb4 COLLATE {collate} NOT NULL,
                user_id BIGINT NOT NULL,
                role ENUM('editor','viewer') NOT NULL DEFAULT 'editor',
                joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_home_project_member (project_id, user_id),
                INDEX ix_home_project_members_project_id (project_id),
                INDEX ix_home_project_members_user_id (user_id),
                CONSTRAINT fk_hpm_project FOREIGN KEY (project_id)
                    REFERENCES home_projects(id) ON DELETE CASCADE,
                CONSTRAINT fk_hpm_user FOREIGN KEY (user_id)
                    REFERENCES users(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
        """,
        "home_project_invites": f"""
            CREATE TABLE home_project_invites (
                id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                project_id VARCHAR(36) CHARACTER SET utf8mb4 COLLATE {collate} NOT NULL,
                email VARCHAR(255) NOT NULL,
                role ENUM('editor','viewer') NOT NULL DEFAULT 'editor',
                token VARCHAR(64) NOT NULL,
                invited_by BIGINT NOT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                expires_at DATETIME NOT NULL,
                accepted_at DATETIME NULL,
                UNIQUE KEY uq_home_project_invite_token (token),
                INDEX ix_home_project_invites_project_id (project_id),
                INDEX ix_home_project_invites_email (email),
                CONSTRAINT fk_hpi_project FOREIGN KEY (project_id)
                    REFERENCES home_projects(id) ON DELETE CASCADE,
                CONSTRAINT fk_hpi_invited_by FOREIGN KEY (invited_by)
                    REFERENCES users(id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
        """,
    }
    with engine.begin() as conn:
        for table, ddl in tables.items():
            r = conn.execute(
                text(
                    "SELECT COUNT(*) FROM information_schema.TABLES "
                    "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :tbl"
                ),
                {"tbl": table},
            )
            if r.scalar() == 0:
                conn.execute(text(ddl))
                print(f"  Tabla {table} creada.")

        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'home_project_documents' AND COLUMN_NAME = 'section_id'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text(
                    "ALTER TABLE home_project_documents "
                    "ADD COLUMN section_id BIGINT NULL, "
                    "ADD INDEX ix_home_project_documents_section_id (section_id), "
                    "ADD CONSTRAINT fk_hpd_section FOREIGN KEY (section_id) "
                    "REFERENCES home_project_sections(id) ON DELETE SET NULL"
                )
            )
            print("  Columna home_project_documents.section_id añadida.")


def _ensure_section_comments_and_assignment() -> None:
    collate = "utf8mb4_0900_ai_ci"
    with engine.begin() as conn:
        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.TABLES "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'home_project_section_comments'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text(
                    f"""
                    CREATE TABLE home_project_section_comments (
                        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        section_id BIGINT NOT NULL,
                        user_id BIGINT NOT NULL,
                        body TEXT NOT NULL,
                        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        INDEX ix_hpsc_section_id (section_id),
                        INDEX ix_hpsc_user_id (user_id),
                        INDEX ix_hpsc_created_at (created_at),
                        CONSTRAINT fk_hpsc_section FOREIGN KEY (section_id)
                            REFERENCES home_project_sections(id) ON DELETE CASCADE,
                        CONSTRAINT fk_hpsc_user FOREIGN KEY (user_id)
                            REFERENCES users(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
                    """
                )
            )
            print("  Tabla home_project_section_comments creada.")

        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'home_project_sections' "
                "AND COLUMN_NAME = 'assigned_to_user_id'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text(
                    "ALTER TABLE home_project_sections "
                    "ADD COLUMN assigned_to_user_id BIGINT NULL, "
                    "ADD INDEX ix_home_project_sections_assigned_to (assigned_to_user_id), "
                    "ADD CONSTRAINT fk_hps_assigned_to FOREIGN KEY (assigned_to_user_id) "
                    "REFERENCES users(id) ON DELETE SET NULL"
                )
            )
            print("  Columna home_project_sections.assigned_to_user_id añadida.")


def _ensure_section_review_statuses() -> None:
    with engine.begin() as conn:
        r = conn.execute(
            text(
                "SELECT COLUMN_TYPE FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'home_project_sections' "
                "AND COLUMN_NAME = 'status'"
            )
        )
        row = r.scalar()
        if row and "needs_details" not in str(row):
            conn.execute(
                text(
                    "ALTER TABLE home_project_sections "
                    "MODIFY COLUMN status ENUM("
                    "'pending','in_progress','needs_details','needs_correction','completed'"
                    ") NOT NULL DEFAULT 'pending'"
                )
            )
            print("  Estados de revisión añadidos a home_project_sections.status.")


def _ensure_home_project_events_table() -> None:
    collate = "utf8mb4_0900_ai_ci"
    with engine.begin() as conn:
        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.TABLES "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'home_project_events'"
            )
        )
        if r.scalar() != 0:
            return

        conn.execute(
            text(
                f"""
                CREATE TABLE home_project_events (
                    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    project_id VARCHAR(36) CHARACTER SET utf8mb4 COLLATE {collate} NOT NULL,
                    actor_user_id BIGINT NULL,
                    event_type VARCHAR(64) NOT NULL,
                    section_id BIGINT NULL,
                    document_id BIGINT NULL,
                    comment_id BIGINT NULL,
                    metadata_json JSON NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX ix_hpe_project_id (project_id),
                    INDEX ix_hpe_actor_user_id (actor_user_id),
                    INDEX ix_hpe_event_type (event_type),
                    INDEX ix_hpe_section_id (section_id),
                    INDEX ix_hpe_document_id (document_id),
                    INDEX ix_hpe_comment_id (comment_id),
                    INDEX ix_hpe_created_at (created_at),
                    CONSTRAINT fk_hpe_project FOREIGN KEY (project_id)
                        REFERENCES home_projects(id) ON DELETE CASCADE,
                    CONSTRAINT fk_hpe_actor FOREIGN KEY (actor_user_id)
                        REFERENCES users(id) ON DELETE SET NULL,
                    CONSTRAINT fk_hpe_section FOREIGN KEY (section_id)
                        REFERENCES home_project_sections(id) ON DELETE SET NULL,
                    CONSTRAINT fk_hpe_document FOREIGN KEY (document_id)
                        REFERENCES home_project_documents(id) ON DELETE SET NULL,
                    CONSTRAINT fk_hpe_comment FOREIGN KEY (comment_id)
                        REFERENCES home_project_section_comments(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
                """
            )
        )
        print("  Tabla home_project_events creada.")


def _ensure_billing_receipts_table() -> None:
    collate = "utf8mb4_0900_ai_ci"
    with engine.begin() as conn:
        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.TABLES "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'billing_receipts'"
            )
        )
        if r.scalar() != 0:
            return

        conn.execute(
            text(
                f"""
                CREATE TABLE billing_receipts (
                    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    receipt_number VARCHAR(32) NOT NULL,
                    user_id BIGINT NOT NULL,
                    plan_id INT NULL,
                    plan_slug VARCHAR(32) NOT NULL DEFAULT '',
                    plan_name VARCHAR(80) NOT NULL DEFAULT '',
                    amount_cents INT NOT NULL DEFAULT 0,
                    currency VARCHAR(8) NOT NULL DEFAULT 'MXN',
                    billing_mode VARCHAR(16) NOT NULL DEFAULT 'demo',
                    payment_ref VARCHAR(128) NULL,
                    period_start DATETIME NULL,
                    period_end DATETIME NULL,
                    email_sent_at DATETIME NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uq_billing_receipt_number (receipt_number),
                    INDEX ix_billing_receipts_user_id (user_id),
                    INDEX ix_billing_receipts_created_at (created_at),
                    CONSTRAINT fk_br_user FOREIGN KEY (user_id)
                        REFERENCES users(id) ON DELETE CASCADE,
                    CONSTRAINT fk_br_plan FOREIGN KEY (plan_id)
                        REFERENCES plans(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
                """
            )
        )
        print("  Tabla billing_receipts creada.")


def _ensure_support_role_and_tables() -> None:
    """Rol support en users.role + tablas de tickets."""
    collate = "utf8mb4_0900_ai_ci"
    with engine.begin() as conn:
        # Ampliar ENUM de rol (MySQL)
        try:
            conn.execute(
                text(
                    "ALTER TABLE users MODIFY COLUMN role "
                    "ENUM('admin','support','user') NOT NULL DEFAULT 'user'"
                )
            )
            print("  users.role incluye 'support'.")
        except Exception as exc:
            print(f"  Nota users.role enum: {exc}")

        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.TABLES "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'support_tickets'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text(
                    f"""
                    CREATE TABLE support_tickets (
                        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        user_id BIGINT NOT NULL,
                        assigned_to BIGINT NULL,
                        subject VARCHAR(160) NOT NULL,
                        status ENUM('open','pending','resolved','closed')
                            NOT NULL DEFAULT 'open',
                        priority ENUM('normal','high') NOT NULL DEFAULT 'normal',
                        related_chat_id VARCHAR(36) NULL,
                        related_analysis_id BIGINT NULL,
                        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                            ON UPDATE CURRENT_TIMESTAMP,
                        INDEX ix_support_tickets_user_id (user_id),
                        INDEX ix_support_tickets_assigned_to (assigned_to),
                        INDEX ix_support_tickets_status (status),
                        INDEX ix_support_tickets_created_at (created_at),
                        INDEX ix_support_tickets_updated_at (updated_at),
                        CONSTRAINT fk_st_user FOREIGN KEY (user_id)
                            REFERENCES users(id) ON DELETE CASCADE,
                        CONSTRAINT fk_st_assignee FOREIGN KEY (assigned_to)
                            REFERENCES users(id) ON DELETE SET NULL,
                        CONSTRAINT fk_st_analysis FOREIGN KEY (related_analysis_id)
                            REFERENCES analyses(id) ON DELETE SET NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
                    """
                )
            )
            print("  Tabla support_tickets creada.")

        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.TABLES "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'support_messages'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text(
                    f"""
                    CREATE TABLE support_messages (
                        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        ticket_id BIGINT NOT NULL,
                        author_id BIGINT NOT NULL,
                        body TEXT NOT NULL,
                        is_staff TINYINT(1) NOT NULL DEFAULT 0,
                        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        INDEX ix_support_messages_ticket_id (ticket_id),
                        INDEX ix_support_messages_author_id (author_id),
                        INDEX ix_support_messages_created_at (created_at),
                        CONSTRAINT fk_sm_ticket FOREIGN KEY (ticket_id)
                            REFERENCES support_tickets(id) ON DELETE CASCADE,
                        CONSTRAINT fk_sm_author FOREIGN KEY (author_id)
                            REFERENCES users(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
                    """
                )
            )
            print("  Tabla support_messages creada.")


def _ensure_refund_requests_table() -> None:
    collate = "utf8mb4_0900_ai_ci"
    with engine.begin() as conn:
        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.TABLES "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'refund_requests'"
            )
        )
        if r.scalar() != 0:
            return
        conn.execute(
            text(
                f"""
                CREATE TABLE refund_requests (
                    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    user_id BIGINT NOT NULL,
                    receipt_id BIGINT NULL,
                    amount_cents INT NOT NULL DEFAULT 0,
                    currency VARCHAR(8) NOT NULL DEFAULT 'MXN',
                    status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
                    eligible_at_request TINYINT(1) NOT NULL DEFAULT 0,
                    reason TEXT NOT NULL,
                    admin_note TEXT NOT NULL,
                    eligibility_json JSON NULL,
                    reviewed_by BIGINT NULL,
                    reviewed_at DATETIME NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX ix_refund_requests_user_id (user_id),
                    INDEX ix_refund_requests_status (status),
                    INDEX ix_refund_requests_created_at (created_at),
                    CONSTRAINT fk_rr_user FOREIGN KEY (user_id)
                        REFERENCES users(id) ON DELETE CASCADE,
                    CONSTRAINT fk_rr_receipt FOREIGN KEY (receipt_id)
                        REFERENCES billing_receipts(id) ON DELETE SET NULL,
                    CONSTRAINT fk_rr_reviewer FOREIGN KEY (reviewed_by)
                        REFERENCES users(id) ON DELETE SET NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
                """
            )
        )
        print("  Tabla refund_requests creada.")


def _ensure_usage_asks_count() -> None:
    """Columna asks_count + backfill de preguntas (type=question) del mes."""
    with engine.begin() as conn:
        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'usage_records' AND COLUMN_NAME = 'asks_count'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text(
                    "ALTER TABLE usage_records "
                    "ADD COLUMN asks_count INT NOT NULL DEFAULT 0"
                )
            )
            print("  Columna usage_records.asks_count añadida.")

        # Backfill: mensajes user con type=question del periodo de cada fila
        try:
            conn.execute(
                text(
                    """
                    UPDATE usage_records ur
                    SET asks_count = (
                      SELECT COUNT(*)
                      FROM messages m
                      INNER JOIN chats c ON c.id = m.chat_id
                      WHERE c.user_id = ur.user_id
                        AND m.role = 'user'
                        AND m.created_at >= STR_TO_DATE(CONCAT(ur.period_key, '-01'), '%Y-%m-%d')
                        AND m.created_at < DATE_ADD(
                          STR_TO_DATE(CONCAT(ur.period_key, '-01'), '%Y-%m-%d'),
                          INTERVAL 1 MONTH
                        )
                        AND (
                          JSON_UNQUOTE(JSON_EXTRACT(m.content, '$.type')) = 'question'
                          OR (
                            m.analysis_id IS NULL
                            AND JSON_EXTRACT(m.content, '$.type') IS NULL
                            AND JSON_EXTRACT(m.content, '$.filename') IS NULL
                            AND JSON_EXTRACT(m.content, '$.analysis_id') IS NULL
                          )
                        )
                    )
                    WHERE ur.asks_count = 0
                    """
                )
            )
        except Exception as exc:
            print(f"  Aviso: no se pudo backfill asks_count ({exc})")


def _ensure_home_project_ai_reviews_table() -> None:
    """Paquetes de revisión IA ligados a entregables del expediente."""
    collate = "utf8mb4_0900_ai_ci"
    with engine.begin() as conn:
        r = conn.execute(
            text(
                "SELECT COUNT(*) FROM information_schema.TABLES "
                "WHERE TABLE_SCHEMA = DATABASE() "
                "AND TABLE_NAME = 'home_project_ai_reviews'"
            )
        )
        if r.scalar() == 0:
            conn.execute(
                text(
                    f"""
                    CREATE TABLE home_project_ai_reviews (
                        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        project_id VARCHAR(36) CHARACTER SET utf8mb4 COLLATE {collate} NOT NULL,
                        stage_number INT NOT NULL,
                        section_id BIGINT NULL,
                        document_id BIGINT NULL,
                        analysis_id BIGINT NULL,
                        created_by BIGINT NULL,
                        status ENUM('open','resolved','dismissed') NOT NULL DEFAULT 'open',
                        scope_json JSON NULL,
                        exclusions_json JSON NULL,
                        verdict_json JSON NULL,
                        findings_json JSON NULL,
                        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        INDEX ix_hpair_project_id (project_id),
                        INDEX ix_hpair_stage_number (stage_number),
                        INDEX ix_hpair_section_id (section_id),
                        INDEX ix_hpair_document_id (document_id),
                        INDEX ix_hpair_analysis_id (analysis_id),
                        INDEX ix_hpair_status (status),
                        INDEX ix_hpair_created_at (created_at),
                        CONSTRAINT fk_hpair_project FOREIGN KEY (project_id)
                            REFERENCES home_projects(id) ON DELETE CASCADE,
                        CONSTRAINT fk_hpair_section FOREIGN KEY (section_id)
                            REFERENCES home_project_sections(id) ON DELETE SET NULL,
                        CONSTRAINT fk_hpair_document FOREIGN KEY (document_id)
                            REFERENCES home_project_documents(id) ON DELETE SET NULL,
                        CONSTRAINT fk_hpair_analysis FOREIGN KEY (analysis_id)
                            REFERENCES analyses(id) ON DELETE SET NULL,
                        CONSTRAINT fk_hpair_created_by FOREIGN KEY (created_by)
                            REFERENCES users(id) ON DELETE SET NULL
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE={collate}
                    """
                )
            )
            print("  Tabla home_project_ai_reviews creada.")


def _ensure_home_project_file_slots() -> None:
    """Slots nombrados por apartado + slot_key en documentos."""
    with engine.begin() as conn:
        for table, column, ddl in (
            (
                "home_project_sections",
                "catalog_key",
                "ALTER TABLE home_project_sections "
                "ADD COLUMN catalog_key VARCHAR(80) NULL, "
                "ADD INDEX ix_hps_catalog_key (catalog_key)",
            ),
            (
                "home_project_sections",
                "slots_json",
                "ALTER TABLE home_project_sections ADD COLUMN slots_json JSON NULL",
            ),
            (
                "home_project_documents",
                "slot_key",
                "ALTER TABLE home_project_documents "
                "ADD COLUMN slot_key VARCHAR(80) NULL, "
                "ADD INDEX ix_hpd_slot_key (slot_key)",
            ),
        ):
            r = conn.execute(
                text(
                    "SELECT COUNT(*) FROM information_schema.COLUMNS "
                    "WHERE TABLE_SCHEMA = DATABASE() "
                    "AND TABLE_NAME = :tbl AND COLUMN_NAME = :col"
                ),
                {"tbl": table, "col": column},
            )
            if r.scalar() == 0:
                conn.execute(text(ddl))
                print(f"  Columna {table}.{column} añadida.")


def apply_pending_migrations() -> None:
    """Aplica ALTER TABLE pendientes sin borrar datos."""
    _ensure_analysis_corrections_column()
    _ensure_user_oauth_columns()
    _ensure_home_project_collab_tables()
    _ensure_section_comments_and_assignment()
    _ensure_section_review_statuses()
    _ensure_home_project_events_table()
    _ensure_home_project_ai_reviews_table()
    _ensure_home_project_file_slots()
    _ensure_billing_receipts_table()
    _ensure_support_role_and_tables()
    _ensure_refund_requests_table()
    _ensure_usage_asks_count()
