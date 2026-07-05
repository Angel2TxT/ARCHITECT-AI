# Correo con Brevo (tickets, recuperación de contraseña)

ARCHITECT envía comprobantes PDF y enlaces de recuperación vía **SMTP de Brevo**.

## 1. Obtener credenciales en Brevo

1. Entra a [https://app.brevo.com](https://app.brevo.com)
2. **Settings → SMTP & API → SMTP**
3. Anota:
   - **SMTP server**: `smtp-relay.brevo.com`
   - **Port**: `587`
   - **Login**: tu correo de cuenta Brevo (ej. `tu@gmail.com`)
   - **SMTP key**: genera una clave SMTP (no uses la API key v3)
4. **Senders & IP → Senders**: verifica el correo remitente que usarás en `MAIL_FROM_ADDRESS`

## 2. Configurar `.env` (raíz del proyecto)

```env
APP_BASE_URL=http://localhost:8000

MAIL_MAILER=smtp
MAIL_HOST=smtp-relay.brevo.com
MAIL_PORT=587
MAIL_USERNAME=tu_correo_de_login_brevo@gmail.com
MAIL_PASSWORD=xsmtpsib-tu_clave_smtp_de_brevo
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@tudominio.com
MAIL_FROM_NAME=ARCHITECT
```

Importante:

- `MAIL_USERNAME` = login SMTP de Brevo (correo de la cuenta)
- `MAIL_PASSWORD` = **SMTP key**, no la API key REST
- `MAIL_FROM_ADDRESS` debe estar **verificado** en Brevo

## 3. Reiniciar backend

```powershell
docker compose restart backend
```

## 4. Probar envío

```powershell
c:\UNI\ARCHITECT\.venv\Scripts\python.exe scripts\test_mail.py tu_correo@gmail.com
```

Debe responder `Correo enviado correctamente`.

También puedes revisar `/api/health` → `"mail": { "configured": true, ... }`.

## 5. Probar ticket de compra

1. Inicia sesión en `:8000`
2. Compra un plan demo en checkout
3. Debes ver **«Te enviamos el comprobante a tu correo»** y recibir el PDF adjunto

Si falla, reenvía desde **Mi cuenta → Mis comprobantes → Reenviar**.

## Errores frecuentes

| Síntoma | Causa |
|---------|--------|
| `Correo no configurado` | Falta algún `MAIL_*` en `.env` |
| `Authentication failed` | SMTP key incorrecta o usaste API key en vez de SMTP key |
| `Sender not valid` | `MAIL_FROM_ADDRESS` no verificado en Brevo |
| No llega el correo | Revisa spam; en Brevo → Transactional → Email logs |
