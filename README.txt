SELECTOR DE MUNICIPIOS PARA EL FORMULARIO DE TALLERMAP
======================================================

Este paquete contiene únicamente:

- js/municipios-formulario.js
- pages/registro.html

Qué hace:
- Lee los municipios activos desde la tabla public.municipios de Supabase.
- En códigos postales 03, 12 y 46 exige seleccionar una población válida.
- Corrige variantes como Alicante a Alacant/Alicante cuando corresponda.
- En el resto de España mantiene la validación existente por código postal.
- No modifica js/registro.js.

Cómo instalar:
1. Copia las carpetas js y pages dentro de la carpeta local crodis-web.
2. Acepta combinar carpetas.
3. Reemplaza pages/registro.html cuando Windows lo pregunte.
4. Vuelve a GitHub Desktop.
5. Haz commit y después Push origin.
