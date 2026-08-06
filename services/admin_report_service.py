"""Generación de resúmenes administrativos por rango de fechas (CSV / PDF)."""

from __future__ import annotations

import csv
import io
from datetime import date, datetime, time
from typing import Any

from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from db.models import (
    Analysis,
    BillingReceipt,
    Chat,
    GuestTrial,
    HomeProject,
    HomeProjectDocument,
    HomeProjectEvent,
    HomeProjectStatus,
    Message,
    Plan,
    Subscription,
    UsageRecord,
    User,
)

EVENT_LABELS = {
    "section_assigned": "Apartado asignado",
    "section_status_changed": "Estado de apartado",
    "section_reopened": "Apartado reabierto",
    "section_comment_added": "Comentario",
    "section_comment_deleted": "Comentario eliminado",
    "document_uploaded": "Documento subido",
    "document_deleted": "Documento eliminado",
    "member_invited": "Invitación enviada",
    "member_joined": "Miembro unido",
    "member_removed": "Miembro removido",
    "stage_completed": "Etapa completada",
    "stage_reopened": "Etapa reabierta",
    "stage_advanced": "Etapa avanzada",
}


def parse_report_dates(date_from: str, date_to: str) -> tuple[datetime, datetime]:
    try:
        start_day = date.fromisoformat(date_from.strip())
        end_day = date.fromisoformat(date_to.strip())
    except ValueError as exc:
        raise ValueError("Fechas inválidas. Usa formato YYYY-MM-DD.") from exc

    if end_day < start_day:
        raise ValueError("La fecha final debe ser igual o posterior a la inicial.")

    span = (end_day - start_day).days
    if span > 366:
        raise ValueError("El período máximo es de 366 días.")

    start = datetime.combine(start_day, time.min)
    end = datetime.combine(end_day, time.max.replace(microsecond=0))
    return start, end


def _period_keys_between(start: datetime, end: datetime) -> list[str]:
    keys: list[str] = []
    cursor = date(start.year, start.month, 1)
    last = date(end.year, end.month, 1)
    while cursor <= last:
        keys.append(f"{cursor.year:04d}-{cursor.month:02d}")
        if cursor.month == 12:
            cursor = date(cursor.year + 1, 1, 1)
        else:
            cursor = date(cursor.year, cursor.month + 1, 1)
    return keys


def _safe_count(db: Session, model, start: datetime, end: datetime, *extra) -> int:
    try:
        q = db.query(func.count(model.id)).filter(
            model.created_at >= start,
            model.created_at <= end,
            *extra,
        )
        return int(q.scalar() or 0)
    except Exception:
        db.rollback()
        return 0


