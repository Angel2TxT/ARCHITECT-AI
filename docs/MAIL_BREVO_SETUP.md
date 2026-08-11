# Correo con Brevo (tickets, recuperación de contraseña)

ARCHITECT puede enviar correos de dos formas:

1. **API HTTP de Brevo (recomendado)** — no te pide autorizar cada IP nueva
2. **SMTP** — funciona, pero Brevo bloquea IPs nuevas (típico con Wi‑Fi / Cloudflare Tunnel)

## Por qué te llega “Verificar una nueva IP”

Con SMTP, Brevo exige autorizar la IP pública desde la que sale el correo. Si tu IP cambia (casa, móvil, tunnel), el envío falla hasta que autorices.

**Arreglo inmediato (SMTP):** en el correo de Brevo pulsa:

- **Sí, autorizar la nueva dirección IP** (esta vez), o
- **Detener la revisión de las direcciones IP** (para que no vuelva a pasar)

**Arreglo permanente (recomendado):** usa la **API key** (abajo).

## 1. Configuración recomendada — API Brevo

1. Entra a [https://app.brevo.com](https://app.brevo.com)
2. **Settings → SMTP & API → API keys → Generate a new API key**
3. **Senders & IP → Senders**: verifica el correo de `MAIL_FROM_ADDRESS`
4. En `.env`:

```env
APP_BASE_URL=http://localhost:8000

MAIL_MAILER=brevo
BREVO_API_KEY=xkeysib-tu_api_key_aqui
MAIL_FROM_ADDRESS=tu_remitente_verificado@gmail.com
MAIL_FROM_NAME=ARCHITECT

# SMTP opcional (fallback si MAIL_MAILER=smtp)
MAIL_HOST=smtp-relay.brevo.com
MAIL_PORT=587
MAIL_USERNAME=tu_login@smtp-brevo.com
MAIL_PASSWORD=xsmtpsib-tu_clave_smtp
MAIL_ENCRYPTION=tls
```

Importante:

- `BREVO_API_KEY` = **API key** (`xkeysib-...`), no la SMTP key
- `MAIL_FROM_ADDRESS` debe estar **verificado** en Brevo
- Con `MAIL_MAILER=brevo` ya no hace falta autorizar IPs del SMTP

## 2. Alternativa — solo SMTP

```env
MAIL_MAILER=smtp
MAIL_HOST=smtp-relay.brevo.com
MAIL_PORT=587
MAIL_USERNAME=tu_login_smtp@smtp-brevo.com
MAIL_PASSWORD=xsmtpsib-tu_clave_smtp
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@tudominio.com
MAIL_FROM_NAME=ARCHITECT
```

Si usas SMTP y te bloquean por IP: autoriza la IP o desactiva la revisión de IPs en Brevo.

## 3. Reiniciar backend

```powershell
docker compose restart backend
```

Si corres uvicorn local, reinicia el proceso para recargar `.env`.

## 4. Probar envío

```powershell
c:\UNI\ARCHITECT\.venv\Scripts\python.exe scripts\test_mail.py tu_correo@gmail.com
```

Debe responder `Correo enviado correctamente` y mostrar `mailer: brevo` (o `smtp`).

También: `/api/health` → `"mail": { "configured": true, "mailer": "brevo", ... }`.

## 5. Probar ticket de compra

1. Inicia sesión
2. Compra un plan demo en checkout
3. Debes ver el aviso de comprobante y recibir el PDF

Si falla, reenvía desde **Mi cuenta → Mis comprobantes → Reenviar**.

## Errores frecuentes

| Síntoma | Causa |
|---------|--------|
| `Correo no configurado` / falta `BREVO_API_KEY` | Pon la API key y `MAIL_MAILER=brevo` |
| Correo de “Verificar una nueva IP” | Estás en SMTP; pasa a API o autoriza/desactiva revisión de IP |
| `Authentication failed` / 401 | API key incorrecta o usaste SMTP key como API key |
| `Sender not valid` | `MAIL_FROM_ADDRESS` no verificado en Brevo |
| No llega el correo | Revisa spam; en Brevo → Transactional → Logs |
