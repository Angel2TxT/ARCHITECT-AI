"""Simula un proyecto casa hogar completo (9 etapas) vía API local.

Uso:
  python scripts/simulate_full_home_project.py \\
    --email lopeztrujilloxd@gmail.com --password '***'
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import zipfile
from pathlib import Path

import httpx
from PIL import Image, ImageDraw, ImageFont

BASE = "http://localhost:8000"
ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "data" / "_sim_assets"
ASSETS.mkdir(parents=True, exist_ok=True)

STAGE_NOTES = {
    1: "Arquitecto: brief validado con familia López. Programa de 180 m², 3 recámaras, estudio y patio central.",
    2: "Arquitecto + topógrafo: predio 12×25 m en Ocosingo. Uso habitacional confirmado; pendiente leve al sur.",
    3: "Arquitecto: zonificación pública/privada/servicio aprobada. Circulación en L hacia patio.",
    4: "Arquitecto: anteproyecto con planta en L y volumetría a un nivel. Cliente eligió opción B.",
    5: "Arquitecto: planos arquitectónicos completos. Cuadro de áreas 178.4 m² construidos.",
    6: "Ing. estructural + instalaciones: cimentación corrida, HS y eléctrico listos para obra.",
    7: "Administrador de obra: presupuesto $1.85 MDP + cronograma 7 meses, 4 hitos de pago.",
    8: "Residente de obra: avance 100% estructura y acabados. Bitácora y fotos de cierre de obra.",
    9: "Dirección: punch list cerrada, acta de entrega firmada y expediente de cierre digital.",
}

COMMENTS = [
    ("owner", "Dejo el entregable cargado. Revisen y comenten hallazgos."),
    ("arq", "Revisé el documento: coincide con el programa y la normativa local."),
    ("ing", "Desde estructura/instalaciones: sin observaciones bloqueantes. Procedemos."),
]


def _client(token: str | None = None) -> httpx.Client:
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return httpx.Client(base_url=BASE, headers=headers, timeout=60.0)


def login(email: str, password: str) -> tuple[str, dict]:
    with _client() as c:
        r = c.post("/api/auth/login", json={"email": email, "password": password})
        if r.status_code >= 400:
            raise SystemExit(f"Login falló ({email}): {r.status_code} {r.text}")
        data = r.json()
        return data["access_token"], data


def register_if_needed(email: str, password: str, full_name: str) -> str:
    with _client() as c:
        r = c.post(
            "/api/auth/register",
            json={"email": email, "password": password, "full_name": full_name},
        )
        if r.status_code < 400:
            return r.json()["access_token"]
        # ya existe
        return login(email, password)[0]


def admin_set_plan(admin_token: str, user_id: int, plan_slug: str) -> None:
    with _client(admin_token) as c:
        r = c.post(f"/api/admin/users/{user_id}/plan", json={"plan_slug": plan_slug})
        if r.status_code >= 400:
            raise SystemExit(f"No se pudo subir plan: {r.status_code} {r.text}")
        print(f"  Plan usuario {user_id} -> {plan_slug}")


def _minimal_pdf(title: str, body: str) -> bytes:
    # PDF mínimo válido con texto (sin dependencias).
    content = f"BT /F1 12 Tf 50 750 Td ({title[:80]}) Tj 0 -20 Td ({body[:100]}) Tj ET"
    stream = content.encode("latin-1", errors="replace")
    objs = []
    objs.append(b"1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n")
    objs.append(b"2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n")
    objs.append(
        b"3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>endobj\n"
    )
    objs.append(
        f"4 0 obj<< /Length {len(stream)} >>stream\n".encode()
        + stream
        + b"\nendstream\nendobj\n"
    )
    objs.append(b"5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj\n")
    out = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for obj in objs:
        offsets.append(len(out))
        out.extend(obj)
    xref = len(out)
    out.extend(f"xref\n0 {len(offsets)}\n".encode())
    out.extend(b"0000000000 65535 f \n")
    for off in offsets[1:]:
        out.extend(f"{off:010d} 00000 n \n".encode())
    out.extend(
        f"trailer<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    )
    return bytes(out)


def _minimal_docx(title: str, body: str) -> bytes:
    document_xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>{title}</w:t></w:r></w:p>
    <w:p><w:r><w:t>{body}</w:t></w:r></w:p>
  </w:body>
</w:document>"""
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>"""
    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", rels)
        z.writestr("word/document.xml", document_xml)
    return buf.getvalue()


def _minimal_xlsx(sheet_title: str, rows: list[list[str]]) -> bytes:
    # SpreadsheetML mínimo
    sheet_rows = []
    for r_i, row in enumerate(rows, start=1):
        cells = []
        for c_i, val in enumerate(row):
            col = chr(ord("A") + c_i)
            safe = str(val).replace("&", "&amp;").replace("<", "&lt;")
            cells.append(f'<c r="{col}{r_i}" t="inlineStr"><is><t>{safe}</t></is></c>')
        sheet_rows.append(f"<row r=\"{r_i}\">{''.join(cells)}</row>")
    sheet = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        f"<sheetData>{''.join(sheet_rows)}</sheetData></worksheet>"
    )
    workbook = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Hoja1" sheetId="1" r:id="rId1"/></sheets>
</workbook>"""
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>"""
    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""
    wb_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>"""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", rels)
        z.writestr("xl/workbook.xml", workbook)
        z.writestr("xl/_rels/workbook.xml.rels", wb_rels)
        z.writestr("xl/worksheets/sheet1.xml", sheet)
    _ = sheet_title
    return buf.getvalue()


