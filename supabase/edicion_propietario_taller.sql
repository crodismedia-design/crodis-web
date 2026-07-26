-- TallerMap: edición segura de fichas por sus propietarios.
-- Ejecuta este archivo completo en Supabase > SQL Editor.
-- Requiere haber ejecutado antes formulario_seguro.sql.

begin;

create table if not exists public.taller_propietarios (
    taller_id uuid primary key references public.talleres(id) on delete cascade,
    usuario_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

create index if not exists taller_propietarios_usuario_idx
    on public.taller_propietarios (usuario_id);

-- Asigna al usuario verificado las fichas creadas desde el formulario.
insert into public.taller_propietarios (taller_id, usuario_id)
select t.id, s.usuario_id
from public.talleres t
join public.solicitudes_alta_taller s on s.id = t.solicitud_id
where s.usuario_id is not null
on conflict (taller_id) do nothing;

-- Recupera fichas anteriores si el mismo correo ya se confirmó en Supabase Auth.
insert into public.taller_propietarios (taller_id, usuario_id)
select t.id, u.id
from public.talleres t
join public.solicitudes_alta_taller s on s.id = t.solicitud_id
join auth.users u on lower(u.email) = lower(s.email)
where u.email_confirmed_at is not null
on conflict (taller_id) do nothing;

update public.solicitudes_alta_taller s
set usuario_id = u.id
from auth.users u
where s.usuario_id is null
  and u.email_confirmed_at is not null
  and lower(u.email) = lower(s.email);

-- Recupera también los horarios de altas anteriores.
update public.talleres t
set horarios = s.horarios,
    updated_at = now()
from public.solicitudes_alta_taller s
where s.id = t.solicitud_id
  and s.horarios is not null
  and t.horarios is distinct from s.horarios;

create or replace function public.asignar_propietario_taller_publicado()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if new.usuario_id is not null then
        insert into public.taller_propietarios (taller_id, usuario_id)
        select t.id, new.usuario_id
        from public.talleres t
        where t.solicitud_id = new.id
        on conflict (taller_id) do update
        set usuario_id = excluded.usuario_id;

        update public.talleres
        set horarios = new.horarios,
            updated_at = now()
        where solicitud_id = new.id;
    end if;
    return new;
end;
$$;

drop trigger if exists zz_asignar_propietario_taller_al_publicar
    on public.solicitudes_alta_taller;
create trigger zz_asignar_propietario_taller_al_publicar
after insert on public.solicitudes_alta_taller
for each row
when (new.estado = 'aprobada')
execute function public.asignar_propietario_taller_publicado();

alter table public.taller_propietarios enable row level security;

drop policy if exists "propietarios ven sus asignaciones"
    on public.taller_propietarios;
create policy "propietarios ven sus asignaciones"
on public.taller_propietarios
for select
to authenticated
using (usuario_id = auth.uid());

create or replace function public.mis_talleres()
returns table (
    id uuid,
    nombre text,
    propietario text,
    cif text,
    email text,
    telefono text,
    web text,
    direccion text,
    codigo_postal text,
    ciudad text,
    provincia text,
    horarios jsonb,
    servicios text[],
    descripcion text,
    verificado boolean,
    activo boolean,
    updated_at timestamptz
)
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
    select
        t.id, t.nombre, t.propietario, t.cif, t.email, t.telefono,
        t.web, t.direccion, t.codigo_postal, t.ciudad, t.provincia,
        t.horarios, t.servicios, t.descripcion, t.verificado,
        t.activo, t.updated_at
    from public.talleres t
    join public.taller_propietarios p on p.taller_id = t.id
    where p.usuario_id = auth.uid()
    order by t.created_at desc;
$$;

create or replace function public.actualizar_mi_taller(
    p_taller_id uuid,
    p_nombre text,
    p_propietario text,
    p_telefono text,
    p_web text,
    p_direccion text,
    p_codigo_postal text,
    p_ciudad text,
    p_provincia text,
    p_horarios jsonb,
    p_servicios text[],
    p_descripcion text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_solicitud_id bigint;
    v_web text := nullif(btrim(coalesce(p_web, '')), '');
    v_servicios text[] := coalesce(p_servicios, array[]::text[]);
begin
    if auth.uid() is null then
        raise exception 'sesion_requerida' using errcode = '42501';
    end if;

    select t.solicitud_id
    into v_solicitud_id
    from public.talleres t
    join public.taller_propietarios p on p.taller_id = t.id
    where t.id = p_taller_id
      and p.usuario_id = auth.uid();

    if not found then
        raise exception 'taller_no_autorizado' using errcode = '42501';
    end if;

    if char_length(btrim(coalesce(p_nombre, ''))) not between 2 and 120 then
        raise exception 'nombre_no_valido' using errcode = '23514';
    end if;
    if char_length(btrim(coalesce(p_propietario, ''))) not between 2 and 120 then
        raise exception 'propietario_no_valido' using errcode = '23514';
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
    if not v_servicios <@ array[
        'mecanica-general', 'mantenimiento-programado', 'cambio-aceite-filtros',
        'pre-itv', 'frenos', 'embrague', 'correa-distribucion',
        'cadena-distribucion', 'reparacion-motor', 'sistema-refrigeracion',
        'escape-catalizador', 'caja-cambios', 'neumaticos',
        'alineacion-direccion', 'equilibrado-ruedas',
        'suspension-amortiguadores', 'direccion', 'diagnosis-electronica',
        'electricidad-automovil', 'baterias', 'alternador-motor-arranque',
        'centralitas-electronica', 'sistemas-adas', 'llaves-codificacion',
        'chapa-pintura', 'carroceria', 'lunas-cristales',
        'desabollado-sin-pintura', 'tapiceria', 'aire-acondicionado',
        'calefaccion-climatizacion', 'hibridos-electricos',
        'baterias-alta-tension', 'cargadores-vehiculo-electrico',
        'furgonetas', 'vehiculos-industriales', 'autocaravanas',
        'vehiculos-4x4', 'equipos-sonido', 'multimedia-navegacion',
        'vinilos-rotulacion', 'wrapping', 'tuning-personalizacion',
        'iluminacion-automovil', 'grua-asistencia', 'lavado-detailing',
        'montaje-accesorios', 'homologaciones', 'instalacion-glp'
    ]::text[] then
        raise exception 'servicios_no_validos' using errcode = '23514';
    end if;
    if exists (
        select 1
        from unnest(v_servicios) servicio
        where nullif(btrim(servicio), '') is null
    ) then
        raise exception 'servicios_no_validos' using errcode = '23514';
    end if;
    if char_length(btrim(coalesce(p_descripcion, ''))) not between 10 and 1500 then
        raise exception 'descripcion_no_valida' using errcode = '23514';
    end if;
    if exists (
        select 1
        from public.talleres t
        where t.id <> p_taller_id
          and t.activo = true
          and lower(btrim(coalesce(t.nombre, ''))) = lower(btrim(p_nombre))
          and lower(btrim(coalesce(t.direccion, ''))) = lower(btrim(p_direccion))
    ) then
        raise exception 'duplicado: ya existe otro taller con el mismo nombre y dirección'
            using errcode = '23505';
    end if;

    update public.talleres
    set nombre = btrim(p_nombre),
        propietario = btrim(p_propietario),
        telefono = btrim(p_telefono),
        web = v_web,
        direccion = btrim(p_direccion),
        codigo_postal = p_codigo_postal,
        ciudad = btrim(p_ciudad),
        provincia = p_provincia,
        horarios = p_horarios,
        servicios = v_servicios,
        descripcion = btrim(p_descripcion),
        updated_at = now()
    where id = p_taller_id;

    if v_solicitud_id is not null then
        update public.solicitudes_alta_taller
        set nombre_taller = btrim(p_nombre),
            propietario = btrim(p_propietario),
            telefono = btrim(p_telefono),
            web = v_web,
            direccion = btrim(p_direccion),
            codigo_postal = p_codigo_postal,
            ciudad = btrim(p_ciudad),
            provincia = p_provincia,
            horarios = p_horarios,
            servicios = v_servicios,
            descripcion = btrim(p_descripcion)
        where id = v_solicitud_id;
    end if;

    return p_taller_id;
end;
$$;

revoke all on table public.taller_propietarios from public, anon;
grant select on table public.taller_propietarios to authenticated;

revoke all on function public.mis_talleres() from public, anon;
grant execute on function public.mis_talleres() to authenticated;

revoke all on function public.actualizar_mi_taller(
    uuid, text, text, text, text, text, text, text, text, jsonb, text[], text
) from public, anon;
grant execute on function public.actualizar_mi_taller(
    uuid, text, text, text, text, text, text, text, text, jsonb, text[], text
) to authenticated;

revoke all on function public.asignar_propietario_taller_publicado()
    from public, anon, authenticated;

commit;

-- Comprobación opcional:
-- select * from public.mis_talleres();
