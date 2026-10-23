"""Generador del dump completo de base de datos MySQL (architect.sql).
Incluye esquema de las 23 tablas, planes, usuarios, suscripciones y proyecto de demostración Casa Hogar.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = ROOT.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from sqlalchemy.dialects import mysql
from sqlalchemy.schema import CreateTable

from db.database import Base
from db.models import (
    Analysis,
    BillingReceipt,
    Chat,
    GuestTrial,
    HomeProject,
    HomeProjectAiReview,
    HomeProjectDocument,
    HomeProjectEvent,
    HomeProjectInvite,
    HomeProjectMember,
    HomeProjectMemberRole,
    HomeProjectSection,
    HomeProjectSectionComment,
    HomeProjectSectionStatus,
    HomeProjectStage,
    HomeProjectStatus,
    HomeStageStatus,
    Message,
    Plan,
    RefundRequest,
    Subscription,
    SubscriptionStatus,
    SupportMessage,
    SupportTicket,
    UsageRecord,
    User,
    UserDeviceToken,
    UserNotification,
    UserRole,
)
from db.seed import DEFAULT_PLANS
from services.auth_service import hash_password
from services.home_project_service import load_stage_catalog


def escape_sql(val: object) -> str:
    if val is None:
        return "NULL"
    if isinstance(val, bool):
        return "1" if val else "0"
    if isinstance(val, (int, float)):
        return str(val)
    if isinstance(val, datetime):
        return f"'{val.strftime('%Y-%m-%d %H:%M:%S')}'"
    if isinstance(val, (dict, list)):
        s = json.dumps(val, ensure_ascii=False)
        return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "\\r") + "'"
    s = str(val)
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "\\r") + "'"


def row_to_insert(table_name: str, cols: list[str], row: list[object]) -> str:
    col_str = ", ".join(f"`{c}`" for c in cols)
    val_str = ", ".join(escape_sql(v) for v in row)
    return f"INSERT INTO `{table_name}` ({col_str}) VALUES ({val_str});\n"


def generate_sql() -> str:
    lines: list[str] = [
        "-- ARCHITECT — Base de datos MySQL completa (Esquema + Datos iniciales + Proyecto Demo)\n",
        "-- Generado automáticamente con soporte para todas las funcionalidades\n",
        "-- Compatible con MySQL 8.0+\n\n",
        "SET NAMES utf8mb4;\n",
        "SET CHARACTER SET utf8mb4;\n",
        "SET FOREIGN_KEY_CHECKS = 0;\n",
        "SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';\n",
        "SET time_zone = '+00:00';\n\n",
        "CREATE DATABASE IF NOT EXISTS `architect` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n",
        "USE `architect`;\n\n",
    ]

    # Orden de creación respetando dependencias de claves foráneas
    ordered_tables = [
        "plans",
        "users",
        "guest_trials",
        "subscriptions",
        "billing_receipts",
        "usage_records",
        "chats",
        "messages",
        "analyses",
        "home_projects",
        "home_project_stages",
        "home_project_sections",
        "home_project_section_comments",
        "home_project_documents",
        "home_project_members",
        "home_project_invites",
        "home_project_events",
        "home_project_ai_reviews",
        "refund_requests",
        "support_tickets",
        "support_messages",
        "user_notifications",
        "user_device_tokens",
    ]

    lines.append("-- ========================================================\n")
    lines.append("-- 1. ESTRUCTURA DE TABLAS (DDL)\n")
    lines.append("-- ========================================================\n\n")

    for tname in ordered_tables:
        table = Base.metadata.tables[tname]
        ddl = str(CreateTable(table).compile(dialect=mysql.dialect())).strip()
        lines.append(f"DROP TABLE IF EXISTS `{tname}`;\n")
        lines.append(ddl + ";\n\n")

    lines.append("-- ========================================================\n")
    lines.append("-- 2. DATOS INICIALES (CATÁLOGOS, USUARIOS Y PROYECTO DEMO)\n")
    lines.append("-- ========================================================\n\n")

    # --- 1. PLANS ---
    lines.append("-- Catálogo de Planes\n")
    plan_cols = [
        "id", "slug", "name", "description", "price_monthly_cents",
        "analyses_limit_monthly", "allow_real_model", "max_file_mb",
        "sort_order", "is_active", "features_json"
    ]
    for idx, p in enumerate(DEFAULT_PLANS, start=1):
        lines.append(row_to_insert("plans", plan_cols, [
            idx,
            p["slug"],
            p["name"],
            p["description"],
            p["price_monthly_cents"],
            p["analyses_limit_monthly"],
            p["allow_real_model"],
            p["max_file_mb"],
            p["sort_order"],
            True,
            p["features"],
        ]))
    lines.append("\n")

    # --- 2. USERS ---
    lines.append("-- Usuarios iniciales\n")
    user_cols = [
        "id", "email", "password_hash", "full_name", "role", "is_active",
        "created_at", "updated_at", "oauth_provider", "oauth_subject", "avatar_url"
    ]
    users_data = [
        (1, "admin@architect.local", hash_password("admin123"), "Administrador del Sistema", "admin", True),
        (2, "lopeztrujilloxd@gmail.com", hash_password("password123"), "Angel Emmanuel Trujillo Lopez", "user", True),
        (3, "arq.morales@architect.local", hash_password("Colaborador123!"), "Arq. Ana Morales", "user", True),
        (4, "ing.ruiz@architect.local", hash_password("Colaborador123!"), "Ing. Carlos Ruiz", "user", True),
        (5, "residente.vega@architect.local", hash_password("Colaborador123!"), "Arq. Roberto Vega", "user", True),
    ]
    now = datetime(2026, 8, 1, 10, 0, 0)
    for u_id, email, pwd_hash, full_name, role, active in users_data:
        lines.append(row_to_insert("users", user_cols, [
            u_id, email, pwd_hash, full_name, role, active, now, now, None, None, None
        ]))
    lines.append("\n")

    # --- 3. SUBSCRIPTIONS ---
    lines.append("-- Suscripciones activas\n")
    sub_cols = [
        "id", "user_id", "plan_id", "status", "current_period_start",
        "current_period_end", "stripe_customer_id", "stripe_subscription_id",
        "canceled_at", "created_at"
    ]
    start_dt = datetime(2026, 1, 1, 0, 0, 0)
    end_dt = datetime(2027, 12, 31, 23, 59, 59)
    lines.append(row_to_insert("subscriptions", sub_cols, [
        1, 1, 4, "active", start_dt, end_dt, "cus_admin_demo", "sub_admin_demo", None, start_dt
    ]))
    lines.append(row_to_insert("subscriptions", sub_cols, [
        2, 2, 4, "active", start_dt, end_dt, "cus_angel_demo", "sub_angel_demo", None, start_dt
    ]))
    lines.append("\n")

    # --- 4. HOME PROJECTS ---
    lines.append("-- Proyectos Casa Hogar\n")
    proj_cols = [
        "id", "user_id", "name", "client_name", "location", "latitude", "longitude",
        "description", "status", "current_stage", "metadata_json", "created_at", "updated_at"
    ]

    p1_id = "96513baa-ca57-4316-88ce-3192492bf343"
    p1_meta = {
        "budget": {
            "total_estimated": 1850000,
            "currency": "MXN",
            "stages": {
                "1": {"allocated": 35000, "spent": 32000, "notes": "Brief, programa arquitectónico y validación con cliente."},
                "2": {"allocated": 65000, "spent": 65000, "notes": "Estudio topográfico, mecánica de suelos y deslinde catastral."},
                "3": {"allocated": 50000, "spent": 48500, "notes": "Zonificación y esquemas funcionales de distribución."},
                "4": {"allocated": 85000, "spent": 85000, "notes": "Anteproyecto volumétrico y renders de aprobación final."},
                "5": {"allocated": 160000, "spent": 155000, "notes": "Plantas arquitectónicas, cortes, fachadas y detalles constructivos."},
                "6": {"allocated": 220000, "spent": 220000, "notes": "Memorias de cálculo estructural, planos eléctricos e hidrosanitarios."},
                "7": {"allocated": 45000, "spent": 40000, "notes": "Catálogo de conceptos, números generadores y contratación."},
                "8": {"allocated": 1120000, "spent": 1110000, "notes": "Ejecución física de cimentación, estructura, muros y acabados."},
                "9": {"allocated": 70000, "spent": 68500, "notes": "Revisión final, punch list, actas de entrega y póliza de garantía."}
            }
        }
    }
    p1_created = datetime(2026, 5, 10, 9, 30, 0)
    lines.append(row_to_insert("home_projects", proj_cols, [
        p1_id,
        2,
        "Residencia Bosques — Simulación Completa (100%)",
        "Familia Morales López",
        "Ocosingo, Chiapas",
        16.9072,
        -92.0942,
        "Proyecto integral de autoconstrucción de 180 m² con las 9 etapas ejecutadas al 100%. Incluye expediente de planos técnicos, cálculo estructural, instalaciones, bitácora de obra y presupuesto final auditado.",
        "completed",
        9,
        p1_meta,
        p1_created,
        datetime(2026, 10, 13, 16, 45, 0),
    ]))

    p2_id = "269c4a5e-8b1a-4d7a-9cf2-1b6a7e0e8910"
    p2_created = datetime(2026, 9, 1, 11, 0, 0)
    lines.append(row_to_insert("home_projects", proj_cols, [
        p2_id,
        2,
        "Casa López — Ocosingo",
        "Familia López Gómez",
        "Ocosingo, Centro, Chiapas",
        16.9045,
        -92.0920,
        "Vivienda progresiva de dos niveles en lote urbano.",
        "active",
        2,
        {},
        p2_created,
        p2_created,
    ]))
    lines.append("\n")

    # --- 5. STAGES ---
    lines.append("-- Etapas de los proyectos\n")
    stage_cols = [
        "id", "project_id", "stage_number", "slug", "title", "status",
        "notes", "checklist_json", "started_at", "completed_at", "analysis_id"
    ]
    catalog = load_stage_catalog()
    stage_notes_p1 = {
        1: "Brief y necesidades validadas con el cliente. Programa de 180 m² aprobado.",
        2: "Levantamiento topográfico y estudio de mecánica de suelos completados.",
        3: "Esquema funcional y zonificación de áreas pública/privada/servicio definidos.",
        4: "Anteproyecto arquitectónico volumétrico aprobado por el cliente.",
        5: "Planos arquitectónicos ejecutivos y cuadro de especificaciones listos.",
        6: "Memorias de cálculo estructural e ingenierías (hidrosanitaria y eléctrica) aprobadas.",
        7: "Presupuesto base de $1.85 MDP y cronograma de obra acordados.",
        8: "Construcción física finalizada al 100%. Bitácora de obra con supervisión continua.",
        9: "Recepción de obra, punch list cerrado y expediente digital entregado.",
    }

    stage_id_counter = 1
    # Etapas para P1 (todas completed)
    for st_def in catalog:
        num = int(st_def["number"])
        st_date = p1_created + timedelta(days=num * 14)
        comp_date = st_date + timedelta(days=12)
        chk = [{"key": it["key"], "label": it["label"], "done": True} for it in st_def.get("items", [])]
        lines.append(row_to_insert("home_project_stages", stage_cols, [
            stage_id_counter,
            p1_id,
            num,
            st_def["slug"],
            st_def["title"],
            "completed",
            stage_notes_p1.get(num, "Etapa completada."),
            chk,
            st_date,
            comp_date,
            None,
        ]))
        stage_id_counter += 1

    # Etapas para P2
    for st_def in catalog:
        num = int(st_def["number"])
        status = "completed" if num == 1 else ("in_progress" if num == 2 else "pending")
        chk = [{"key": it["key"], "label": it["label"], "done": num == 1} for it in st_def.get("items", [])]
        lines.append(row_to_insert("home_project_stages", stage_cols, [
            stage_id_counter,
            p2_id,
            num,
            st_def["slug"],
            st_def["title"],
            status,
            "",
            chk,
            p2_created if num <= 2 else None,
            p2_created + timedelta(days=10) if num == 1 else None,
            None,
        ]))
        stage_id_counter += 1
    lines.append("\n")

    # --- 6. SECTIONS ---
    lines.append("-- Apartados de etapas (Sections)\n")
    sec_cols = [
        "id", "project_id", "stage_number", "title", "description",
        "sort_order", "status", "created_by", "is_catalog",
        "slots_json", "created_at", "updated_at"
    ]
    catalog_sections = {int(st["number"]): st.get("sections") or [] for st in catalog}
    sec_id_counter = 1
    p1_section_ids_by_stage: dict[int, list[int]] = {}

    for num in range(1, 10):
        specs = catalog_sections.get(num, [])
        for order, spec in enumerate(specs):
            lines.append(row_to_insert("home_project_sections", sec_cols, [
                sec_id_counter,
                p1_id,
                num,
                spec["title"],
                spec.get("description", ""),
                order,
                "completed",
                2,
                True,
                spec.get("slots", []),
                p1_created,
                p1_created,
            ]))
            p1_section_ids_by_stage.setdefault(num, []).append(sec_id_counter)
            sec_id_counter += 1

    # Secciones para P2
    for num in range(1, 10):
        specs = catalog_sections.get(num, [])
        for order, spec in enumerate(specs):
            lines.append(row_to_insert("home_project_sections", sec_cols, [
                sec_id_counter,
                p2_id,
                num,
                spec["title"],
                spec.get("description", ""),
                order,
                "completed" if num == 1 else "pending",
                2,
                True,
                spec.get("slots", []),
                p2_created,
                p2_created,
            ]))
            sec_id_counter += 1
    lines.append("\n")

    # --- 7. MEMBERS ---
    lines.append("-- Colaboradores asignados al proyecto demo\n")
    mem_cols = ["id", "project_id", "user_id", "role", "joined_at"]
    members_data = [
        (1, p1_id, 3, "editor", p1_created + timedelta(days=5)),
        (2, p1_id, 4, "editor", p1_created + timedelta(days=7)),
        (3, p1_id, 5, "viewer", p1_created + timedelta(days=10)),
        (4, p2_id, 3, "editor", p2_created + timedelta(days=3)),
    ]
    for m in members_data:
        lines.append(row_to_insert("home_project_members", mem_cols, list(m)))
    lines.append("\n")

    # --- 8. DOCUMENTS ---
    lines.append("-- Documentación técnica cargada en el expediente\n")
    doc_cols = [
        "id", "project_id", "user_id", "stage_number", "section_id", "slot_key",
        "original_filename", "stored_path", "mime_type", "file_size",
        "description", "analysis_id", "created_at"
    ]
    doc_templates = [
        (1, "brief_necesidades_cliente.pdf", "application/pdf", 145000),
        (2, "estudio_topografico_deslinde.pdf", "application/pdf", 280000),
        (3, "esquema_zonificacion.pdf", "application/pdf", 95000),
        (4, "anteproyecto_planta_arquitectonica.pdf", "application/pdf", 450000),
        (5, "plano_arquitectonico_ejecutivo.pdf", "application/pdf", 820000),
        (6, "memoria_calculo_estructural.pdf", "application/pdf", 610000),
        (6, "instalaciones_hidrosanitarias_electricas.pdf", "application/pdf", 540000),
        (7, "catalogo_conceptos_presupuesto.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 112000),
        (7, "cronograma_ruta_critica.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 88000),
        (8, "bitacora_supervision_obra.pdf", "application/pdf", 730000),
        (8, "fotos_avance_fachada_final.jpg", "image/jpeg", 320000),
        (9, "acta_entrega_recepcion_firmada.pdf", "application/pdf", 210000),
        (9, "expediente_cierre_digital.pdf", "application/pdf", 950000),
    ]

    for d_idx, (st_num, fname, mime, sz) in enumerate(doc_templates, start=1):
        sec_ids = p1_section_ids_by_stage.get(st_num, [1])
        s_id = sec_ids[0]
        lines.append(row_to_insert("home_project_documents", doc_cols, [
            d_idx,
            p1_id,
            2,
            st_num,
            s_id,
            "doc",
            fname,
            f"data/home_projects/{p1_id}/{fname}",
            mime,
            sz,
            f"Documento técnico correspondiente a la etapa {st_num}",
            None,
            p1_created + timedelta(days=st_num * 12),
        ]))
    lines.append("\n")

    # --- 9. SECTION COMMENTS ---
    lines.append("-- Comentarios técnicos de revisión en apartados\n")
    comm_cols = ["id", "section_id", "user_id", "body", "created_at"]
    comments = [
        (1, p1_section_ids_by_stage[1][0], 3, "Brief validado con la familia: se aprueba la zonificación con patio central y recámara en planta baja.", p1_created + timedelta(days=14)),
        (2, p1_section_ids_by_stage[2][0], 4, "Estudio topográfico y mecánica de suelos concluidos: capacidad de carga óptima de 1.8 kg/cm².", p1_created + timedelta(days=28)),
        (3, p1_section_ids_by_stage[4][0], 3, "Anteproyecto aprobado por el cliente sin observaciones. Pasamos al desarrollo del proyecto ejecutivo.", p1_created + timedelta(days=45)),
        (4, p1_section_ids_by_stage[6][0], 4, "Cálculo estructural revisado conforme al código sísmico de Chiapas: zapatas aisladas y trabes de liga listas.", p1_created + timedelta(days=70)),
        (5, p1_section_ids_by_stage[7][0], 3, "Catálogo de conceptos y presupuesto de $1.85 MDP cerrado favorablemente con contratistas.", p1_created + timedelta(days=85)),
        (6, p1_section_ids_by_stage[8][0], 5, "Supervisión diaria en bitácora: colado de losas e instalaciones concluidas con éxito.", p1_created + timedelta(days=120)),
        (7, p1_section_ids_by_stage[9][0], 2, "Acta de entrega formal y recepción técnica firmada. Expediente cerrado al 100%.", p1_created + timedelta(days=140)),
    ]
    for c in comments:
        lines.append(row_to_insert("home_project_section_comments", comm_cols, list(c)))
    lines.append("\n")

    # --- 10. EVENTS ---
    lines.append("-- Línea de tiempo / Historial de eventos\n")
    evt_cols = ["id", "project_id", "actor_user_id", "event_type", "metadata_json", "created_at"]
    events_data = [
        (1, p1_id, 2, "stage_completed", {"description": "Etapa 1 inicializada y validada con cliente."}, p1_created + timedelta(days=14)),
        (2, p1_id, 2, "member_invited", {"description": "Arq. Ana Morales se unió como Editora técnica."}, p1_created + timedelta(days=15)),
        (3, p1_id, 2, "member_invited", {"description": "Ing. Carlos Ruiz se unió como Editor estructural."}, p1_created + timedelta(days=16)),
        (4, p1_id, 2, "document_uploaded", {"description": "Se cargaron los planos ejecutivos de la Etapa 5."}, p1_created + timedelta(days=60)),
        (5, p1_id, 2, "stage_advanced", {"description": "Etapa 6 completada con aprobación estructural e hidrosanitaria."}, p1_created + timedelta(days=75)),
        (6, p1_id, 2, "stage_advanced", {"description": "Presupuesto y contratos cerrados en Etapa 7."}, p1_created + timedelta(days=90)),
        (7, p1_id, 2, "stage_advanced", {"description": "Construcción física finalizada al 100% en Etapa 8."}, p1_created + timedelta(days=125)),
        (8, p1_id, 2, "stage_advanced", {"description": "Expediente de obra concluido al 100% y entregado formalmente."}, p1_created + timedelta(days=145)),
    ]
    for ev in events_data:
        lines.append(row_to_insert("home_project_events", evt_cols, list(ev)))
    lines.append("\n")

    lines.append("SET FOREIGN_KEY_CHECKS = 1;\n")
    lines.append("-- Fin del dump ARCHITECT\n")

    return "".join(lines)


def main() -> int:
    sql = generate_sql()
    
    # 1. Guardar en database/architect.sql (carpeta visible en raíz)
    db_dir = WORKSPACE_ROOT / "database"
    db_dir.mkdir(parents=True, exist_ok=True)
    out1 = db_dir / "architect.sql"
    out1.write_text(sql, encoding="utf-8", newline="\n")

    # 2. Guardar en backend/scripts/db/architect.sql (carpeta técnica existente)
    out2 = WORKSPACE_ROOT / "backend" / "scripts" / "db" / "architect.sql"
    out2.parent.mkdir(parents=True, exist_ok=True)
    out2.write_text(sql, encoding="utf-8", newline="\n")

    print(f"Dump SQL generado exitosamente:")
    print(f"  1. {out1} ({out1.stat().st_size} bytes)")
    print(f"  2. {out2} ({out2.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
