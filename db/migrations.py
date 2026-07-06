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


def apply_pending_migrations() -> None:
    """Aplica ALTER TABLE pendientes sin borrar datos."""
    _ensure_analysis_corrections_column()
    _ensure_user_oauth_columns()
    _ensure_home_project_collab_tables()
    _ensure_section_comments_and_assignment()
    _ensure_section_review_statuses()
    _ensure_home_project_events_table()
    _ensure_billing_receipts_table()
