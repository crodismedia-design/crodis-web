-- TallerMap: formulario seguro con correo verificado, límites, privacidad,
-- validación reforzada de horarios y sincronización de fotografías.
-- Ejecuta este archivo completo una sola vez en Supabase > SQL Editor.

begin;

alter table public.solicitudes_alta_taller
    add column if not exists usuario_id uuid references auth.users(id) on delete set null;
alter table public.solicitudes_alta_taller
    add column if not exists localidad_verificada boolean not null default false;
alter table public.solicitudes_alta_taller
    add column if not exists acepta_privacidad boolean not null default false;
alter table public.solicitudes_alta_taller
    add column if not exists acepta_privacidad_at timestamptz;
alter table public.solicitudes_alta_taller
    add column if not exists version_privacidad text;

create index if not exists solicitudes_usuario_fecha_idx
    on public.solicitudes_alta_taller (usuario_id, created_at desc)
    where usuario_id is not null;

create or replace function public.documento_fiscal_es_valido(p_documento text)
returns boolean
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
declare
    v_documento text;
    v_numero bigint;
    v_letra text;
    v_letras_nif constant text := 'TRWAGMYFPDXBNJZSQVHLCKE';
    v_tipo text;
    v_digitos text;
    v_control text;
    v_suma integer := 0;
    v_valor integer;
    v_control_numero integer;
    v_control_letra text;
    i integer;
begin
    v_documento := upper(regexp_replace(p_documento, '[[:space:].-]', '', 'g'));

    if v_documento ~ '^[0-9]{8}[A-Z]$' then
        v_numero := left(v_documento, 8)::bigint;
        v_letra := right(v_documento, 1);
        return substr(v_letras_nif, (v_numero % 23)::integer + 1, 1) = v_letra;
    end if;

    if v_documento ~ '^[XYZ][0-9]{7}[A-Z]$' then
        v_numero := (
            case left(v_documento, 1)
                when 'X' then '0'
                when 'Y' then '1'
                else '2'
            end || substr(v_documento, 2, 7)
        )::bigint;
        v_letra := right(v_documento, 1);
        return substr(v_letras_nif, (v_numero % 23)::integer + 1, 1) = v_letra;
    end if;

    if v_documento !~ '^[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]$' then
        return false;
    end if;

    v_tipo := left(v_documento, 1);
    v_digitos := substr(v_documento, 2, 7);
    v_control := right(v_documento, 1);

    for i in 1..7 loop
        v_valor := substr(v_digitos, i, 1)::integer;
        if i % 2 = 0 then
            v_suma := v_suma + v_valor;
        else
            v_valor := v_valor * 2;
            v_suma := v_suma + (v_valor / 10) + (v_valor % 10);
        end if;
    end loop;

    v_control_numero := (10 - (v_suma % 10)) % 10;
    v_control_letra := substr('JABCDEFGHI', v_control_numero + 1, 1);

    if position(v_tipo in 'ABEH') > 0 then
        return v_control = v_control_numero::text;
    elsif position(v_tipo in 'KPQS') > 0 then
        return v_control = v_control_letra;
    end if;
    return v_control in (v_control_numero::text, v_control_letra);
end;
$$;