def build_period_report(db: Session, start: datetime, end: datetime) -> dict[str, Any]:
    users_new = _safe_count(db, User, start, end)
    users_google = (
        db.query(func.count(User.id))
        .filter(
            User.created_at >= start,
            User.created_at <= end,
            User.oauth_provider == "google",
        )
        .scalar()
        or 0
    )
    analyses_total = _safe_count(db, Analysis, start, end)
    analyses_demo = (
        db.query(func.count(Analysis.id))
        .filter(
            Analysis.created_at >= start,
            Analysis.created_at <= end,
            Analysis.is_demo_model.is_(True),
        )
        .scalar()
        or 0
    )
    analyses_training = (
        db.query(func.count(Analysis.id))
        .filter(
            Analysis.created_at >= start,
            Analysis.created_at <= end,
            Analysis.training_eligible.is_(True),
        )
        .scalar()
        or 0
    )
    chats_new = _safe_count(db, Chat, start, end)
    messages_new = (
        db.query(func.count(Message.id))
        .filter(Message.created_at >= start, Message.created_at <= end)
        .scalar()
        or 0
    )
    projects_new = _safe_count(db, HomeProject, start, end)
    projects_completed = (
        db.query(func.count(HomeProject.id))
        .filter(
            HomeProject.status == HomeProjectStatus.completed,
            HomeProject.updated_at >= start,
            HomeProject.updated_at <= end,
        )
        .scalar()
        or 0
    )
    documents_new = _safe_count(db, HomeProjectDocument, start, end)
    events_new = _safe_count(db, HomeProjectEvent, start, end)
    guest_sessions = (
        db.query(func.count(GuestTrial.id))
        .filter(GuestTrial.last_seen_at >= start, GuestTrial.last_seen_at <= end)
        .scalar()
        or 0
    )
    guest_analyses = int(
        db.query(func.coalesce(func.sum(GuestTrial.analyses_count), 0))
        .filter(GuestTrial.last_seen_at >= start, GuestTrial.last_seen_at <= end)
        .scalar()
        or 0
    )
    period_keys = _period_keys_between(start, end)
    usage_analyses = int(
        db.query(func.coalesce(func.sum(UsageRecord.analyses_count), 0))
        .filter(UsageRecord.period_key.in_(period_keys))
        .scalar()
        or 0
    )

    plan_rows = (
        db.query(Plan.slug, Plan.name, func.count(Subscription.id))
        .outerjoin(Subscription, Subscription.plan_id == Plan.id)
        .group_by(Plan.id, Plan.slug, Plan.name)
        .order_by(Plan.sort_order.asc())
        .all()
    )

    users_list = (
        db.query(User)
        .filter(User.created_at >= start, User.created_at <= end)
        .order_by(User.created_at.desc())
        .limit(500)
        .all()
    )
    analyses_list = (
        db.query(Analysis)
        .options(joinedload(Analysis.user))
        .filter(Analysis.created_at >= start, Analysis.created_at <= end)
        .order_by(Analysis.created_at.desc())
        .limit(500)
        .all()
    )
    projects_list = (
        db.query(HomeProject)
        .options(joinedload(HomeProject.user))
        .filter(HomeProject.created_at >= start, HomeProject.created_at <= end)
        .order_by(HomeProject.created_at.desc())
        .limit(300)
        .all()
    )
    events_list = (
        db.query(HomeProjectEvent)
        .options(
            joinedload(HomeProjectEvent.project),
            joinedload(HomeProjectEvent.actor),
        )
        .filter(HomeProjectEvent.created_at >= start, HomeProjectEvent.created_at <= end)
        .order_by(HomeProjectEvent.created_at.desc())
        .limit(300)
        .all()
    )

    kpis = [
        ("Usuarios nuevos", users_new),
        ("Registros con Google", users_google),
        ("Registros con correo", max(users_new - int(users_google), 0)),
        ("Análisis en el período", analyses_total),
        ("Análisis modelo demo", int(analyses_demo)),
        ("Análisis modelo real", max(analyses_total - int(analyses_demo), 0)),
        ("Elegibles entrenamiento", int(analyses_training)),
        ("Uso facturado (meses cubiertos)", usage_analyses),
        ("Chats creados", chats_new),
        ("Mensajes enviados", int(messages_new)),
        ("Proyectos casa hogar nuevos", projects_new),
        ("Proyectos completados (aprox.)", int(projects_completed)),
        ("Documentos subidos", documents_new),
        ("Eventos de auditoría", events_new),
        ("Sesiones invitado activas", int(guest_sessions)),
        ("Análisis de invitados", guest_analyses),
    ]

    return {
        "meta": {
            "title": "ARCHITECT — Resumen administrativo",
            "from": start.date().isoformat(),
            "to": end.date().isoformat(),
            "generated_at": datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
            "period_keys": period_keys,
        },
        "kpis": [{"label": label, "value": value} for label, value in kpis],
        "plans": [
            {
                "slug": slug,
                "name": name,
                "subscribers": int(count or 0),
            }
            for slug, name, count in plan_rows
        ],
        "users": [
            {
                "id": u.id,
                "email": u.email,
                "full_name": u.full_name or "",
                "role": u.role.value,
                "oauth_provider": u.oauth_provider or "email",
                "created_at": u.created_at.isoformat() if u.created_at else "",
            }
            for u in users_list
        ],
        "analyses": [
            {
                "id": a.id,
                "user_email": a.user.email if a.user else "",
                "filename": a.original_filename,
                "is_demo": "Sí" if a.is_demo_model else "No",
                "training": "Sí" if a.training_eligible else "No",
                "created_at": a.created_at.isoformat() if a.created_at else "",
            }
            for a in analyses_list
        ],
        "home_projects": [
            {
                "id": p.id,
                "name": p.name,
                "client": p.client_name or "",
                "owner": p.user.email if p.user else "",
                "status": p.status.value,
                "stage": p.current_stage,
                "created_at": p.created_at.isoformat() if p.created_at else "",
            }
            for p in projects_list
        ],
        "activity": [
            {
                "date": e.created_at.isoformat() if e.created_at else "",
                "project": e.project.name if e.project else e.project_id,
                "event": EVENT_LABELS.get(e.event_type.value, e.event_type.value),
                "actor": e.actor.email if e.actor else "Sistema",
            }
            for e in events_list
        ],
    }


