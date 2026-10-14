# Elíptica · Registro de Producción (v1.0)

App para registrar por obra: procesos, ensamblador, ensamble terminado, despacho e instalación.
Funciona en iPhone, iPad y Mac. Los datos se guardan en Supabase al instante.

## 1. Publicarla en GitHub (igual que el dashboard, pero en un repositorio NUEVO)

1. Entra a github.com → botón verde **New** (nuevo repositorio).
2. Nombre: `registro-produccion` · marca **Public** · **Create repository**.
3. Toca **uploading an existing file** y arrastra TODO el contenido de esta carpeta
   (index.html, sw.js, manifest.json y las carpetas `icons` y `lib`). → **Commit changes**.
4. **Settings → Pages** → Branch: **main** / carpeta **/(root)** → **Save**.
5. En 1–2 minutos queda en: `https://TU_USUARIO.github.io/registro-produccion/`

Importante: no la subas dentro del repositorio del dashboard; debe ir en uno aparte.

## 2. Cerrar el registro de usuarios nuevos en Supabase (seguridad)

Supabase → **Authentication** → **Sign In / Providers** (o **Settings**) →
desactiva **Allow new users to sign up** → **Save**.
Así solo pueden entrar los usuarios que tú creas.

## 3. Instalar en iPhone / iPad

Safari → abre el enlace → botón **Compartir** → **Agregar a pantalla de inicio**.
Cada persona entra con el correo y la contraseña que le creaste en Supabase.

## Quién puede hacer qué

| | Gerente | Asistente |
|---|---|---|
| Procesos, ensamblador, despacho, instalación | Sí | Sí |
| Ver precios y cobros | Sí | No (la base de datos lo bloquea) |
| Modificar datos de la OP (medidas, ítem, obra) | Sí | No (la base de datos lo bloquea) |
| Exportar la base a Excel | Sí | No |