def _plan_image(label: str, path: Path) -> Path:
    if path.exists() and path.stat().st_size > 1000:
        return path
    img = Image.new("RGB", (1200, 900), (245, 242, 235))
    draw = ImageDraw.Draw(img)
    # Marco de predio
    draw.rectangle([80, 80, 1120, 820], outline=(30, 30, 30), width=3)
    # Habitaciones
    rooms = [
        (100, 100, 480, 420, "Sala / Comedor"),
        (500, 100, 900, 420, "Cocina"),
        (100, 440, 480, 800, "Recámara 1"),
        (500, 440, 900, 800, "Recámara 2"),
        (920, 100, 1100, 800, "Patio"),
    ]
    for x1, y1, x2, y2, name in rooms:
        draw.rectangle([x1, y1, x2, y2], outline=(60, 60, 60), width=2)
        draw.text((x1 + 16, y1 + 16), name, fill=(20, 20, 20))
    draw.text((100, 30), f"ARCHITECT · {label}", fill=(0, 0, 0))
    draw.text((100, 850), "Planta esquemática — vivienda unifamiliar Chiapas", fill=(80, 80, 80))
    img.save(path, format="JPEG", quality=88)
    return path


def download_real_samples() -> dict[str, Path]:
    """Descarga PDFs/imágenes públicas reales y genera planos locales."""
    files: dict[str, Path] = {}
    targets = {
        "sample_pdf": (
            "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf",
            ASSETS / "dummy.pdf",
        ),
        "mozilla_pdf": (
            "https://raw.githubusercontent.com/mozilla/pdf.js/master/web/compressed.tracemonkey-pldi-09.pdf",
            ASSETS / "sample-report.pdf",
        ),
        "site_photo": (
            "https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=1200",
            ASSETS / "site-photo.jpg",
        ),
        "construction_photo": (
            "https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=1200",
            ASSETS / "obra-avance.jpg",
        ),
    }
    with httpx.Client(timeout=45.0, follow_redirects=True) as c:
        for key, (url, dest) in targets.items():
            if dest.exists() and dest.stat().st_size > 500:
                files[key] = dest
                print(f"  cache {dest.name}")
                continue
            try:
                r = c.get(url, headers={"User-Agent": "ARCHITECT-sim/1.0"})
                r.raise_for_status()
                dest.write_bytes(r.content)
                files[key] = dest
                print(f"  descargado {dest.name} ({len(r.content)} bytes)")
            except Exception as exc:
                print(f"  WARN {key}: {exc}")

    files["planta"] = _plan_image("Planta arquitectónica", ASSETS / "planta.jpg")
    files["zonificacion"] = _plan_image("Zonificación", ASSETS / "zonificacion.jpg")
    files["fachada"] = _plan_image("Fachadas y cortes", ASSETS / "fachadas.jpg")
    files["hidrosanitario"] = _plan_image("Hidrosanitario", ASSETS / "hidro.jpg")
    files["electrico"] = _plan_image("Eléctrico", ASSETS / "electrico.jpg")

    brief = ASSETS / "brief-cliente.docx"
    if not brief.exists():
        brief.write_bytes(
            _minimal_docx(
                "Brief Casa López — Ocosingo",
                "Familia de 5. Necesitan 3 recámaras, estudio, cocina abierta y patio seguro.",
            )
        )
    files["brief"] = brief

    cuadro = ASSETS / "cuadro-espacios.xlsx"
    if not cuadro.exists():
        cuadro.write_bytes(
            _minimal_xlsx(
                "Espacios",
                [
                    ["Espacio", "m2", "Notas"],
                    ["Sala-comedor", "28", "Doble altura parcial"],
                    ["Cocina", "14", "Isla"],
                    ["Recámara principal", "16", "Walk-in"],
                    ["Recámara 2", "12", ""],
                    ["Recámara 3", "12", ""],
                    ["Estudio", "10", ""],
                    ["Baños", "10", "2.5"],
                    ["Patio / circulación", "30", ""],
                ],
            )
        )
    files["cuadro"] = cuadro

    presupuesto = ASSETS / "presupuesto.xlsx"
    if not presupuesto.exists():
        presupuesto.write_bytes(
            _minimal_xlsx(
                "Presupuesto",
                [
                    ["Partida", "Importe MXN"],
                    ["Preliminares", "85000"],
                    ["Cimentación", "220000"],
                    ["Estructura", "310000"],
                    ["Albañilería", "280000"],
                    ["Instalaciones", "195000"],
                    ["Acabados", "410000"],
                    ["Indirectos", "150000"],
                    ["TOTAL", "1850000"],
                ],
            )
        )
    files["presupuesto"] = presupuesto

    cronograma = ASSETS / "cronograma.xlsx"
    if not cronograma.exists():
        cronograma.write_bytes(
            _minimal_xlsx(
                "Cronograma",
                [
                    ["Mes", "Actividad"],
                    ["1", "Cimentación"],
                    ["2-3", "Estructura"],
                    ["4", "Albañilería"],
                    ["5", "Instalaciones"],
                    ["6-7", "Acabados y entrega"],
                ],
            )
        )
    files["cronograma"] = cronograma

    # PDF técnico local si falló descarga
    tech_pdf = ASSETS / "memoria-tecnica.pdf"
    if not tech_pdf.exists():
        tech_pdf.write_bytes(
            _minimal_pdf(
                "Memoria tecnica vivienda Ocosingo",
                "Cimentacion corrida, muros de block, losa aligerada.",
            )
        )
    files["tech_pdf"] = tech_pdf
    if "sample_pdf" not in files:
        files["sample_pdf"] = tech_pdf
    if "mozilla_pdf" not in files:
        files["mozilla_pdf"] = tech_pdf
    if "site_photo" not in files:
        files["site_photo"] = files["planta"]
    if "construction_photo" not in files:
        files["construction_photo"] = files["fachada"]

    return files


