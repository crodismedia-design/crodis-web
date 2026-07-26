-- TallerMap: formularios sin propietario, CIF/NIF ni correo electrónico.
-- Ejecutar COMPLETO y como último paso en Supabase > SQL Editor.
-- Mantiene la publicación automática y deja la edición exclusivamente al administrador.

begin;

-- Los tres campos se conservan como columnas para no perder datos antiguos,
-- pero dejan de ser obligatorios y las nuevas altas públicas los guardan a NULL.
alter table public.solicitudes_alta_taller
    alter column propietario drop not null,
    alter column cif drop not null,
    alter column email drop not null;

alter table public.solicitudes_alta_taller
    drop constraint if exists solicitudes_alta_taller_propietario_check;
alter table public.solicitudes_alta_taller
    drop constraint if exists solicitudes_alta_taller_cif_check;
alter table public.solicitudes_alta_taller
    drop constraint if exists solicitudes_alta_taller_email_check;
alter table public.solicitudes_alta_taller
    drop constraint if exists solicitudes_documento_fiscal_valido;

-- Las nuevas altas no necesitan una cuenta de Supabase Auth.
-- Para reducir abusos se permiten como máximo tres altas por teléfono en 24 horas.
create or replace function public.preparar_estado_solicitud()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_telefono text := regexp_replace(coalesce(new.telefono, ''), '[^0-9+]', '', 'g');
begin
    if coalesce(auth.role(), '') in ('anon', 'authenticated')
       and (
            select count(*)
            from public.solicitudes_alta_taller s
            where regexp_replace(coalesce(s.telefono, ''), '[^0-9+]', '', 'g') = v_telefono
              and s.created_at > now() - interval '24 hours'
       ) >= 3 then
        raise exception 'limite_altas: demasiadas altas para este teléfono durante las últimas 24 horas'
            using errcode = 'P0001';
    end if;

    if new.localidad_verificada is not true then
        raise exception 'localidad_no_verificada: comprueba población y código postal'
            using errcode = '23514';
    end if;
    if new.acepta_privacidad is not true
       or new.acepta_privacidad_at is null
       or nullif(btrim(new.version_privacidad), '') is null then
        raise exception 'privacidad_no_aceptada'
            using errcode = '23514';
    end if;
    if new.acepta_responsabilidad is not true
       or new.acepta_terminos_at is null
       or nullif(btrim(new.version_terminos), '') is null then
        raise exception 'condiciones_no_aceptadas'
            using errcode = '23514';
    end if;
    if not public.horario_semanal_es_valido(new.horarios) then
        raise exception 'horarios_no_validos'
            using errcode = '23514';
    end if;

    new.propietario := null;
    new.cif := null;
    new.email := null;
    new.usuario_id := null;
    new.estado := 'aprobada';
    new.revisada_at := now();
    new.revisada_por := null;
    return new;
end;
$$;

drop policy if exists "usuarios verificados envian solicitudes"
    on public.solicitudes_alta_taller;
drop policy if exists "visitantes pueden enviar solicitudes"
    on public.solicitudes_alta_taller;
create policy "visitantes pueden enviar solicitudes"
on public.solicitudes_alta_taller
for insert
to anon, authenticated
with check (
    usuario_id is null
    and propietario is null
    and cif is null
    and email is null
    and estado = 'aprobada'
    and localidad_verificada = true
    and acepta_privacidad = true
    and acepta_privacidad_at is not null
    and nullif(btrim(version_privacidad), '') is not null
    and acepta_responsabilidad = true
    and acepta_terminos_at is not null
    and nullif(btrim(version_terminos), '') is not null
    and char_length(btrim(nombre_taller)) between 2 and 120
    and char_length(btrim(telefono)) between 9 and 30
    and char_length(btrim(direccion)) between 5 and 255
    and codigo_postal ~ '^[0-9]{5}$'
    and char_length(btrim(ciudad)) between 2 and 100
    and char_length(btrim(provincia)) between 2 and 100
    and public.provincia_de_codigo_postal(codigo_postal) = provincia
    and public.horario_semanal_es_valido(horarios)
    and cardinality(servicios) between 1 and 49
    and cardinality(fotos) <= 5
    and (
        cardinality(fotos) = 0
        or (
            acepta_condiciones_fotos = true
            and acepta_condiciones_fotos_at is not null
            and nullif(btrim(version_condiciones_fotos), '') is not null
        )
    )
    and char_length(btrim(descripcion)) between 10 and 1500
);