create or replace function public.horario_semanal_es_valido(p_horarios jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
declare
    v_dia text;
    v_horario jsonb;
    v_turno jsonb;
    v_turnos jsonb;
    v_apertura text;
    v_cierre text;
    v_cierre_anterior text;
    v_hay_dia_abierto boolean := false;
begin
    if jsonb_typeof(p_horarios) <> 'object' then
        return false;
    end if;

    foreach v_dia in array array[
        'lunes', 'martes', 'miercoles', 'jueves',
        'viernes', 'sabado', 'domingo'
    ] loop
        v_horario := p_horarios -> v_dia;
        if v_horario is null or jsonb_typeof(v_horario) <> 'object' then
            return false;
        end if;
        if v_horario ->> 'cerrado' not in ('true', 'false') then
            return false;
        end if;
        v_turnos := v_horario -> 'turnos';
        if v_turnos is null or jsonb_typeof(v_turnos) <> 'array' then
            return false;
        end if;

        if (v_horario ->> 'cerrado')::boolean then
            if jsonb_array_length(v_turnos) <> 0 then
                return false;
            end if;
            continue;
        end if;

        v_hay_dia_abierto := true;
        if jsonb_array_length(v_turnos) not between 1 and 2 then
            return false;
        end if;

        v_cierre_anterior := null;
        for v_turno in select value from jsonb_array_elements(v_turnos) loop
            v_apertura := v_turno ->> 'apertura';
            v_cierre := v_turno ->> 'cierre';
            if v_apertura !~ '^([01][0-9]|2[0-3]):(00|30)$' then
                return false;
            end if;
            if v_cierre !~ '^(([01][0-9]|2[0-3]):(00|30)|24:00)$' then
                return false;
            end if;
            if v_cierre <= v_apertura then
                return false;
            end if;
            if v_cierre_anterior is not null and v_apertura < v_cierre_anterior then
                return false;
            end if;
            v_cierre_anterior := v_cierre;
        end loop;
    end loop;

    return v_hay_dia_abierto;
end;
$$;

create or replace function public.preparar_estado_solicitud()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_usuario uuid := auth.uid();
    v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
    -- Las operaciones del SQL Editor no llevan JWT. Las peticiones públicas sí.
    if v_usuario is null and coalesce(auth.role(), '') in ('anon', 'authenticated') then
        raise exception 'correo_no_verificado: inicia sesión mediante el enlace enviado por correo'
            using errcode = '42501';
    end if;

    if v_usuario is not null then
        if v_email = '' then
            raise exception 'correo_no_verificado: la sesión no contiene un correo confirmado'
                using errcode = '42501';
        end if;
        if lower(trim(new.email)) <> v_email then
            raise exception 'correo_no_verificado: el correo del formulario no coincide con la sesión'
                using errcode = '42501';
        end if;
        if (
            select count(*)
            from public.solicitudes_alta_taller s
            where s.usuario_id = v_usuario
              and s.created_at > now() - interval '24 hours'
        ) >= 3 then
            raise exception 'limite_altas: demasiadas altas durante las últimas 24 horas'
                using errcode = 'P0001';
        end if;
        new.usuario_id := v_usuario;
        new.email := v_email;
    end if;

    if new.localidad_verificada is not true then
        raise exception 'localidad_no_verificada: comprueba población y código postal'
            using errcode = '23514';
    end if;
    if new.acepta_privacidad is not true
        or new.acepta_privacidad_at is null
        or nullif(trim(new.version_privacidad), '') is null then
        raise exception 'privacidad_no_aceptada'
            using errcode = '23514';
    end if;
    if not public.documento_fiscal_es_valido(new.cif) then
        raise exception 'documento_fiscal_no_valido'
            using errcode = '23514';
    end if;
    if not public.horario_semanal_es_valido(new.horarios) then
        raise exception 'horarios_no_validos'
            using errcode = '23514';
    end if;

    new.estado := 'aprobada';
    new.revisada_at := now();
    new.revisada_por := null;
    return new;
end;
$$;

alter table public.solicitudes_alta_taller
    drop constraint if exists solicitudes_horarios_obligatorios;
alter table public.solicitudes_alta_taller
    add constraint solicitudes_horarios_obligatorios
    check (public.horario_semanal_es_valido(horarios)) not valid;

alter table public.solicitudes_alta_taller
    drop constraint if exists solicitudes_documento_fiscal_valido;
alter table public.solicitudes_alta_taller
    add constraint solicitudes_documento_fiscal_valido
    check (public.documento_fiscal_es_valido(cif)) not valid;

drop policy if exists "visitantes pueden enviar solicitudes"
    on public.solicitudes_alta_taller;
drop policy if exists "usuarios verificados envian solicitudes"
    on public.solicitudes_alta_taller;
create policy "usuarios verificados envian solicitudes"
on public.solicitudes_alta_taller
for insert
to authenticated
with check (
    usuario_id = auth.uid()
    and lower(trim(email)) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and estado = 'aprobada'
    and localidad_verificada = true
    and acepta_privacidad = true
    and acepta_privacidad_at is not null
    and nullif(trim(version_privacidad), '') is not null
    and acepta_responsabilidad = true
    and acepta_terminos_at is not null
    and public.documento_fiscal_es_valido(cif)
    and public.horario_semanal_es_valido(horarios)
    and public.provincia_de_codigo_postal(codigo_postal) = provincia
    and cardinality(servicios) > 0
    and cardinality(fotos) <= 5
    and (
        cardinality(fotos) = 0
        or (
            acepta_condiciones_fotos = true
            and acepta_condiciones_fotos_at is not null
            and nullif(trim(version_condiciones_fotos), '') is not null
        )
    )
);

drop policy if exists "propietarios leen sus solicitudes"
    on public.solicitudes_alta_taller;
create policy "propietarios leen sus solicitudes"
on public.solicitudes_alta_taller
for select
to authenticated
using (usuario_id = auth.uid());

create or replace function public.puede_subir_foto_solicitud(p_ruta text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select auth.uid() is not null
        and exists (
            select 1
            from public.solicitudes_alta_taller s
            where s.usuario_id = auth.uid()
              and p_ruta = any(s.fotos)
              and s.acepta_condiciones_fotos = true
              and s.acepta_condiciones_fotos_at is not null
        );
$$;

drop policy if exists "solicitudes suben sus fotos autorizadas" on storage.objects;
create policy "solicitudes suben sus fotos autorizadas"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'fotos-talleres'
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
    and public.puede_subir_foto_solicitud(name)
);

create or replace function public.actualizar_fotos_solicitud(
    p_solicitud_id bigint,
    p_fotos text[]
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_fotos_anteriores text[];
begin
    if auth.uid() is null then
        raise exception 'No autorizado' using errcode = '42501';
    end if;

    select s.fotos
    into v_fotos_anteriores
    from public.solicitudes_alta_taller s
    where s.id = p_solicitud_id
      and s.usuario_id = auth.uid();

    if not found then
        raise exception 'Solicitud no encontrada' using errcode = 'P0002';
    end if;

    p_fotos := coalesce(p_fotos, '{}'::text[]);
    if cardinality(p_fotos) > 5 or not (p_fotos <@ v_fotos_anteriores) then
        raise exception 'Lista de fotografías no permitida' using errcode = '42501';
    end if;

    update public.solicitudes_alta_taller
    set fotos = p_fotos
    where id = p_solicitud_id;

    update public.talleres
    set fotos = p_fotos,
        updated_at = now()
    where solicitud_id = p_solicitud_id;
end;
$$;

revoke insert on table public.solicitudes_alta_taller from anon;
grant insert, select on table public.solicitudes_alta_taller to authenticated;
revoke usage on sequence public.solicitudes_alta_taller_id_seq from anon;
grant usage on sequence public.solicitudes_alta_taller_id_seq to authenticated;

revoke all on function public.documento_fiscal_es_valido(text)
    from public, anon, authenticated;
grant execute on function public.documento_fiscal_es_valido(text)
    to anon, authenticated;
revoke all on function public.horario_semanal_es_valido(jsonb)
    from public, anon, authenticated;
grant execute on function public.horario_semanal_es_valido(jsonb)
    to anon, authenticated;
revoke all on function public.preparar_estado_solicitud()
    from public, anon, authenticated;
revoke all on function public.puede_subir_foto_solicitud(text)
    from public, anon, authenticated;
grant execute on function public.puede_subir_foto_solicitud(text)
    to authenticated;
revoke all on function public.actualizar_fotos_solicitud(bigint, text[])
    from public, anon, authenticated;
grant execute on function public.actualizar_fotos_solicitud(bigint, text[])
    to authenticated;

commit;

-- Comprobaciones opcionales:
-- select id, nombre_taller, email, usuario_id, localidad_verificada,
--        acepta_privacidad, created_at
-- from public.solicitudes_alta_taller
-- order by created_at desc limit 10;