def pick_file(slot: dict, assets: dict[str, Path]) -> tuple[Path, str]:
    accept = [a.lower() for a in (slot.get("accept") or [])]
    key = slot.get("key") or ""
    title = slot.get("title") or key

    def first_ext(*exts: str) -> str | None:
        for e in exts:
            if e in accept or not accept:
                return e
        return accept[0] if accept else ".pdf"

    # Preferencias semánticas
    if any(k in key for k in ("foto", "fotos", "avance", "volumetria", "render")):
        if ".jpg" in accept or ".jpeg" in accept or ".png" in accept or not accept:
            src = assets["construction_photo"] if "avance" in key else assets["site_photo"]
            return src, f"{key}{src.suffix}"
    if any(k in key for k in ("planta", "diagrama", "zonificacion", "fachada", "constructiva", "hidro", "electric")):
        mapping = {
            "zonificacion": assets["zonificacion"],
            "diagrama": assets["zonificacion"],
            "fachada": assets["fachada"],
            "hidro": assets["hidrosanitario"],
            "electric": assets["electrico"],
        }
        src = assets["planta"]
        for frag, path in mapping.items():
            if frag in key:
                src = path
                break
        return src, f"{key}.jpg"
    if "presupuesto" in key or "proveedor" in key:
        return assets["presupuesto"], f"{key}.xlsx"
    if "cronograma" in key or "hito" in key:
        return assets["cronograma"], f"{key}.xlsx"
    if "cuadro" in key or "espacio" in key or "area" in key:
        return assets["cuadro"], f"{key}.xlsx"
    if "brief" in key or "entrevista" in key:
        return assets["brief"], f"{key}.docx"
    if first_ext(".pdf") == ".pdf" or ".pdf" in accept:
        src = assets["mozilla_pdf"] if "estudio" in key or "memoria" in key else assets["sample_pdf"]
        if "estructural" in key or "memoria" in key or "norma" in key or "uso_suelo" in key:
            src = assets["tech_pdf"] if "tech_pdf" in assets else assets["sample_pdf"]
        return src, f"{key}.pdf"
    if ".docx" in accept or ".doc" in accept:
        return assets["brief"], f"{key}.docx"
    if ".xlsx" in accept or ".xls" in accept:
        return assets["cuadro"], f"{key}.xlsx"
    if ".jpg" in accept or ".jpeg" in accept or ".png" in accept:
        return assets["planta"], f"{key}.jpg"
    return assets["sample_pdf"], f"{key}.pdf"