def _filename_slug(report: dict[str, Any]) -> str:
    meta = report["meta"]
    return f"architect-resumen_{meta['from']}_{meta['to']}"


def report_to_csv(report: dict[str, Any]) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf)
    meta = report["meta"]

    writer.writerow([meta["title"]])
    writer.writerow(["Período desde", meta["from"]])
    writer.writerow(["Período hasta", meta["to"]])
    writer.writerow(["Generado (UTC)", meta["generated_at"]])
    writer.writerow(["Meses de uso incluidos", ", ".join(meta["period_keys"])])
    writer.writerow([])

    writer.writerow(["MÉTRICAS DEL PERÍODO"])
    writer.writerow(["Métrica", "Valor"])
    for row in report["kpis"]:
        writer.writerow([row["label"], row["value"]])
    writer.writerow([])

    writer.writerow(["DISTRIBUCIÓN POR PLAN (suscriptores actuales)"])
    writer.writerow(["Plan", "Slug", "Suscriptores"])
    for p in report["plans"]:
        writer.writerow([p["name"], p["slug"], p["subscribers"]])
    writer.writerow([])

    writer.writerow(["USUARIOS NUEVOS EN EL PERÍODO"])
    writer.writerow(["ID", "Correo", "Nombre", "Rol", "Proveedor", "Alta"])
    for u in report["users"]:
        writer.writerow(
            [u["id"], u["email"], u["full_name"], u["role"], u["oauth_provider"], u["created_at"]]
        )
    writer.writerow([])

    writer.writerow(["ANÁLISIS EN EL PERÍODO"])
    writer.writerow(["ID", "Usuario", "Archivo", "Demo", "Entrenamiento", "Fecha"])
    for a in report["analyses"]:
        writer.writerow(
            [a["id"], a["user_email"], a["filename"], a["is_demo"], a["training"], a["created_at"]]
        )
    writer.writerow([])

    writer.writerow(["PROYECTOS CASA HOGAR NUEVOS"])
    writer.writerow(["ID", "Nombre", "Cliente", "Propietario", "Estado", "Etapa", "Alta"])
    for p in report["home_projects"]:
        writer.writerow(
            [p["id"], p["name"], p["client"], p["owner"], p["status"], p["stage"], p["created_at"]]
        )
    writer.writerow([])

    writer.writerow(["ACTIVIDAD CASA HOGAR"])
    writer.writerow(["Fecha", "Proyecto", "Evento", "Actor"])
    for e in report["activity"]:
        writer.writerow([e["date"], e["project"], e["event"], e["actor"]])

    return buf.getvalue().encode("utf-8-sig")