revoke all on table public.solicitudes_alta_taller from anon, authenticated;
grant insert on table public.solicitudes_alta_taller to anon, authenticated;
grant select on table public.solicitudes_alta_taller to authenticated;
grant usage on sequence public.solicitudes_alta_taller_id_seq to anon, authenticated;

-- Permite subir únicamente las fotografías ya declaradas por una solicitud válida.
create or replace function public.puede_subir_foto_solicitud(p_ruta text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select
        p_ruta ~ '^solicitudes/[0-9a-f-]{36}/[0-9]{2}-[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$'
        and exists (
            select 1
            from public.solicitudes_alta_taller s
            where p_ruta = any(s.fotos)
              and s.acepta_condiciones_fotos = true
              and s.acepta_condiciones_fotos_at is not null
        );
$$;

drop policy if exists "solicitudes suben sus fotos autorizadas"
    on storage.objects;
create policy "solicitudes suben sus fotos autorizadas"
on storage.objects
for insert
to anon, authenticated
with check (
    bucket_id = 'fotos-talleres'
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
    and public.puede_subir_foto_solicitud(name)
);

revoke all on function public.puede_subir_foto_solicitud(text) from public;
grant execute on function public.puede_subir_foto_solicitud(text)
    to anon, authenticated;

-- Desactiva la gestión por propietario: desde ahora solo administra TallerMap.
drop trigger if exists zz_asignar_propietario_taller_al_publicar
    on public.solicitudes_alta_taller;
drop policy if exists "propietarios leen sus solicitudes"
    on public.solicitudes_alta_taller;
do $$
begin
    if to_regclass('public.taller_propietarios') is not null then
        execute 'drop policy if exists "propietarios ven sus asignaciones" on public.taller_propietarios';
    end if;
end;
$$;

do $$
declare
    v_funcion record;
begin
    for v_funcion in
        select p.oid::regprocedure::text as firma
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in ('mis_talleres', 'actualizar_mi_taller', 'actualizar_fotos_solicitud')
    loop
        execute format(
            'revoke all on function %s from public, anon, authenticated',
            v_funcion.firma
        );
    end loop;
end;
$$;

-- RPC administrativo: mantiene la firma actual, crea las fichas nuevas sin esos
-- tres datos y conserva los valores históricos al editar una ficha antigua.
create or replace function public.admin_guardar_taller_opcional(
    p_taller_id uuid,
    p_nombre text,
    p_propietario text,
    p_cif text,
    p_email text,
    p_telefono text,
    p_web text,
    p_direccion text,
    p_codigo_postal text,
    p_ciudad text,
    p_provincia text,
    p_horarios jsonb,
    p_servicios text[],
    p_fotos text[],
    p_descripcion text,
    p_verificado boolean,
    p_activo boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_id uuid;
    v_telefono text := nullif(btrim(coalesce(p_telefono, '')), '');
    v_web text := nullif(btrim(coalesce(p_web, '')), '');
    v_direccion text := nullif(btrim(coalesce(p_direccion, '')), '');
    v_codigo_postal text := nullif(btrim(coalesce(p_codigo_postal, '')), '');
    v_ciudad text := nullif(btrim(coalesce(p_ciudad, '')), '');
    v_provincia text := nullif(btrim(coalesce(p_provincia, '')), '');
    v_descripcion text := nullif(btrim(coalesce(p_descripcion, '')), '');
    v_servicios text[] := coalesce(p_servicios, '{}'::text[]);
    v_fotos text[] := coalesce(p_fotos, '{}'::text[]);
begin
    if not public.es_administrador() then
        raise exception 'No autorizado' using errcode = '42501';
    end if;
    if char_length(btrim(coalesce(p_nombre, ''))) not between 2 and 120 then
        raise exception 'nombre_no_valido' using errcode = '23514';
    end if;
    if v_telefono is not null and char_length(v_telefono) not between 9 and 30 then
        raise exception 'telefono_no_valido' using errcode = '23514';
    end if;
    if v_web is not null and v_web !~* '^https?://[^[:space:]]+$' then
        raise exception 'web_no_valida' using errcode = '23514';
    end if;
    if v_direccion is not null and char_length(v_direccion) not between 5 and 255 then
        raise exception 'direccion_no_valida' using errcode = '23514';
    end if;
    if v_codigo_postal is not null and v_codigo_postal !~ '^[0-9]{5}$' then
        raise exception 'codigo_postal_no_valido' using errcode = '23514';
    end if;
    if v_ciudad is not null and char_length(v_ciudad) not between 2 and 100 then
        raise exception 'ciudad_no_valida' using errcode = '23514';
    end if;
    if v_codigo_postal is not null and v_provincia is not null
       and public.provincia_de_codigo_postal(v_codigo_postal) is distinct from v_provincia then
        raise exception 'provincia_codigo_postal_no_coinciden' using errcode = '23514';
    end if;
    if p_horarios is not null and not public.horario_semanal_es_valido(p_horarios) then
        raise exception 'horarios_no_validos' using errcode = '23514';
    end if;
    if cardinality(v_servicios) > 49 then
        raise exception 'servicios_no_validos' using errcode = '23514';
    end if;
    if cardinality(v_fotos) > 5 then
        raise exception 'demasiadas_fotos' using errcode = '23514';
    end if;
    if v_descripcion is not null and char_length(v_descripcion) not between 10 and 1500 then
        raise exception 'descripcion_no_valida' using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.talleres t
        where (p_taller_id is null or t.id <> p_taller_id)
          and v_direccion is not null
          and lower(btrim(coalesce(t.nombre, ''))) = lower(btrim(p_nombre))
          and lower(btrim(coalesce(t.direccion, ''))) = lower(v_direccion)
    ) then
        raise exception 'duplicado: ya existe un taller con el mismo nombre y dirección'
            using errcode = '23505';
    end if;

    if p_taller_id is null then
        insert into public.talleres (
            nombre, propietario, cif, email, telefono, web, direccion,
            codigo_postal, ciudad, provincia, pais, horarios, servicios,
            fotos, descripcion, verificado, activo, updated_at
        ) values (
            btrim(p_nombre), null, null, null, v_telefono, v_web, v_direccion,
            v_codigo_postal, v_ciudad, v_provincia, 'España', p_horarios,
            v_servicios, v_fotos, v_descripcion, coalesce(p_verificado, false),
            coalesce(p_activo, true), now()
        )
        returning id into v_id;
    else
        update public.talleres
        set nombre = btrim(p_nombre),
            telefono = v_telefono,
            web = v_web,
            direccion = v_direccion,
            codigo_postal = v_codigo_postal,
            ciudad = v_ciudad,
            provincia = v_provincia,
            horarios = p_horarios,
            servicios = v_servicios,
            fotos = v_fotos,
            descripcion = v_descripcion,
            verificado = coalesce(p_verificado, false),
            activo = coalesce(p_activo, true),
            updated_at = now()
        where id = p_taller_id
        returning id into v_id;

        if v_id is null then
            raise exception 'Taller no encontrado';
        end if;
    end if;

    return v_id;
end;
$$;

revoke all on function public.admin_guardar_taller_opcional(
    uuid, text, text, text, text, text, text, text, text, text, text,
    jsonb, text[], text[], text, boolean, boolean
) from public, anon;
grant execute on function public.admin_guardar_taller_opcional(
    uuid, text, text, text, text, text, text, text, text, text, text,
    jsonb, text[], text[], text, boolean, boolean
) to authenticated;

commit;

-- Comprobación opcional:
-- select id, nombre_taller, propietario, cif, email, telefono
-- from public.solicitudes_alta_taller
-- order by id desc limit 5;
