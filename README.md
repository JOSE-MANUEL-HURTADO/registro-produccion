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

## Regla para SQL nuevos (cambio de Supabase del 30-oct-2026)
Desde el 30 de octubre de 2026, Supabase ya no da acceso automático por la API a las tablas NUEVAS de `public`.
Todo SQL que cree una tabla que la app lea o escriba debe incluir, en el mismo archivo:

```sql
grant select, insert, update, delete on public.<tabla> to authenticated;
```

Solo `authenticated` (nunca `anon`), y con RLS activo. Las tablas existentes no se ven afectadas.
Las tablas de solo registro (consultadas desde el SQL Editor) no necesitan grant.

## Si la app se pierde (recuperación)
La copia diaria del Mac (carpeta de respaldos en iCloud) trae todo lo necesario:
- `REINSTALAR_APP.sql`: un solo SQL, generado cada día desde la base real, que reconstruye la app completa en un proyecto de Supabase nuevo (tablas, funciones, triggers, RLS, permisos, carpeta de PDF, tiempo real, contadores).
- `COPIA_COMPLETA_*.zip`: los datos (un .json por tabla, en orden de restauración) y `_usuarios.json`.
- `PDF_OP/`: los PDF de las OP.
Pasos en el `LEEME.txt` del .zip. Datos: `restaurar_tabla(tabla, filas)` y al final `restaurar_secuencias()`.

## Avisos al celular (v6.82)
- `sql/50_notificaciones.sql`: cada acción (escaneos, programación, despachos, actas, firmas, precios, cobros, cargas) crea una notificación agrupada y la base llama a la Edge Function `notificar` (pg_net). La llave privada VAPID **no** está en el repo (`PEGAR_AQUI_LA_LLAVE_PRIVADA`); vive solo en la tabla `push_config` (sin políticas: solo la lee la función).
- `supabase/functions/notificar/index.ts`: envía el push a los celulares del gerente (tabla `push_subs`), menos al de quien hizo la acción; borra suscripciones vencidas.
- En la app: botón 🔔 (solo gerente). En iPhone/iPad requiere iOS 16.4+ y abrir la app desde el ícono de inicio.
