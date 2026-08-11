from sqlalchemy import func
from sqlalchemy.orm import Session

from fastapi import HTTPException

from db.models import User, UserRole
from services.auth_service import hash_password, verify_password
from services.avatar_service import delete_user_avatar


def update_profile(db: Session, user: User, *, full_name: str) -> User:
    name = (full_name or "").strip()
    if not name:
        raise HTTPException(400, "El nombre no puede quedar vacío")
    if len(name) > 120:
        raise HTTPException(400, "El nombre es demasiado largo")
    user.full_name = name
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def change_password(
    db: Session,
    user: User,
    *,
    current_password: str | None,
    new_password: str,
) -> User:
    new_password = (new_password or "").strip()
    if len(new_password) < 8:
        raise HTTPException(400, "La contraseña nueva debe tener al menos 8 caracteres")
    if len(new_password) > 128:
        raise HTTPException(400, "La contraseña nueva es demasiado larga")

    if user.password_hash:
        if not current_password:
            raise HTTPException(400, "Indica tu contraseña actual")
        if not verify_password(current_password, user.password_hash):
            raise HTTPException(400, "La contraseña actual no es correcta")
    # Cuentas Google sin password: permiten definir una por primera vez

    user.password_hash = hash_password(new_password)
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def delete_own_account(
    db: Session,
    user: User,
    *,
    password: str | None = None,
    confirm_email: str | None = None,
) -> None:
    if user.role == UserRole.admin:
        admins = (
            db.query(func.count(User.id))
            .filter(User.role == UserRole.admin, User.is_active.is_(True))
            .scalar()
            or 0
        )
        if admins <= 1:
            raise HTTPException(
                400,
                "No puedes eliminar la única cuenta de administrador. "
                "Crea otro admin antes.",
            )

    if user.password_hash:
        if not password or not verify_password(password, user.password_hash):
            raise HTTPException(400, "Contraseña incorrecta")
    else:
        expected = (user.email or "").strip().lower()
        got = (confirm_email or "").strip().lower()
        if got != expected:
            raise HTTPException(
                400,
                "Escribe tu correo exacto para confirmar la eliminación",
            )

    uid = user.id
    try:
        delete_user_avatar(uid)
    except Exception:
        pass
    db.delete(user)
    db.commit()