def upload_doc(
    token: str,
    project_id: str,
    stage_number: int,
    section_id: int,
    slot_key: str,
    path: Path,
    filename: str,
) -> None:
    with _client(token) as c:
        with path.open("rb") as fh:
            r = c.post(
                f"/api/home-projects/{project_id}/stages/{stage_number}/documents",
                files={"file": (filename, fh, "application/octet-stream")},
                data={"section_id": str(section_id), "slot_key": slot_key},
            )
        if r.status_code >= 400:
            raise RuntimeError(f"Upload {filename}: {r.status_code} {r.text[:300]}")


def patch_section(token: str, project_id: str, section_id: int, **payload) -> dict:
    with _client(token) as c:
        r = c.patch(f"/api/home-projects/{project_id}/sections/{section_id}", json=payload)
        if r.status_code >= 400:
            raise RuntimeError(f"patch section: {r.status_code} {r.text[:300]}")
        return r.json()


def add_comment(token: str, project_id: str, section_id: int, body: str) -> None:
    with _client(token) as c:
        r = c.post(
            f"/api/home-projects/{project_id}/sections/{section_id}/comments",
            json={"body": body},
        )
        if r.status_code >= 400:
            print(f"  WARN comment: {r.status_code} {r.text[:200]}")


def patch_stage(token: str, project_id: str, stage_number: int, **payload) -> None:
    with _client(token) as c:
        r = c.patch(
            f"/api/home-projects/{project_id}/stages/{stage_number}",
            json=payload,
        )
        if r.status_code >= 400:
            raise RuntimeError(f"patch stage: {r.status_code} {r.text[:300]}")


def advance(token: str, project_id: str) -> dict:
    with _client(token) as c:
        r = c.post(
            f"/api/home-projects/{project_id}/advance",
            json={"acknowledge_open_findings": True},
        )
        if r.status_code >= 400:
            raise RuntimeError(f"advance: {r.status_code} {r.text[:400]}")
        return r.json()


def get_project(token: str, project_id: str) -> dict:
    with _client(token) as c:
        r = c.get(f"/api/home-projects/{project_id}")
        r.raise_for_status()
        return r.json()


