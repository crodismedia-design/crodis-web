-- TallerMap: control total de fichas para administradores.
-- Ejecuta este archivo completo en Supabase > SQL Editor.
-- Requiere la configuración principal y formulario_seguro.sql.

begin;

create table if not exists public.taller_historial (
    id bigint generated always as identity primary key,
    taller_id uuid,
    nombre_taller text,
    accion text not null check (accion in ('creado', 'actualizado', 'eliminado')),
    actor_id uuid,
    tipo_actor text not null,
    datos_anteriores jsonb,
    datos_nuevos jsonb,
    created_at timestamptz not null default now()
);

create index if not exists taller_historial_fecha_idx
    on public.taller_historial (created_at desc);
create index if not exists taller_historial_taller_idx
    on public.taller_historial (taller_id, created_at desc);

create or replace function public.registrar_historial_taller()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_actor uuid := auth.uid();
    v_tipo_actor text;
begin
    v_tipo_actor := case
        when v_actor is null then 'sistema'
        when public.es_administrador() then 'administrador'
        else 'propietario'
    end;

    insert into public.taller_historial (
        taller_id, nombre_taller, accion, actor_id, tipo_actor,
        datos_anteriores, datos_nuevos
    ) values (
        coalesce(new.id, old.id),
        coalesce(new.nombre, old.nombre),
        case tg_op
            when 'INSERT' then 'creado'
            when 'UPDATE' then 'actualizado'
            else 'eliminado'
        end,
        v_actor,
        v_tipo_actor,
        case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
        case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
    );

    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

drop trigger if exists registrar_historial_taller_cambios on public.talleres;
create trigger registrar_historial_taller_cambios
after insert or update or delete on public.talleres
for each row execute function public.registrar_historial_taller();

alter table public.taller_historial enable row level security;

drop policy if exists "administradores consultan historial de talleres"
    on public.taller_historial;
create policy "administradores consultan historial de talleres"
on public.taller_historial
for select
to authenticated
using (public.es_administrador());

