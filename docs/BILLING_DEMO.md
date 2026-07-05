# Planes y pasarela de pago simulada (proyecto escolar)

ARCHITECT usa **modo demo** para suscripciones: no hay Stripe, no hay cobros reales y no necesitas cuenta de pagos para la entrega académica.

## Cómo funciona

1. Todo usuario nuevo empieza en plan **Gratis** (5 análisis/mes, modelo demo).
2. Si elige **Starter**, **Pro** o **Enterprise**, la app abre `/checkout` — una **pasarela simulada** con formulario de tarjeta ficticio.
3. Al confirmar, el backend activa el plan en MySQL y aplican los **límites reales** del plan (análisis/mes, tamaño de archivo, modelo demo vs entrenado).
4. **Bajar a Gratis** desde el modal de planes es inmediato (sin pasarela).
5. Tras un pago simulado exitoso se genera un **comprobante PDF** (folio `AR-YYYYMM-#####`), se puede **descargar** y, si `MAIL_*` está configurado, se **envía por correo** con el PDF adjunto.
6. En **Mi cuenta** aparece el **historial de compras** con descarga, reenvío de correo y **exportación ZIP** de todos los PDF.
7. **Gráfica de uso mensual** (últimos 6 meses) en Mi cuenta.
8. **Badge de plan/uso** visible en el workspace (`Plan Pro · 12/50`).
9. Si falla el envío de correo, aparece un **aviso persistente** con botón para descargar el PDF.
10. Panel **Administración → Comprobantes**: ventas simuladas por plan y listado global.

## Configuración (`.env`)

```env
BILLING_MODE=demo
# Correos/OAuth — mismo puerto donde entras (p. ej. 8000 con backend directo)
APP_BASE_URL=http://localhost:8000

# Opcional: envío de comprobantes por correo (Brevo — ver docs/MAIL_BREVO_SETUP.md)
MAIL_HOST=smtp-relay.brevo.com
MAIL_PORT=587
MAIL_USERNAME=tu_login_brevo@gmail.com
MAIL_PASSWORD=xsmtpsib-tu_clave_smtp
MAIL_FROM_ADDRESS=noreply@tudominio.com
MAIL_FROM_NAME=ARCHITECT
MAIL_ENCRYPTION=tls
```
Con Docker: `docker compose up` y listo. No configures `STRIPE_*`.

El checkout demo usa la ruta relativa `/checkout?token=...`, así que **permaneces en el puerto actual** (8000 o 3000) al pagar o cancelar.

## Qué decir en la exposición / documento

- “Implementamos un flujo de suscripción con pasarela de pago **simulada** para demostrar el recorrido completo (selección de plan → checkout → activación → límites de uso).”
- “Los límites por plan **sí se aplican en el backend** al analizar planos (`assert_can_analyze`).”
- “No integramos un procesador de pagos real porque el alcance es académico.”

## Endpoints relevantes

| Endpoint | Uso |
|----------|-----|
| `GET /api/billing/config` | Modo `demo` |
| `POST /api/billing/checkout` | Inicia pasarela simulada |
| `POST /api/billing/checkout/complete` | Confirma pago demo y emite comprobante |
| `GET /api/billing/receipts` | Historial de comprobantes del usuario |
| `GET /api/billing/receipts/{id}/pdf` | Descarga PDF (requiere sesión) |
| `POST /api/billing/receipts/{id}/email` | Reenvía comprobante al correo |
| `GET /api/billing/usage-history` | Gráfica de uso mensual |
| `GET /api/billing/receipts/export/zip` | ZIP con todos los PDF |
| `POST /api/billing/change-plan` | Solo bajar a **free** |
| `GET /api/admin/billing/receipts` | Admin: listado de comprobantes |
| `GET /api/admin/billing/summary` | Admin: ventas simuladas por plan |

## Validar que todo funciona

```powershell
C:\UNI\ARCHITECT\.venv\Scripts\python.exe scripts\validate_billing_e2e.py
```

Debe terminar con `TODAS LAS PRUEBAS PASARON`.

## Stripe (opcional, no usar en proyecto escolar)

Si en el futuro quisieras cobros reales, existe código preparado. Ver `docs/STRIPE_SETUP.md` — **no es necesario para la entrega académica**.