def _esc_html(text: Any) -> str:
    s = str(text if text is not None else "")
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def report_to_pdf(report: dict[str, Any]) -> bytes:
    try:
        from fpdf import FPDF
    except ImportError as exc:
        raise RuntimeError("Instala fpdf2 para exportar PDF: pip install fpdf2") from exc

    meta = report["meta"]
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=14)
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 16)
    pdf.cell(0, 10, "ARCHITECT - Resumen administrativo", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", size=10)
    pdf.cell(0, 6, f"Periodo: {meta['from']} a {meta['to']}", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, f"Generado (UTC): {meta['generated_at']}", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)

    kpi_rows = "".join(
        f"<tr><td>{_esc_html(r['label'])}</td><td align='right'>{_esc_html(r['value'])}</td></tr>"
        for r in report["kpis"]
    )
    plan_rows = "".join(
        f"<tr><td>{_esc_html(p['name'])}</td><td>{_esc_html(p['slug'])}</td>"
        f"<td align='right'>{_esc_html(p['subscribers'])}</td></tr>"
        for p in report["plans"]
    )

    def _table_html(title: str, headers: list[str], rows_html: str, empty_msg: str) -> str:
        head = "".join(f"<th>{_esc_html(h)}</th>" for h in headers)
        body = rows_html or f"<tr><td colspan='{len(headers)}'>{_esc_html(empty_msg)}</td></tr>"
        return f"""
        <h2 style="font-size:12px;">{_esc_html(title)}</h2>
        <table border="1" cellpadding="4" cellspacing="0" width="100%">
          <thead><tr>{head}</tr></thead>
          <tbody>{body}</tbody>
        </table>
        <br/>
        """

    user_rows = "".join(
        f"<tr><td>{u['id']}</td><td>{_esc_html(u['email'])}</td>"
        f"<td>{_esc_html(u['full_name'])}</td><td>{_esc_html(u['created_at'][:10])}</td></tr>"
        for u in report["users"][:40]
    )
    analysis_rows = "".join(
        f"<tr><td>{a['id']}</td><td>{_esc_html(a['user_email'])}</td>"
        f"<td>{_esc_html(a['filename'])}</td><td>{_esc_html(a['is_demo'])}</td></tr>"
        for a in report["analyses"][:40]
    )
    project_rows = "".join(
        f"<tr><td>{_esc_html(p['name'])}</td><td>{_esc_html(p['owner'])}</td>"
        f"<td>{_esc_html(p['status'])}</td><td>{p['stage']}</td></tr>"
        for p in report["home_projects"][:30]
    )
    activity_rows = "".join(
        f"<tr><td>{_esc_html(e['date'][:16].replace('T', ' '))}</td>"
        f"<td>{_esc_html(e['project'])}</td><td>{_esc_html(e['event'])}</td></tr>"
        for e in report["activity"][:35]
    )

    html = f"""
    <h2 style="font-size:12px;">Metricas del periodo</h2>
    <table border="1" cellpadding="4" cellspacing="0" width="60%">
      <thead><tr><th>Metrica</th><th>Valor</th></tr></thead>
      <tbody>{kpi_rows}</tbody>
    </table>
    <br/>
    <h2 style="font-size:12px;">Distribucion por plan (suscriptores actuales)</h2>
    <table border="1" cellpadding="4" cellspacing="0" width="80%">
      <thead><tr><th>Plan</th><th>Slug</th><th>Suscriptores</th></tr></thead>
      <tbody>{plan_rows}</tbody>
    </table>
    <br/>
    {_table_html("Usuarios nuevos (max 40)", ["ID", "Correo", "Nombre", "Alta"], user_rows, "Sin registros")}
    {_table_html("Analisis (max 40)", ["ID", "Usuario", "Archivo", "Demo"], analysis_rows, "Sin analisis")}
    {_table_html("Proyectos nuevos (max 30)", ["Proyecto", "Propietario", "Estado", "Etapa"], project_rows, "Sin proyectos")}
    {_table_html("Actividad casa hogar (max 35)", ["Fecha", "Proyecto", "Evento"], activity_rows, "Sin actividad")}
    """

    pdf.write_html(html)
    out = pdf.output()
    if isinstance(out, bytearray):
        return bytes(out)
    if isinstance(out, bytes):
        return out
    return str(out).encode("latin-1")


def export_report(report: dict[str, Any], fmt: str) -> tuple[bytes, str, str]:
    slug = _filename_slug(report)
    fmt = (fmt or "csv").strip().lower()
    if fmt in ("csv", "xlsx", "excel"):
        return (
            report_to_csv(report),
            f"{slug}.csv",
            "text/csv; charset=utf-8",
        )
    if fmt == "pdf":
        return (
            report_to_pdf(report),
            f"{slug}.pdf",
            "application/pdf",
        )
    raise ValueError("Formato no soportado. Usa csv o pdf.")


# ── Exportaciones por recurso (listados del panel) ──────────────────────────

EXPORT_RESOURCES = {
    "users",
    "subscriptions",
    "plans",
    "analyses",
    "home-projects",
    "chats",
    "activity",
    "receipts",
    "guest-trials",
}


def _rows_to_csv(title: str, headers: list[str], rows: list[list[Any]]) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow([title])
    writer.writerow(headers)
    for row in rows:
        writer.writerow(row)
    return ("\ufeff" + buf.getvalue()).encode("utf-8")


def _rows_to_pdf(title: str, headers: list[str], rows: list[list[Any]]) -> bytes:
    try:
        from fpdf import FPDF
    except ImportError as exc:
        raise RuntimeError("fpdf2 no está instalado") from exc

    pdf = FPDF(orientation="L", unit="mm", format="A4")
    pdf.set_auto_page_break(auto=True, margin=12)
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 14)
    pdf.cell(0, 8, title[:80], ln=1)
    pdf.set_font("Helvetica", "", 8)
    pdf.ln(2)

    col_w = max(25, int(270 / max(len(headers), 1)))
    pdf.set_font("Helvetica", "B", 8)
    for h in headers:
        pdf.cell(col_w, 6, _esc_html(str(h))[:28], border=1)
    pdf.ln()
    pdf.set_font("Helvetica", "", 7)
    for row in rows[:200]:
        for cell in row:
            pdf.cell(col_w, 5, _esc_html(str(cell if cell is not None else ""))[:28], border=1)
        pdf.ln()
        if pdf.get_y() > 190:
            pdf.add_page()
            pdf.set_font("Helvetica", "B", 8)
            for h in headers:
                pdf.cell(col_w, 6, _esc_html(str(h))[:28], border=1)
            pdf.ln()
            pdf.set_font("Helvetica", "", 7)

    out = pdf.output()
    if isinstance(out, bytearray):
        return bytes(out)
    if isinstance(out, bytes):
        return out
    return str(out).encode("latin-1")