def stage_by_number(project: dict, n: int) -> dict:
    return next(s for s in project["stages"] if s["stage_number"] == n)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--admin-email", default="admin@architect.local")
    ap.add_argument("--admin-password", default="admin123")
    args = ap.parse_args()

    print("1) Login propietario…")
    owner_token, owner_auth = login(args.email, args.password)
    owner = owner_auth.get("user") or {}
    owner_id = owner.get("id")
    print(f"   OK {owner.get('email')} id={owner_id}")

    print("2) Subir a Enterprise (invites + cupo)…")
    admin_token, _ = login(args.admin_email, args.admin_password)
    admin_set_plan(admin_token, int(owner_id), "enterprise")

    print("3) Registrar colaboradores…")
    arq_email = "arq.colaborador.architect@gmail.com"
    ing_email = "ing.colaborador.architect@gmail.com"
    collab_pass = "Colaborador123!"
    arq_token = register_if_needed(arq_email, collab_pass, "Arq. Ana Morales")
    ing_token = register_if_needed(ing_email, collab_pass, "Ing. Carlos Ruiz")
    print(f"   {arq_email} / {ing_email}")

    print("4) Descargar / generar archivos…")
    assets = download_real_samples()

    print("5) Crear proyecto…")
    with _client(owner_token) as c:
        r = c.post(
            "/api/home-projects",
            json={
                "name": "Casa López — Ocosingo (simulación completa)",
                "client_name": "Familia López Hernández",
                "location": "Ocosingo, Centro, Chiapas",
                "latitude": 16.9072,
                "longitude": -92.0942,
                "description": (
                    "Proyecto demostración 100%: vivienda unifamiliar de un nivel, "
                    "180 m², patio central. Equipo: arquitecto + ingeniero + propietario."
                ),
            },
        )
        if r.status_code >= 400:
            raise SystemExit(f"Crear proyecto: {r.status_code} {r.text}")
        project = r.json()
    project_id = project["id"]
    print(f"   id={project_id}")

    print("6) Invitar colaboradores…")
    with _client(owner_token) as c:
        for email, role in ((arq_email, "editor"), (ing_email, "editor")):
            r = c.post(
                f"/api/home-projects/{project_id}/members/invite",
                json={"email": email, "role": role},
            )
            print(f"   invite {email}: {r.status_code} {r.json().get('status') if r.status_code < 400 else r.text[:120]}")

    tokens = {"owner": owner_token, "arq": arq_token, "ing": ing_token}

    print("7) Recorrer 9 etapas…")
    for n in range(1, 10):
        project = get_project(owner_token, project_id)
        stage = stage_by_number(project, n)
        print(f"\n=== Etapa {n}: {stage['title']} ===")
        patch_stage(
            owner_token,
            project_id,
            n,
            status="in_progress",
            notes=STAGE_NOTES[n],
        )

        sections = stage.get("sections") or []
        for sec in sections:
            sec_id = sec["id"]
            print(f"  Apartado: {sec['title']}")
            assignee_token_key = "arq" if n <= 5 else "ing"

            # 1) Subir documentos primero (requisito para asignar/revisar)
            for slot in sec.get("slots") or []:
                path, filename = pick_file(slot, assets)
                try:
                    upload_doc(
                        owner_token,
                        project_id,
                        n,
                        sec_id,
                        slot["key"],
                        path,
                        filename,
                    )
                    print(f"    ↑ {slot['key']} ← {filename}")
                except Exception as exc:
                    print(f"    FAIL {slot['key']}: {exc}")

            # 2) Asignar responsable
            project = get_project(owner_token, project_id)
            members = project.get("members") or []
            assignee_user = None
            for m in members:
                email = (m.get("email") or "").lower()
                if assignee_token_key == "arq" and "arq" in email:
                    assignee_user = m.get("user_id")
                if assignee_token_key == "ing" and "ing" in email:
                    assignee_user = m.get("user_id")
            if assignee_user:
                try:
                    patch_section(
                        owner_token,
                        project_id,
                        sec_id,
                        status="in_progress",
                        assigned_to_user_id=assignee_user,
                    )
                    print(f"    → asignado a {assignee_token_key} (user_id={assignee_user})")
                except Exception as exc:
                    print(f"    WARN assign: {exc}")

            # 3) Comentarios del equipo
            for who, text in COMMENTS:
                add_comment(
                    tokens[who],
                    project_id,
                    sec_id,
                    f"[Etapa {n} · {sec['title']}] {text}",
                )

            # 4) Completar apartado con revisión
            patch_section(
                owner_token,
                project_id,
                sec_id,
                status="completed",
                review_comment="Revision de direccion: apartado aprobado para avance.",
            )
            print("    OK apartado completado")

        # completar etapa / avanzar
        if n < 9:
            result = advance(owner_token, project_id)
            pct = result.get("progress_percent") or result.get("project", {}).get("progress_percent")
            # advance returns project payload wrapped?
            if "progress_percent" in result:
                print(f"  → avanzada. progreso={result['progress_percent']}%")
            elif "project" in result:
                print(f"  → avanzada. progreso={result['project'].get('progress_percent')}%")
            else:
                print(f"  → avanzada. keys={list(result.keys())[:8]}")
        else:
            # última etapa: advance marca proyecto completed
            result = advance(owner_token, project_id)
            print("  → etapa 9 / proyecto cerrado")

    final = get_project(owner_token, project_id)
    print("\n======== RESUMEN ========")
    print(f"Proyecto: {final['name']}")
    print(f"ID: {final['id']}")
    print(f"Status: {final['status']}")
    print(f"Etapa actual: {final['current_stage']}")
    print(f"Progreso: {final.get('progress_percent')}%")
    print(f"Ubicación: {final.get('location')} ({final.get('latitude')}, {final.get('longitude')})")
    print(f"Miembros: {len(final.get('members') or [])}")
    print(f"Archivos: {len(final.get('files') or [])}")
    completed = sum(1 for s in final.get("stages") or [] if s.get("status") == "completed")
    print(f"Etapas completadas: {completed}/9")
    print(f"Abrir: http://localhost:8000/legacy-app?home-projects=1&project={final['id']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