create or replace function public.admin_guardar_taller(
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
    v_solicitud_id bigint;
    v_web text := nullif(btrim(coalesce(p_web, '')), '');
    v_servicios text[] := coalesce(p_servicios, array[]::text[]);
    v_fotos text[] := coalesce(p_fotos, array[]::text[]);
begin
    if not public.es_administrador() then
        raise exception 'No autorizado' using errcode = '42501';
    end if;

    if char_length(btrim(coalesce(p_nombre, ''))) not between 2 and 120
       or char_length(btrim(coalesce(p_propietario, ''))) not between 2 and 120 then
        raise exception 'nombre_o_propietario_no_valido' using errcode = '23514';
    end if;
    if not public.documento_fiscal_es_valido(p_cif) then
        raise exception 'documento_fiscal_no_valido' using errcode = '23514';
    end if;
    if coalesce(p_email, '') !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'email_no_valido' using errcode = '23514';
    end if;
    if char_length(btrim(coalesce(p_telefono, ''))) not between 9 and 30 then
        raise exception 'telefono_no_valido' using errcode = '23514';
    end if;
    if v_web is not null and v_web !~* '^https?://[^[:space:]]+$' then
        raise exception 'web_no_valida' using errcode = '23514';
    end if;
    if char_length(btrim(coalesce(p_direccion, ''))) not between 5 and 255 then
        raise exception 'direccion_no_valida' using errcode = '23514';
    end if;
    if coalesce(p_codigo_postal, '') !~ '^[0-9]{5}$'
       or public.provincia_de_codigo_postal(p_codigo_postal) is distinct from p_provincia then
        raise exception 'provincia_codigo_postal_no_coinciden' using errcode = '23514';
    end if;
    if char_length(btrim(coalesce(p_ciudad, ''))) not between 2 and 100 then
        raise exception 'ciudad_no_valida' using errcode = '23514';
    end if;
    if not public.horario_semanal_es_valido(p_horarios) then
        raise exception 'horarios_no_validos' using errcode = '23514';
    end if;
    if cardinality(v_servicios) < 1 or cardinality(v_servicios) > 49 then
        raise exception 'servicios_no_validos' using errcode = '23514';
    end if;
    if cardinality(v_fotos) > 5 then
        raise exception 'demasiadas_fotos' using errcode = '23514';
    end if;
    if char_length(btrim(coalesce(p_descripcion, ''))) not between 10 and 1500 then
        raise exception 'descripcion_no_valida' using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.talleres t
        where (p_taller_id is null or t.id <> p_taller_id)
          and (
              lower(btrim(coalesce(t.cif, ''))) = lower(btrim(p_cif))
              or (
                  lower(btrim(coalesce(t.nombre, ''))) = lower(btrim(p_nombre))
                  and lower(btrim(coalesce(t.direccion, ''))) = lower(btrim(p_direccion))
              )
          )
    ) then
        raise exception 'duplicado: ya existe un taller con el mismo CIF o nombre y dirección'
            using errcode = '23505';
    end if;

    if p_taller_id is null then
        insert into public.talleres (
            nombre, propietario, cif, email, telefono, web, direccion,
            codigo_postal, ciudad, provincia, pais, horarios, servicios,
            fotos, descripcion, verificado, activo, updated_at
        ) values (
            btrim(p_nombre), btrim(p_propietario), upper(btrim(p_cif)),
            lower(btrim(p_email)), btrim(p_telefono), v_web, btrim(p_direccion),
            p_codigo_postal, btrim(p_ciudad), p_provincia, 'España',
            p_horarios, v_servicios, v_fotos, btrim(p_descripcion),
            coalesce(p_verificado, false), coalesce(p_activo, true), now()
        )
        returning id into v_id;
    else
        update public.talleres
        set nombre = btrim(p_nombre),
            propietario = btrim(p_propietario),
            cif = upper(btrim(p_cif)),
            email = lower(btrim(p_email)),
            telefono = btrim(p_telefono),
            web = v_web,
            direccion = btrim(p_direccion),
            codigo_postal = p_codigo_postal,
            ciudad = btrim(p_ciudad),
            provincia = p_provincia,
            horarios = p_horarios,
            servicios = v_servicios,
            fotos = v_fotos,
            descripcion = btrim(p_descripcion),
            verificado = coalesce(p_verificado, false),
            activo = coalesce(p_activo, true),
            updated_at = now()
        where id = p_taller_id
        returning id, solicitud_id into v_id, v_solicitud_id;

        if v_id is null then
            raise exception 'Taller no encontrado';
        end if;

        if v_solicitud_id is not null then
            update public.solicitudes_alta_taller
            set nombre_taller = btrim(p_nombre),
                propietario = btrim(p_propietario),
                cif = upper(btrim(p_cif)),
                email = lower(btrim(p_email)),
                telefono = btrim(p_telefono),
                web = v_web,
                direccion = btrim(p_direccion),
                codigo_postal = p_codigo_postal,
                ciudad = btrim(p_ciudad),
                provincia = p_provincia,
                horarios = p_horarios,
                servicios = v_servicios,
                fotos = v_fotos,
                descripcion = btrim(p_descripcion),
                estado = case when coalesce(p_activo, true) then 'aprobada' else 'rechazada' end,
                revisada_at = now(),
                revisada_por = auth.uid()
            where id = v_solicitud_id;
        end if;
    end if;

    return v_id;
end;
$$;

