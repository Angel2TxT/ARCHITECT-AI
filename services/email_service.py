"""Envío de correos vía SMTP (Brevo u otro proveedor)."""

from __future__ import annotations

import logging
import os
import smtplib
import ssl
from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from html import escape as html_escape

logger = logging.getLogger(__name__)


def _mail_setting(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def is_mail_configured() -> bool:
    return bool(
        _mail_setting("MAIL_HOST")
        and _mail_setting("MAIL_USERNAME")
        and _mail_setting("MAIL_PASSWORD")
        and _mail_setting("MAIL_FROM_ADDRESS")
    )


def mail_config_status() -> dict[str, object]:
    """Estado de SMTP (Brevo) sin exponer secretos."""
    host = _mail_setting("MAIL_HOST")
    missing: list[str] = []
    if not host:
        missing.append("MAIL_HOST")
    if not _mail_setting("MAIL_USERNAME"):
        missing.append("MAIL_USERNAME")
    if not _mail_setting("MAIL_PASSWORD"):
        missing.append("MAIL_PASSWORD")
    if not _mail_setting("MAIL_FROM_ADDRESS"):
        missing.append("MAIL_FROM_ADDRESS")
    return {
        "configured": not missing,
        "provider": "brevo" if "brevo" in host.lower() else ("smtp" if host else None),
        "host": host or None,
        "port": int(_mail_setting("MAIL_PORT", "587") or "587"),
        "encryption": _mail_setting("MAIL_ENCRYPTION", "tls") or "tls",
        "from_address": _mail_setting("MAIL_FROM_ADDRESS") or None,
        "from_name": _mail_setting("MAIL_FROM_NAME", "ARCHITECT") or "ARCHITECT",
        "missing": missing,
    }


def _from_header() -> str:
    address = _mail_setting("MAIL_FROM_ADDRESS")
    name = _mail_setting("MAIL_FROM_NAME", "ARCHITECT")
    if name:
        return f"{name} <{address}>"
    return address


def send_email(
    *,
    to: str,
    subject: str,
    text_body: str,
    html_body: str | None = None,
    attachments: list[tuple[str, bytes, str]] | None = None,
) -> None:
    if not is_mail_configured():
        raise RuntimeError("Correo no configurado (revisa MAIL_* en .env)")

    to = (to or "").strip().lower()
    if not to or "@" not in to:
        raise ValueError("Destinatario inválido")

    host = _mail_setting("MAIL_HOST")
    port = int(_mail_setting("MAIL_PORT", "587") or "587")
    username = _mail_setting("MAIL_USERNAME")
    password = _mail_setting("MAIL_PASSWORD")
    encryption = _mail_setting("MAIL_ENCRYPTION", "tls").lower()

    msg = MIMEMultipart("mixed")
    alt = MIMEMultipart("alternative")
    alt.attach(MIMEText(text_body, "plain", "utf-8"))
    if html_body:
        alt.attach(MIMEText(html_body, "html", "utf-8"))
    msg.attach(alt)
    for filename, content, mime in attachments or []:
        part = MIMEApplication(content, Name=filename)
        part.add_header("Content-Disposition", "attachment", filename=filename)
        if mime:
            part.set_type(mime)
        msg.attach(part)
    msg["Subject"] = subject
    msg["From"] = _from_header()
    msg["To"] = to

    if encryption == "ssl":
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(host, port, context=context, timeout=30) as smtp:
            smtp.login(username, password)
            smtp.sendmail(_mail_setting("MAIL_FROM_ADDRESS"), [to], msg.as_string())
    else:
        with smtplib.SMTP(host, port, timeout=30) as smtp:
            if encryption in ("tls", "starttls"):
                smtp.starttls(context=ssl.create_default_context())
            smtp.login(username, password)
            smtp.sendmail(_mail_setting("MAIL_FROM_ADDRESS"), [to], msg.as_string())


def _app_base_url() -> str:
    return os.getenv("APP_BASE_URL", "http://localhost:3000").rstrip("/")


def _project_url(project_id: str) -> str:
    return f"{_app_base_url()}/legacy-app?home-projects=1&project={project_id}"


def _e(value: object) -> str:
    return html_escape(str(value or ""), quote=True)


def _architect_transaction_email_html(
    *,
    badge: str,
    greeting: str,
    headline: str,
    summary_rows: list[tuple[str, str]],
    hero_label: str,
    hero_value: str,
    hero_note: str,
    cta_label: str,
    cta_url: str,
    attachment_note: str,
    legal_note: str,
) -> str:
    rows_html = "".join(
        f"""
        <tr>
          <td bgcolor="#111113" style="padding:12px 0;border-bottom:1px solid #27272a;color:#a1a1aa;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;width:38%;vertical-align:top;font-family:Segoe UI,system-ui,sans-serif;">{_e(label)}</td>
          <td bgcolor="#111113" style="padding:12px 0 12px 14px;border-bottom:1px solid #27272a;color:#fafafa;font-size:14px;font-weight:600;vertical-align:top;font-family:Segoe UI,system-ui,sans-serif;">{_e(value)}</td>
        </tr>
        """
        for label, value in summary_rows
    )
    return f"""<!DOCTYPE html>
<html lang="es" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="color-scheme" content="dark" />
  <meta name="supported-color-schemes" content="dark" />
  <title>{_e(headline)}</title>
</head>
<body bgcolor="#050505" style="margin:0;padding:0;background-color:#050505;color:#fafafa;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">{_e(headline)} · {_e(hero_value)}</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#050505" style="background-color:#050505;">
    <tr>
      <td align="center" style="padding:36px 16px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#111113" style="max-width:560px;background-color:#111113;border:1px solid #27272a;border-radius:18px;">
          <tr>
            <td bgcolor="#09090b" style="background-color:#09090b;padding:24px 28px;border-bottom:1px solid #27272a;">
              <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                <tr>
                  <td style="padding:5px 12px;border:1px solid #3f3f46;border-radius:999px;background-color:#18181b;color:#a1a1aa;font-size:10px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;font-family:Segoe UI,system-ui,sans-serif;">{_e(badge)}</td>
                </tr>
              </table>
              <div style="margin-top:16px;font-size:26px;line-height:1.1;font-weight:700;letter-spacing:-0.03em;color:#fafafa;font-family:Segoe UI,system-ui,sans-serif;">ARCHITECT</div>
              <div style="margin-top:8px;font-size:14px;line-height:1.5;color:#a1a1aa;font-family:Segoe UI,system-ui,sans-serif;">{_e(headline)}</div>
            </td>
          </tr>
          <tr>
            <td bgcolor="#86efac" height="4" style="height:4px;line-height:4px;font-size:0;background-color:#86efac;">&nbsp;</td>
          </tr>
          <tr>
            <td bgcolor="#111113" style="background-color:#111113;padding:28px;">
              <p style="margin:0 0 20px;font-size:15px;line-height:1.65;color:#fafafa;font-family:Segoe UI,system-ui,sans-serif;">{_e(greeting)}</p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#18181b" style="margin-bottom:22px;background-color:#18181b;border:1px solid #27272a;border-radius:14px;">
                <tr>
                  <td style="padding:20px 22px;">
                    <div style="font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#a1a1aa;font-family:Segoe UI,system-ui,sans-serif;">{_e(hero_label)}</div>
                    <div style="margin-top:8px;font-size:30px;line-height:1.1;font-weight:700;letter-spacing:-0.03em;color:#86efac;font-family:Segoe UI,system-ui,sans-serif;">{_e(hero_value)}</div>
                    <div style="margin-top:6px;font-size:12px;color:#a1a1aa;font-family:Segoe UI,system-ui,sans-serif;">{_e(hero_note)}</div>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin-bottom:24px;">
                {rows_html}
              </table>
              <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:0 auto 18px;">
                <tr>
                  <td bgcolor="#ffffff" align="center" style="background-color:#ffffff;border-radius:12px;">
                    <a href="{_e(cta_url)}" target="_blank" style="display:inline-block;padding:14px 30px;color:#09090b;font-size:14px;font-weight:700;text-decoration:none;font-family:Segoe UI,system-ui,sans-serif;">{_e(cta_label)}</a>
                  </td>
                </tr>
              </table>
              <p style="margin:0 0 18px;font-size:13px;line-height:1.55;color:#a1a1aa;text-align:center;font-family:Segoe UI,system-ui,sans-serif;">{_e(attachment_note)}</p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#422006" style="background-color:#422006;border:1px solid #fbbf24;border-radius:12px;">
                <tr>
                  <td style="padding:14px 16px;color:#fde68a;font-size:12px;line-height:1.6;font-family:Segoe UI,system-ui,sans-serif;">
                    <strong style="display:block;margin-bottom:4px;color:#fde68a;">AVISO LEGAL</strong>
                    {_e(legal_note)}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td bgcolor="#09090b" style="background-color:#09090b;padding:16px 28px 24px;border-top:1px solid #27272a;text-align:center;color:#71717a;font-size:11px;line-height:1.5;font-family:Segoe UI,system-ui,sans-serif;">
              ARCHITECT &middot; Proyecto escolar &middot; Pasarela simulada
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


def _send_safe(*, to_email: str, subject: str, text_body: str, html_body: str | None = None) -> bool:
    try:
        send_email(to=to_email, subject=subject, text_body=text_body, html_body=html_body)
        return True
    except Exception:
        logger.exception("No se pudo enviar correo a %s", to_email)
        return False


def send_project_invite_email(
    *,
    to_email: str,
    project_name: str,
    inviter_name: str,
    role: str,
    token: str,
) -> bool:
    role_label = "Editor" if role == "editor" else "Lector"
    invite_url = f"{_app_base_url()}/legacy-app?invite={token}"
    subject = f"Invitación al proyecto «{project_name}» — ARCHITECT"
    text_body = (
        f"Hola,\n\n"
        f"{inviter_name} te ha invitado a colaborar en el proyecto «{project_name}» "
        f"como {role_label}.\n\n"
        f"Acepta la invitación aquí (válida 14 días):\n{invite_url}\n\n"
        f"Debes iniciar sesión con este correo: {to_email}\n\n"
        f"— ARCHITECT"
    )
    html_body = f"""
    <p>Hola,</p>
    <p><strong>{inviter_name}</strong> te ha invitado a colaborar en el proyecto
    <strong>«{project_name}»</strong> como <strong>{role_label}</strong>.</p>
    <p><a href="{invite_url}">Aceptar invitación</a> (válida 14 días)</p>
    <p>Debes iniciar sesión con: <strong>{to_email}</strong></p>
    <p style="color:#666;font-size:12px">ARCHITECT</p>
    """
    return _send_safe(
        to_email=to_email,
        subject=subject,
        text_body=text_body,
        html_body=html_body,
    )


_SECTION_STATUS_LABELS = {
    "pending": "Sin documentación",
    "in_progress": "Pendiente de revisión",
    "needs_details": "Le faltan detalles",
    "needs_correction": "Requiere corrección",
    "completed": "Completado",
}


def send_section_assigned_email(
    *,
    to_email: str,
    project_name: str,
    project_id: str,
    section_title: str,
    assigner_name: str,
) -> bool:
    url = _project_url(project_id)
    subject = f"Te asignaron «{section_title}» — {project_name}"
    text_body = (
        f"Hola,\n\n"
        f"{assigner_name} te asignó el apartado «{section_title}» "
        f"en el proyecto «{project_name}».\n\n"
        f"Ver proyecto: {url}\n\n— ARCHITECT"
    )
    html_body = f"""
    <p>Hola,</p>
    <p><strong>{assigner_name}</strong> te asignó el apartado
    <strong>«{section_title}»</strong> en <strong>«{project_name}»</strong>.</p>
    <p><a href="{url}">Abrir proyecto</a></p>
    <p style="color:#666;font-size:12px">ARCHITECT</p>
    """
    return _send_safe(
        to_email=to_email,
        subject=subject,
        text_body=text_body,
        html_body=html_body,
    )


def send_section_review_email(
    *,
    to_email: str,
    project_name: str,
    project_id: str,
    section_title: str,
    reviewer_name: str,
    new_status: str,
    comment: str = "",
) -> bool:
    status_label = _SECTION_STATUS_LABELS.get(new_status, new_status)
    url = _project_url(project_id)
    subject = f"Revisión: {status_label} — «{section_title}»"
    comment_block = f"\n\nComentario:\n{comment}" if comment else ""
    text_body = (
        f"Hola,\n\n"
        f"{reviewer_name} marcó el apartado «{section_title}» como «{status_label}» "
        f"en «{project_name}».{comment_block}\n\n"
        f"Ver proyecto: {url}\n\n— ARCHITECT"
    )
    html_body = f"""
    <p>Hola,</p>
    <p><strong>{reviewer_name}</strong> revisó el apartado
    <strong>«{section_title}»</strong>: <strong>{status_label}</strong>.</p>
    {f"<blockquote style='border-left:3px solid #ddd;padding-left:12px;color:#444'>{comment}</blockquote>" if comment else ""}
    <p><a href="{url}">Abrir proyecto</a></p>
    <p style="color:#666;font-size:12px">ARCHITECT</p>
    """
    return _send_safe(
        to_email=to_email,
        subject=subject,
        text_body=text_body,
        html_body=html_body,
    )


def send_mention_email(
    *,
    to_email: str,
    project_name: str,
    project_id: str,
    section_title: str,
    author_name: str,
    comment: str,
) -> bool:
    url = _project_url(project_id)
    subject = f"Te mencionaron en «{section_title}» — {project_name}"
    text_body = (
        f"Hola,\n\n"
        f"{author_name} te mencionó en «{section_title}» ({project_name}):\n\n"
        f"{comment}\n\n"
        f"Ver proyecto: {url}\n\n— ARCHITECT"
    )
    html_body = f"""
    <p>Hola,</p>
    <p><strong>{author_name}</strong> te mencionó en
    <strong>«{section_title}»</strong> (<strong>{project_name}</strong>):</p>
    <blockquote style="border-left:3px solid #ddd;padding-left:12px;color:#444">{comment}</blockquote>
    <p><a href="{url}">Abrir proyecto</a></p>
    <p style="color:#666;font-size:12px">ARCHITECT</p>
    """
    return _send_safe(
        to_email=to_email,
        subject=subject,
        text_body=text_body,
        html_body=html_body,
    )


def send_reopen_alert_email(
    *,
    to_email: str,
    project_name: str,
    project_id: str,
    actor_name: str,
    target_label: str,
    reason: str,
    admin_override: bool = False,
) -> bool:
    url = _project_url(project_id)
    override = " (acción de administrador global)" if admin_override else ""
    subject = f"Reapertura: {target_label} — {project_name}"
    text_body = (
        f"Hola,\n\n"
        f"{actor_name} reabrió {target_label} en «{project_name}»{override}.\n\n"
        f"Motivo:\n{reason}\n\n"
        f"Ver proyecto: {url}\n\n— ARCHITECT"
    )
    html_body = f"""
    <p>Hola,</p>
    <p><strong>{actor_name}</strong> reabrió <strong>{target_label}</strong>
    en <strong>«{project_name}»</strong>{override}.</p>
    <blockquote style="border-left:3px solid #ddd;padding-left:12px;color:#444">{reason}</blockquote>
    <p><a href="{url}">Abrir proyecto</a></p>
    <p style="color:#666;font-size:12px">ARCHITECT</p>
    """
    return _send_safe(
        to_email=to_email,
        subject=subject,
        text_body=text_body,
        html_body=html_body,
    )


def send_billing_receipt_email(
    *,
    to_email: str,
    user_name: str,
    receipt_number: str,
    plan_name: str,
    amount_label: str,
    download_url: str,
    pdf_bytes: bytes,
    pdf_filename: str,
    period_label: str | None = None,
    payment_ref: str | None = None,
) -> bool:
    subject = f"Comprobante {receipt_number} - ARCHITECT"
    summary_rows: list[tuple[str, str]] = [
        ("Folio", receipt_number),
        ("Plan", plan_name),
        ("Importe", amount_label),
    ]
    if period_label:
        summary_rows.append(("Periodo", period_label))
    summary_rows.append(("Modo", "Pasarela simulada (demo)"))
    if payment_ref:
        summary_rows.append(("Referencia", payment_ref))

    text_body = (
        f"Hola {user_name},\n\n"
        f"Tu suscripcion al plan {plan_name} quedo registrada correctamente.\n\n"
        f"Folio: {receipt_number}\n"
        f"Importe: {amount_label}\n"
        + (f"Periodo: {period_label}\n" if period_label else "")
        + f"Modo: pasarela simulada (proyecto escolar, sin cargo real)\n\n"
        f"Descargar PDF: {download_url}\n\n"
        f"El comprobante tambien va adjunto en este correo (diseno ARCHITECT).\n\n"
        f"- ARCHITECT"
    )
    html_body = _architect_transaction_email_html(
        badge="Comprobante emitido",
        greeting=f"Hola {user_name}, tu plan {plan_name} ya esta activo. Guarda este comprobante para tu historial academico.",
        headline="Comprobante de suscripcion",
        summary_rows=summary_rows,
        hero_label="Total registrado",
        hero_value=amount_label,
        hero_note="Sin cargo real - simulacion academica",
        cta_label="Ver comprobante en ARCHITECT",
        cta_url=download_url,
        attachment_note="El PDF con diseno ARCHITECT va adjunto a este correo.",
        legal_note=(
            "Documento academico - no es factura fiscal. "
            "Generado con fines de demostracion en el proyecto escolar ARCHITECT."
        ),
    )
    try:
        send_email(
            to=to_email,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
            attachments=[(pdf_filename, pdf_bytes, "application/pdf")],
        )
        return True
    except Exception:
        logger.exception("No se pudo enviar comprobante a %s", to_email)
        return False


def send_password_reset_email(
    *,
    to_email: str,
    user_name: str,
    reset_url: str,
    expires_minutes: int = 60,
) -> bool:
    subject = "Recuperar contraseña — ARCHITECT"
    text_body = (
        f"Hola {user_name},\n\n"
        f"Recibimos una solicitud para restablecer tu contraseña en ARCHITECT.\n\n"
        f"Abre este enlace (valido {expires_minutes} min):\n{reset_url}\n\n"
        f"Si no lo solicitaste, ignora este correo.\n\n"
        f"— ARCHITECT"
    )
    html_body = f"""
    <p>Hola <strong>{user_name}</strong>,</p>
    <p>Recibimos una solicitud para restablecer tu contraseña en ARCHITECT.</p>
    <p><a href="{reset_url}">Restablecer contraseña</a> (válido {expires_minutes} min)</p>
    <p style="color:#666;font-size:12px">Si no lo solicitaste, ignora este correo.</p>
    """
    return _send_safe(
        to_email=to_email,
        subject=subject,
        text_body=text_body,
        html_body=html_body,
    )