def build_resource_export(db: Session, resource: str) -> tuple[str, list[str], list[list[Any]]]:
    """Devuelve (título, headers, filas) para exportar un listado admin."""
    resource = (resource or "").strip().lower()
    if resource not in EXPORT_RESOURCES:
        raise ValueError(
            f"Recurso no válido. Usa: {', '.join(sorted(EXPORT_RESOURCES))}"
        )

    if resource == "users":
        rows_db = db.query(User).order_by(User.created_at.desc()).limit(2000).all()
        headers = ["ID", "Correo", "Nombre", "Rol", "Activo", "Proveedor", "Alta"]
        rows = [
            [
                u.id,
                u.email,
                u.full_name or "",
                u.role.value,
                "Sí" if u.is_active else "No",
                u.oauth_provider or "email",
                u.created_at.isoformat() if u.created_at else "",
            ]
            for u in rows_db
        ]
        return "ARCHITECT — Usuarios", headers, rows

    if resource == "plans":
        rows_db = db.query(Plan).order_by(Plan.sort_order.asc()).all()
        headers = [
            "ID",
            "Slug",
            "Nombre",
            "Precio_centavos",
            "Analisis_mes",
            "MB",
            "Modelo_real",
            "Publico",
        ]
        rows = [
            [
                p.id,
                p.slug,
                p.name,
                p.price_monthly_cents,
                p.analyses_limit_monthly,
                p.max_file_mb,
                "Sí" if p.allow_real_model else "No",
                "Sí" if p.is_public else "No",
            ]
            for p in rows_db
        ]
        return "ARCHITECT — Planes", headers, rows

    if resource == "subscriptions":
        rows_db = (
            db.query(Subscription)
            .options(joinedload(Subscription.plan), joinedload(Subscription.user))
            .order_by(Subscription.created_at.desc())
            .limit(2000)
            .all()
        )
        headers = ["ID", "Usuario", "Plan", "Estado", "Inicio_periodo", "Fin_periodo"]
        rows = [
            [
                s.id,
                s.user.email if s.user else "",
                s.plan.name if s.plan else "",
                s.status.value,
                s.current_period_start.isoformat() if s.current_period_start else "",
                s.current_period_end.isoformat() if s.current_period_end else "",
            ]
            for s in rows_db
        ]
        return "ARCHITECT — Suscripciones", headers, rows

    if resource == "analyses":
        rows_db = (
            db.query(Analysis)
            .options(joinedload(Analysis.user))
            .order_by(Analysis.created_at.desc())
            .limit(2000)
            .all()
        )
        headers = ["ID", "Usuario", "Archivo", "Demo", "Entrenamiento", "Fecha"]
        rows = [
            [
                a.id,
                a.user.email if a.user else "",
                a.original_filename or "",
                "Sí" if a.is_demo_model else "No",
                "Sí" if a.training_eligible else "No",
                a.created_at.isoformat() if a.created_at else "",
            ]
            for a in rows_db
        ]
        return "ARCHITECT — Análisis", headers, rows

    if resource == "home-projects":
        rows_db = (
            db.query(HomeProject)
            .options(joinedload(HomeProject.user))
            .order_by(HomeProject.updated_at.desc())
            .limit(2000)
            .all()
        )
        headers = ["ID", "Nombre", "Cliente", "Propietario", "Estado", "Etapa", "Actualizado"]
        rows = [
            [
                p.id,
                p.name,
                p.client_name or "",
                p.user.email if p.user else "",
                p.status.value,
                p.current_stage,
                p.updated_at.isoformat() if p.updated_at else "",
            ]
            for p in rows_db
        ]
        return "ARCHITECT — Casa hogar", headers, rows

    if resource == "chats":
        rows_db = (
            db.query(Chat)
            .options(joinedload(Chat.user))
            .order_by(Chat.updated_at.desc())
            .limit(2000)
            .all()
        )
        headers = ["ID", "Usuario", "Titulo", "Actualizado"]
        rows = [
            [
                c.id,
                c.user.email if c.user else "",
                c.title or "",
                c.updated_at.isoformat() if c.updated_at else "",
            ]
            for c in rows_db
        ]
        return "ARCHITECT — Chats", headers, rows

    if resource == "activity":
        rows_db = (
            db.query(HomeProjectEvent)
            .options(
                joinedload(HomeProjectEvent.project),
                joinedload(HomeProjectEvent.actor),
            )
            .order_by(HomeProjectEvent.created_at.desc())
            .limit(2000)
            .all()
        )
        headers = ["ID", "Fecha", "Proyecto", "Evento", "Actor"]
        rows = [
            [
                e.id,
                e.created_at.isoformat() if e.created_at else "",
                e.project.name if e.project else e.project_id,
                EVENT_LABELS.get(e.event_type.value, e.event_type.value),
                e.actor.email if e.actor else "Sistema",
            ]
            for e in rows_db
        ]
        return "ARCHITECT — Actividad", headers, rows

    if resource == "receipts":
        rows_db = (
            db.query(BillingReceipt)
            .options(joinedload(BillingReceipt.user))
            .order_by(BillingReceipt.created_at.desc())
            .limit(2000)
            .all()
        )
        headers = ["ID", "Folio", "Usuario", "Plan", "Monto_centavos", "Email_enviado", "Fecha"]
        rows = [
            [
                r.id,
                r.receipt_number or "",
                r.user.email if r.user else "",
                r.plan_name or r.plan_slug,
                r.amount_cents,
                r.email_sent_at.isoformat() if r.email_sent_at else "No",
                r.created_at.isoformat() if r.created_at else "",
            ]
            for r in rows_db
        ]
        return "ARCHITECT — Comprobantes", headers, rows

    # guest-trials
    rows_db = (
        db.query(GuestTrial).order_by(GuestTrial.last_seen_at.desc()).limit(2000).all()
    )
    headers = ["ID", "Analisis", "Preguntas", "Creado", "Ultima_visita"]
    rows = [
        [
            g.id,
            g.analyses_count,
            g.asks_count,
            g.created_at.isoformat() if g.created_at else "",
            g.last_seen_at.isoformat() if g.last_seen_at else "",
        ]
        for g in rows_db
    ]
    return "ARCHITECT — Invitados", headers, rows


def export_resource(
    db: Session, resource: str, fmt: str
) -> tuple[bytes, str, str]:
    title, headers, rows = build_resource_export(db, resource)
    slug = f"architect-{resource.replace('/', '-')}"
    fmt = (fmt or "csv").strip().lower()
    if fmt in ("csv", "xlsx", "excel"):
        return _rows_to_csv(title, headers, rows), f"{slug}.csv", "text/csv; charset=utf-8"
    if fmt == "pdf":
        return _rows_to_pdf(title, headers, rows), f"{slug}.pdf", "application/pdf"
    raise ValueError("Formato no soportado. Usa csv o pdf.")