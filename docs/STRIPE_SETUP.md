# Stripe (opcional — NO usar en proyecto escolar)

> **Proyecto final escolar:** usa `BILLING_MODE=demo` y la guía [BILLING_DEMO.md](BILLING_DEMO.md).  
> Este documento solo aplica si más adelante quieres cobros reales en producción.

Guía para cobrar con **Stripe Checkout** en entorno de pruebas (`sk_test_` / `pk_test_`).

## 1. Cuenta y claves

1. Crea o abre una cuenta en [Stripe Dashboard](https://dashboard.stripe.com).
2. Activa **modo test** (interruptor “Test mode”).
3. Ve a **Developers → API keys** y copia:
   - **Secret key** → `STRIPE_SECRET_KEY=sk_test_...`
   - **Publishable key** → `STRIPE_PUBLISHABLE_KEY=pk_test_...`

## 2. Variables en `.env`

```env
APP_BASE_URL=http://localhost:3000
BILLING_MODE=stripe
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_CURRENCY=mxn
```

`APP_BASE_URL` debe ser la URL que usa el navegador (con Docker suele ser `http://localhost:3000`).

## 3. Sincronizar planes con Stripe

Crea productos y precios mensuales en Stripe y guarda los `price_id` en la base de datos:

```powershell
cd C:\UNI\ARCHITECT
.\.venv\Scripts\python.exe scripts\sync_stripe_plans.py
```

O dentro del contenedor backend:

```bash
docker compose exec backend python scripts/sync_stripe_plans.py
```

Cada plan de pago quedará con `features.stripe_price_id` en MySQL.

## 4. Webhooks (recomendado en local)

Stripe confirma pagos y cancelaciones vía webhook.

### Stripe CLI

```bash
stripe login
stripe listen --forward-to localhost:8000/api/billing/webhook/stripe
```

Copia el **webhook signing secret** (`whsec_...`) a `.env`:

```env
STRIPE_WEBHOOK_SECRET=whsec_...
```

Reinicia el backend después de cambiar `.env`.

> Si usas solo Docker y el backend está en el puerto 8000 del host, el forward anterior funciona. Si el CLI corre en otra máquina, ajusta la URL.

### Eventos que procesa ARCHITECT

| Evento | Acción |
|--------|--------|
| `checkout.session.completed` | Activa el plan en MySQL |
| `customer.subscription.deleted` | Baja a plan Gratis |
| `customer.subscription.updated` | Sincroniza estado (`active`, `past_due`, etc.) |
| `invoice.payment_failed` | Marca suscripción `past_due` |

También puedes confirmar el pago al volver de Checkout en `/checkout/success` (doble vía segura).

## 5. Portal del cliente (opcional)

En Stripe Dashboard → **Settings → Billing → Customer portal**, activa:

- Cancelar suscripción
- Actualizar método de pago

En la app, usuarios con suscripción Stripe real pueden usar **Gestionar suscripción** (API `POST /api/billing/portal`).

## 6. Probar un pago

1. `docker compose up --build` (o backend local con `.env` configurado).
2. Inicia sesión con un usuario en plan **Gratis**.
3. Elige **Starter**, **Pro** o **Enterprise**.
4. Serás redirigido a **Stripe Checkout** (no a la pasarela demo).
5. Tarjeta de prueba: `4242 4242 4242 4242`, cualquier CVC y fecha futura.
6. Al completar, vuelves a `/checkout/success` y el workspace muestra el plan activo.

## 7. Modo demo vs Stripe

| `BILLING_MODE` | `STRIPE_SECRET_KEY` | Comportamiento |
|----------------|---------------------|----------------|
| `demo` | (vacío) | Pasarela simulada en `/checkout` |
| `stripe` | `sk_test_...` | Stripe Checkout real |
| `stripe` | (vacío) | Cae a demo automáticamente |

## 8. Producción

- Cambia a claves **live** (`sk_live_`, `pk_live_`).
- Configura webhook en Dashboard apuntando a `https://tu-dominio/api/billing/webhook/stripe`.
- Usa `APP_BASE_URL=https://tu-dominio`.
- Ejecuta de nuevo `sync_stripe_plans.py` en live (o crea precios manualmente).

## Referencia rápida

```text
POST /api/billing/checkout        → inicia checkout (demo o Stripe)
GET  /api/billing/config          → modo actual + publishable key
POST /api/billing/webhook/stripe  → webhooks Stripe
POST /api/billing/portal          → portal de gestión
```
