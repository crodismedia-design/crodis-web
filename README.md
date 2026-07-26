# TallerMap

Directorio web de talleres de automoción. Permite buscar talleres activos y publicar gratuitamente una ficha sin aprobación previa. El panel privado se utiliza únicamente para revisar posteriormente y retirar registros incorrectos.

El buscador utiliza la población como criterio principal. Opcionalmente, el visitante puede autorizar la ubicación de su dispositivo para detectar su población y lanzar la búsqueda automáticamente; las coordenadas no se guardan en TallerMap.

## Estructura

- `index.html`: página principal y buscador.
- `pages/registro.html`: formulario público de nuevos registros.
- `pages/mi-taller.html`: acceso por correo y edición segura de fichas por sus propietarios.
- `pages/admin-login.html`: acceso privado de administración.
- `pages/admin.html`: revisión posterior y retirada de fichas publicadas.
- `pages/condiciones-fotografias.html`: condiciones adicionales para imágenes opcionales.
- `pages/privacidad.html`: información sobre el tratamiento de datos personales.
- `css/estilo.css`: estilos compartidos y adaptación móvil.
- `js/`: conexión con Supabase y lógica de la web.
- `js/servicios.js`: catálogo compartido por el buscador y el formulario de alta.
- `js/provincias.js`: provincias españolas y validación del prefijo postal.
- `supabase/solicitudes_alta_taller.sql`: tablas, funciones, permisos y políticas RLS.
- `supabase/estadisticas_publicas.sql`: contadores públicos calculados con datos reales.
- `supabase/formulario_web_provincias.sql`: web opcional y comprobación provincia/código postal.
- `supabase/alta_automatica_espana.sql`: activa la publicación automática y gratuita en toda España.
- `supabase/fotos_opcionales_taller.sql`: crea el almacenamiento privado y las políticas para un máximo de cinco fotografías.
- `supabase/horarios_obligatorios.sql`: añade el horario semanal obligatorio y lo publica en cada ficha.
- `supabase/formulario_seguro.sql`: exige correo verificado, limita altas abusivas, valida CIF/NIF y horarios, registra la aceptación de privacidad y corrige fotografías fallidas.
- `supabase/edicion_propietario_taller.sql`: relaciona cada ficha con su propietario verificado y permite actualizar de forma segura sus datos públicos, servicios y horarios.
- `supabase/admin_control_total.sql`: activa el control administrativo completo, el historial de cambios y el resumen exclusivo de talleres por provincia y población.

## Configuración de Supabase

1. Abre **Supabase > SQL Editor**.
2. Copia y ejecuta completo `supabase/solicitudes_alta_taller.sql`.
3. Crea el usuario administrador en **Authentication > Users**.
4. Añade su UUID a `public.administradores` con la instrucción indicada al final del archivo SQL.

Si la base de datos ya estaba configurada antes de añadir los contadores reales, ejecuta también `supabase/estadisticas_publicas.sql` una sola vez.

Para activar la publicación automática en una base de datos ya configurada, ejecuta una sola vez `supabase/alta_automatica_espana.sql`.

Para permitir fotografías opcionales, ejecuta una sola vez `supabase/fotos_opcionales_taller.sql`. Cada imagen puede ocupar hasta 5 MB y las solicitudes con fotos deben aceptar las condiciones adicionales. Las imágenes permanecen privadas mientras la solicitud no esté publicada.

Para exigir y mostrar el horario semanal, ejecuta una sola vez `supabase/horarios_obligatorios.sql`. Cada día admite un turno principal, un segundo turno opcional o la opción «Cerrado».

Después ejecuta una sola vez `supabase/formulario_seguro.sql`. Desde ese momento el propietario debe confirmar su correo mediante un enlace antes de publicar y podrá enviar como máximo tres altas cada 24 horas. Supabase Auth debe permitir el proveedor **Email**.

Para permitir que cada propietario vuelva a editar sus fichas, ejecuta una sola vez `supabase/edicion_propietario_taller.sql`. El acceso se realiza desde `pages/mi-taller.html` mediante un enlace enviado al mismo correo verificado utilizado durante el alta. El CIF, el correo, el estado y la verificación no pueden modificarse desde el editor.

Para activar el centro de control completo, ejecuta después una sola vez `supabase/admin_control_total.sql`. El administrador podrá crear fichas desde cero, editar todos sus campos, verificarlas, activarlas o desactivarlas, eliminarlas con confirmación, consultar el historial, buscar y filtrar, exportar CSV y ver los talleres exclusivamente agrupados por provincia y población.

El panel incluye también un buscador administrativo de candidatos basado en OpenStreetMap. Para activarlo, despliega `supabase/functions/buscar-talleres-internet/index.ts` como Edge Function con el nombre `buscar-talleres-internet`. Los resultados externos nunca se publican automáticamente: se comprueban posibles duplicados y el administrador debe pasarlos al editor, completar los datos obligatorios y revisar su exactitud.

Todas las altas de España se publican automáticamente como fichas activas no verificadas después de confirmar el correo. Una cuenta incluida en `public.administradores` puede revisar posteriormente los registros y retirar los que sean falsos, incorrectos o incumplan las condiciones.

El acceso administrativo y la verificación de propietarios utilizan enlaces seguros enviados por correo. Configura en Supabase **Authentication > URL Configuration** el sitio `https://tallermap.es` y permite la redirección `https://tallermap.es/**`.

## Despliegue

Vercel debe publicar la raíz del repositorio desde la rama `main`. No se necesita un comando de compilación porque la web utiliza HTML, CSS y JavaScript estáticos.
