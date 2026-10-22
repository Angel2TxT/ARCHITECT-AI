"""Script para simular un proyecto completo en Casa Hogar con colaboradores, archivos, comentarios y presupuesto."""

import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Setup paths
sys.path.insert(0, "/app")
sys.path.insert(0, "/app/backend")

from db.database import SessionLocal
from db.models import (
    User,
    UserRole,
    HomeProject,
    HomeProjectStatus,
    HomeProjectStage,
    HomeProjectSection,
    HomeProjectSectionStatus,
    HomeProjectSectionComment,
    HomeProjectMember,
    HomeProjectMemberRole,
    HomeProjectDocument,
    HomeProjectEvent,
    HomeProjectEventType,
)
from services.auth_service import hash_password

def main():
    db = SessionLocal()
    try:
        project_id = "96513baa-ca57-4316-88ce-3192492bf343"
        project = db.query(HomeProject).filter(HomeProject.id == project_id).first()
        if not project:
            print(f"Error: No se encontró proyecto con id {project_id}")
            return 1

        print(f"Encontrado proyecto: {project.name} (ID: {project.id})")

        # 1. Asegurar usuarios colaboradores
        collabs = [
            ("arq.morales@architect.local", "Arq. Ana Morales", HomeProjectMemberRole.editor),
            ("ing.ruiz@architect.local", "Ing. Carlos Ruiz", HomeProjectMemberRole.editor),
            ("residente.vega@architect.local", "Arq. Roberto Vega", HomeProjectMemberRole.viewer),
        ]
        collab_users = []
        for email, name, role in collabs:
            u = db.query(User).filter(User.email == email).first()
            if not u:
                u = User(
                    email=email,
                    password_hash=hash_password("Colaborador123!"),
                    full_name=name,
                    role=UserRole.user,
                )
                db.add(u)
                db.flush()
                print(f"Creado usuario: {email}")
            collab_users.append((u, role))

        # 2. Actualizar datos principales del proyecto
        project.name = "Residencia Bosques — Simulación Completa (100%)"
        project.client_name = "Familia Morales López"
        project.location = "Ocosingo, Chiapas"
        project.latitude = 16.9072
        project.longitude = -92.0942
        project.description = (
            "Proyecto integral de autoconstrucción de 180 m² con las 9 etapas ejecutadas al 100%. "
            "Incluye expediente de planos técnicos, cálculo estructural, instalaciones, bitácora de obra y presupuesto final auditado."
        )
        project.status = HomeProjectStatus.completed
        project.current_stage = 9

        # 3. Metadatos de presupuesto
        project.metadata_json = {
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

        # 4. Asignar colaboradores al proyecto
        # Limpiar miembros existentes
        db.query(HomeProjectMember).filter(HomeProjectMember.project_id == project_id).delete()
        for u, role in collab_users:
            member = HomeProjectMember(
                project_id=project_id,
                user_id=u.id,
                role=role,
                joined_at=datetime.utcnow() - timedelta(days=60),
            )
            db.add(member)
        print("Colaboradores vinculados.")

        # 5. Completar todas las 9 etapas
        stages = db.query(HomeProjectStage).filter(HomeProjectStage.project_id == project_id).all()
        stage_notes = {
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
        for st in stages:
            st.status = "completed"
            st.notes = stage_notes.get(st.stage_number, "Etapa completada.")
            st.started_at = datetime.utcnow() - timedelta(days=90 - (st.stage_number * 8))
            st.completed_at = datetime.utcnow() - timedelta(days=90 - (st.stage_number * 9))

        # 6. Completar todos los apartados (sections)
        sections = db.query(HomeProjectSection).filter(HomeProjectSection.project_id == project_id).all()
        for sec in sections:
            sec.status = HomeProjectSectionStatus.completed

        # 7. Agregar documentos simulados en almacenamiento
        storage_base = Path("/app/data/home_projects") / project_id
        storage_base.mkdir(parents=True, exist_ok=True)

        # Limpiar documentos anteriores para evitar duplicados
        db.query(HomeProjectDocument).filter(HomeProjectDocument.project_id == project_id).delete()

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

        sec_by_stage = {}
        for s in sections:
            sec_by_stage.setdefault(s.stage_number, []).append(s)

        for stage_num, fname, mime, size in doc_templates:
            sec_list = sec_by_stage.get(stage_num, [])
            sec_id = sec_list[0].id if sec_list else None
            slot_key = sec_list[0].slots_json[0].get("key") if sec_list and sec_list[0].slots_json else None

            # Crear archivo físico placeholder si no existe
            disk_path = storage_base / fname
            if not disk_path.exists():
                disk_path.write_bytes(f"%PDF-1.4 mock file content for {fname}".encode("utf-8"))

            doc = HomeProjectDocument(
                project_id=project_id,
                user_id=project.user_id,
                stage_number=stage_num,
                section_id=sec_id,
                slot_key=slot_key,
                original_filename=fname,
                stored_path=str(disk_path),
                mime_type=mime,
                file_size=size,
                created_at=datetime.utcnow() - timedelta(days=90 - (stage_num * 8)),
            )
            db.add(doc)

        print("Documentos registrados.")

        # 8. Agregar comentarios de colaboradores en los apartados
        db.query(HomeProjectSectionComment).filter(
            HomeProjectSectionComment.section_id.in_([s.id for s in sections])
        ).delete(synchronize_session=False)

        comments_data = [
            (1, collab_users[0][0].id, "Brief validado con la familia: se aprueba la zonificación con patio central y recámara principal en planta baja."),
            (2, collab_users[1][0].id, "Estudio topográfico y mecánica de suelos concluidos: capacidad de carga óptima de 1.8 kg/cm²."),
            (4, collab_users[0][0].id, "Anteproyecto aprobado por el cliente sin observaciones. Pasamos al desarrollo del proyecto ejecutivo."),
            (6, collab_users[1][0].id, "Cálculo estructural revisado conforme al código sísmico de Chiapas: zapatas aisladas y trabes de liga listas."),
            (7, collab_users[0][0].id, "Catálogo de conceptos y presupuesto de $1.85 MDP cerrado favorablemente con contratistas."),
            (8, collab_users[2][0].id, "Supervisión diaria en bitácora: colado de losas e instalaciones hidrosanitarias concluidas con éxito."),
            (9, project.user_id, "Acta de entrega formal y recepción técnica firmada. Expediente cerrado al 100%."),
        ]

        for stage_num, user_id_comment, body in comments_data:
            sec_list = sec_by_stage.get(stage_num, [])
            if sec_list:
                c = HomeProjectSectionComment(
                    section_id=sec_list[0].id,
                    user_id=user_id_comment,
                    body=body,
                    created_at=datetime.utcnow() - timedelta(days=90 - (stage_num * 7)),
                )
                db.add(c)

        print("Comentarios técnicos creados.")

        # 9. Crear eventos en la línea de tiempo (historial)
        db.query(HomeProjectEvent).filter(HomeProjectEvent.project_id == project_id).delete()
        events = [
            (HomeProjectEventType.stage_completed, "Etapa 1 inicializada y validada.", 90),
            (HomeProjectEventType.member_invited, "Arq. Ana Morales se unió como Editora.", 85),
            (HomeProjectEventType.member_invited, "Ing. Carlos Ruiz se unió como Editor.", 80),
            (HomeProjectEventType.document_uploaded, "Se subieron los planos ejecutivos de la Etapa 5.", 45),
            (HomeProjectEventType.stage_advanced, "Etapa 6 completada con aprobación estructural.", 35),
            (HomeProjectEventType.stage_advanced, "Presupuesto y contratos cerrados en Etapa 7.", 25),
            (HomeProjectEventType.stage_advanced, "Construcción física finalizada al 100% en Etapa 8.", 10),
            (HomeProjectEventType.stage_advanced, "Expediente de obra concluido al 100% y entregado.", 1),
        ]
        for evt_type, desc, days_ago in events:
            ev = HomeProjectEvent(
                project_id=project_id,
                actor_user_id=project.user_id,
                event_type=evt_type,
                metadata_json={"description": desc},
                created_at=datetime.utcnow() - timedelta(days=days_ago),
            )
            db.add(ev)

        db.commit()
        print("\n¡Simulación completa aplicada con éxito en proyecto 96513baa-ca57-4316-88ce-3192492bf343!")
        return 0

    except Exception as e:
        db.rollback()
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        db.close()

if __name__ == "__main__":
    sys.exit(main())