create or replace function public.admin_cambiar_estado_taller(
    p_taller_id uuid,
    p_activo boolean
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_solicitud_id bigint;
begin
    if not public.es_administrador() then
        raise exception 'No autorizado' using errcode = '42501';
    end if;

    update public.talleres
    set activo = p_activo,
        updated_at = now()
    where id = p_taller_id
    returning solicitud_id into v_solicitud_id;

    if not found then
        raise exception 'Taller no encontrado';
    end if;

    if v_solicitud_id is not null then
        update public.solicitudes_alta_taller
        set estado = case when p_activo then 'aprobada' else 'rechazada' end,
            revisada_at = now(),
            revisada_por = auth.uid()
        where id = v_solicitud_id;
    end if;
end;
$$;

create or replace function public.admin_eliminar_taller(
    p_taller_id uuid,
    p_eliminar_solicitud boolean default true
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_solicitud_id bigint;
begin
    if not public.es_administrador() then
        raise exception 'No autorizado' using errcode = '42501';
    end if;

    select solicitud_id
    into v_solicitud_id
    from public.talleres
    where id = p_taller_id
    for update;

    if not found then
        raise exception 'Taller no encontrado';
    end if;

    delete from public.talleres where id = p_taller_id;

    if p_eliminar_solicitud and v_solicitud_id is not null then
        delete from public.solicitudes_alta_taller where id = v_solicitud_id;
    end if;
end;
$$;

create or replace function public.admin_resumen_ubicaciones(
    p_provincia text default null,
    p_ciudad text default null
)
returns table (
    provincia text,
    ciudad text,
    total bigint,
    activos bigint,
    inactivos bigint,
    verificados bigint,
    no_verificados bigint
)
language plpgsql
security definer
stable
set search_path = public, auth, pg_temp
as $$
begin
    if not public.es_administrador() then
        raise exception 'No autorizado' using errcode = '42501';
    end if;

    return query
    select
        coalesce(nullif(btrim(t.provincia), ''), 'Sin provincia') as provincia,
        coalesce(nullif(btrim(t.ciudad), ''), 'Sin población') as ciudad,
        count(*)::bigint as total,
        count(*) filter (where t.activo)::bigint as activos,
        count(*) filter (where not t.activo)::bigint as inactivos,
        count(*) filter (where t.verificado)::bigint as verificados,
        count(*) filter (where not t.verificado)::bigint as no_verificados
    from public.talleres t
    where (
            nullif(btrim(coalesce(p_provincia, '')), '') is null
            or lower(btrim(t.provincia)) = lower(btrim(p_provincia))
        )
      and (
            nullif(btrim(coalesce(p_ciudad, '')), '') is null
            or btrim(t.ciudad) ilike '%' || btrim(p_ciudad) || '%'
        )
    group by
        coalesce(nullif(btrim(t.provincia), ''), 'Sin provincia'),
        coalesce(nullif(btrim(t.ciudad), ''), 'Sin población')
    order by count(*) desc, 1 asc, 2 asc;
end;
$$;

drop policy if exists "administradores suben fotos de talleres"
    on storage.objects;
create policy "administradores suben fotos de talleres"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'fotos-talleres'
    and public.es_administrador()
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
);

drop policy if exists "administradores eliminan fotos de talleres"
    on storage.objects;
create policy "administradores eliminan fotos de talleres"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'fotos-talleres'
    and public.es_administrador()
);

revoke all on function public.admin_guardar_taller(
    uuid, text, text, text, text, text, text, text, text, text, text,
    jsonb, text[], text[], text, boolean, boolean
) from public, anon;
grant execute on function public.admin_guardar_taller(
    uuid, text, text, text, text, text, text, text, text, text, text,
    jsonb, text[], text[], text, boolean, boolean
) to authenticated;

revoke all on function public.admin_cambiar_estado_taller(uuid, boolean)
    from public, anon;
grant execute on function public.admin_cambiar_estado_taller(uuid, boolean)
    to authenticated;

revoke all on function public.admin_eliminar_taller(uuid, boolean)
    from public, anon;
grant execute on function public.admin_eliminar_taller(uuid, boolean)
    to authenticated;

revoke all on function public.admin_resumen_ubicaciones(text, text)
    from public, anon;
grant execute on function public.admin_resumen_ubicaciones(text, text)
    to authenticated;

revoke all on table public.taller_historial from public, anon;
grant select on table public.taller_historial to authenticated;
revoke all on function public.registrar_historial_taller()
    from public, anon, authenticated;

commit;

-- La eliminación definitiva borra también la solicitud original.
-- Las fotografías se eliminan primero desde el panel administrativo.
