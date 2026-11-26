import { test, expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const PYTHON_EXE = path.join(REPO_ROOT, ".venv", "Scripts", "python.exe");
const ARTIFACT_SCREENSHOTS_DIR = path.join(REPO_ROOT, "qa_reports", "web_verification");

function runDbHelper(action, email, extra = "") {
  const script = `
import sys
from datetime import datetime, timedelta
from sqlalchemy import text
sys.path.insert(0, r"${path.join(REPO_ROOT, "backend")}")
from db.database import SessionLocal
from db.models import EmailVerificationCode, Subscription, User
from services.email_verification_service import _hash_code

action, email, extra = sys.argv[1], sys.argv[2].strip().lower(), sys.argv[3]
with SessionLocal() as db:
    user = db.query(User).filter(User.email == email).first()
    if action == "cleanup":
        if user is not None:
            db.query(EmailVerificationCode).filter(EmailVerificationCode.user_id == user.id).delete()
            db.query(Subscription).filter(Subscription.user_id == user.id).delete()
            db.query(User).filter(User.id == user.id).delete()
            db.commit()
        sys.exit(0)
    assert user is not None, f"User not found: {email}"
    row = (
        db.query(EmailVerificationCode)
        .filter(EmailVerificationCode.user_id == user.id, EmailVerificationCode.consumed_at.is_(None))
        .order_by(EmailVerificationCode.id.desc())
        .first()
    )
    if action == "set_code":
        assert row is not None, "No active verification code row"
        row.code_hash = _hash_code(user.id, extra)
        db.commit()
    elif action == "expire":
        assert row is not None
        row.expires_at = datetime.utcnow() - timedelta(minutes=2)
        db.commit()
    elif action == "age_cooldown":
        assert row is not None
        row.created_at = datetime.utcnow() - timedelta(seconds=65)
        db.commit()
    elif action == "is_verified":
        print("1" if user.email_verified else "0")
    elif action == "mark_verified":
        user.email_verified = True
        db.commit()
    elif action == "cleanup":
        db.query(EmailVerificationCode).filter(EmailVerificationCode.user_id == user.id).delete()
        db.query(Subscription).filter(Subscription.user_id == user.id).delete()
        db.query(User).filter(User.id == user.id).delete()
        db.commit()
`;
  return execFileSync(PYTHON_EXE, ["-c", script, action, email, extra], {
    cwd: REPO_ROOT,
    encoding: "utf-8",
  }).trim();
}

async function fillOtpBoxes(page, code) {
  for (let i = 0; i < 6; i++) {
    await page.getByTestId(`otp-input-${i}`).fill(code[i]);
  }
}

test.describe("Web Email Verification (6-digit code)", () => {
  const createdEmails = [];

  test.afterAll(() => {
    for (const email of createdEmails) {
      try {
        runDbHelper("cleanup", email);
      } catch {
        // ignore cleanup errors
      }
    }
  });

  test("flujo completo: registro, validaciones, reenvío, cambio de correo, recarga, verificación y sincronización", async ({
    page,
  }) => {
    const ts = Date.now();
    const initialEmail = `web.verif.${ts}@gmail.com`;
    const correctedEmail = `web.fixed.${ts}@gmail.com`;
    const password = "Password123!";
    createdEmails.push(initialEmail, correctedEmail);

    // 1. Registro tradicional desde la web
    await page.goto("/login#register");
    await expect(page.getByRole("heading", { name: "Crear cuenta" })).toBeVisible();
    await page.locator('input[name="full_name"]').fill("Usuario Web Prueba");
    await page.locator('input[name="email"]').fill(initialEmail);
    await page.locator('input[name="password"]').fill(password);
    await page.locator('button.auth-submit').click();

    // 2. Redirección a pantalla de verificación y UI completa
    await expect(page).toHaveURL(/\/verify-email$/);
    await expect(page.getByRole("heading", { name: "Verifica tu correo electrónico" })).toBeVisible();
    await expect(page.getByTestId("verify-email-label")).toHaveText(initialEmail);
    await expect(page.getByTestId("verify-resend-btn")).toBeDisabled();
    await expect(page.getByTestId("verify-attempts-label")).toContainText("5");

    await page.screenshot({
      path: path.join(ARTIFACT_SCREENSHOTS_DIR, "01_verify_desktop.png"),
      fullPage: true,
    });

    // Diseño responsivo en móvil (390x844)
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(page.getByTestId("otp-input-5")).toBeVisible();
    const box5 = await page.getByTestId("otp-input-5").boundingBox();
    expect(box5.x + box5.width).toBeLessThanOrEqual(390);
    await page.screenshot({
      path: path.join(ARTIFACT_SCREENSHOTS_DIR, "02_verify_mobile.png"),
      fullPage: true,
    });
    await page.setViewportSize({ width: 1280, height: 800 });

    // 3. Pegado completo y auto-avance + código incorrecto + límite de 5 intentos
    runDbHelper("set_code", initialEmail, "246810");
    await page.getByTestId("otp-input-0").focus();
    await page.getByTestId("otp-input-0").fill("999999");
    await expect(page.getByTestId("otp-input-5")).toHaveValue("9");

    for (let attempt = 1; attempt <= 5; attempt++) {
      await fillOtpBoxes(page, "111111");
      await page.getByTestId("verify-submit-btn").click();
      await expect(page.getByTestId("verify-error")).toBeVisible();
    }
    await expect(page.getByTestId("verify-error")).toContainText("5 intentos");

    // 4. Reenvío de código (tras agotar 5 intentos el código previo queda consumido) e invalidación
    await page.reload();
    await expect(page).toHaveURL(/\/verify-email$/);
    await expect(page.getByTestId("verify-resend-btn")).toBeEnabled();
    await page.getByTestId("verify-resend-btn").click();
    await expect(page.getByTestId("verify-success")).toBeVisible();

    // 5. Cambio de correo electrónico
    await page.getByTestId("verify-change-email-toggle").click();
    await page.getByTestId("verify-new-email-input").fill(correctedEmail);
    await page.getByTestId("verify-change-password-input").fill(password);
    await page.getByTestId("verify-save-email-btn").click();
    await expect(page.getByTestId("verify-email-label")).toHaveText(correctedEmail);
    await expect(page.getByTestId("verify-success")).toContainText(correctedEmail);

    // 6. Código expirado
    runDbHelper("set_code", correctedEmail, "654321");
    runDbHelper("expire", correctedEmail);
    await fillOtpBoxes(page, "654321");
    await page.getByTestId("verify-submit-btn").click();
    await expect(page.getByTestId("verify-error")).toContainText("expirado");

    // 7. Reenvío válido -> actualización de página -> verificación exitosa (el código expirado ya fue consumido)
    await page.reload();
    await expect(page.getByTestId("verify-email-label")).toHaveText(correctedEmail);
    await expect(page.getByTestId("verify-resend-btn")).toBeEnabled();
    await page.getByTestId("verify-resend-btn").click();
    await expect(page.getByTestId("verify-success")).toBeVisible();

    runDbHelper("set_code", correctedEmail, "314159");
    await fillOtpBoxes(page, "314159");
    await page.getByTestId("verify-submit-btn").click();

    await page.waitForURL(/\/legacy-app/, { timeout: 20000 });
    expect(runDbHelper("is_verified", correctedEmail)).toBe("1");

    // 8. Reutilización del mismo código debe fallar en backend
    const reuseRes = await page.request.post("/api/auth/verify-email", {
      data: { email: correctedEmail, code: "314159" },
    });
    expect(reuseRes.status()).toBe(400);

    // 9. Sincronización web <-> móvil: el mismo usuario ya puede iniciar sesión sin verificar
    const mobileLoginRes = await page.request.post("/api/auth/login", {
      data: { email: correctedEmail, password },
    });
    expect(mobileLoginRes.status()).toBe(200);
  });

  test("cuenta no verificada en login, acceso directo a ruta protegida y cuenta existente", async ({
    page,
  }) => {
    const ts = Date.now();
    const email = `web.unverified.${ts}@gmail.com`;
    const existingEmail = `web.existing.${ts}@gmail.com`;
    const password = "Password123!";
    createdEmails.push(email, existingEmail);

    // Registrar cuenta sin verificar y otra cuenta ya verificada (existente)
    const regRes = await page.request.post("/api/auth/register", {
      data: { full_name: "No Verificado", email, password },
    });
    expect(regRes.status()).toBe(200);

    const regExisting = await page.request.post("/api/auth/register", {
      data: { full_name: "Cuenta Existente", email: existingEmail, password },
    });
    expect(regExisting.status()).toBe(200);
    runDbHelper("mark_verified", existingEmail);

    // Acceso directo a ruta protegida /app sin sesión -> redirige a /login
    await page.goto("/app");
    await expect(page).toHaveURL(/\/login$/);

    // Intentar login con cuenta no verificada -> redirige a /verify-email
    await page.locator('input[name="email"]').fill(email);
    await page.locator('input[name="password"]').fill(password);
    await page.locator('button.auth-submit').click();
    await expect(page).toHaveURL(/\/verify-email$/);
    await expect(page.getByTestId("verify-email-label")).toHaveText(email);

    // Volver al login y probar cuenta existente ya verificada
    await page.getByRole("button", { name: "Volver a iniciar sesión" }).click();
    await expect(page).toHaveURL(/\/login$/);
    await page.locator('input[name="email"]').fill(existingEmail);
    await page.locator('input[name="password"]').fill(password);
    await page.locator('button.auth-submit').click();
    await page.waitForURL(/\/legacy-app/, { timeout: 20000 });
  });
});
