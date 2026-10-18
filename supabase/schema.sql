-- =====================================================================
-- ESQUEMA v2: APP DE BARBERÍA
-- Decisiones: el cliente NO crea cuenta (agenda con nombre + WhatsApp),
-- servicios con duración distinta, varios barberos, productos a futuro.
--
-- Pegar completo en Supabase > SQL Editor > New query > Run
-- Guardar este archivo en el repo (ej. supabase/schema.sql)
-- =====================================================================

create extension if not exists btree_gist with schema extensions;

-- ---------------------------------------------------------------------
-- 1. TIPOS
-- ---------------------------------------------------------------------
create type estado_cita as enum ('pendiente', 'asistio', 'ausente', 'cancelado');

-- ---------------------------------------------------------------------
-- 2. TABLAS
-- ---------------------------------------------------------------------

-- Usuarios que pueden entrar al panel del dueño (el cliente nunca inicia sesión)
create table administradores (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- Barberos (no inician sesión; solo sirven para saber quién atiende cada cita)
create table barberos (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  foto_url   text,
  activo     boolean not null default true,   -- desactivar en lugar de borrar
  created_at timestamptz not null default now()
);

-- Servicios: cortes, barbas, combos... cada uno con su duración
create table servicios (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  descripcion     text,
  precio          numeric(12,2) not null check (precio >= 0),
  precio_anterior numeric(12,2) check (precio_anterior >= 0),  -- para mostrar tachado en promociones
  duracion_min    integer not null default 30 check (duracion_min > 0),
  foto_url        text,
  es_promocion    boolean not null default false,
  activo          boolean not null default true,
  created_at      timestamptz not null default now()
);

-- Productos físicos (gel, cera...). Se pueden mostrar y promocionar desde ya;
-- la compra en línea (tabla de pedidos) se agrega más adelante.
create table productos (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  descripcion     text,
  precio          numeric(12,2) not null check (precio >= 0),
  precio_anterior numeric(12,2) check (precio_anterior >= 0),
  foto_url        text,
  stock           integer not null default 0 check (stock >= 0),
  es_promocion    boolean not null default false,
  activo          boolean not null default true,
  created_at      timestamptz not null default now()
);

-- Disponibilidad semanal de la barbería (hora de Colombia)
create table horarios (
  id          uuid primary key default gen_random_uuid(),
  dia_semana  smallint not null check (dia_semana between 0 and 6),   -- 0 = domingo ... 6 = sábado
  hora_inicio time not null,
  hora_fin    time not null,
  activo      boolean not null default true,
  check (hora_fin > hora_inicio)
);

-- Citas
create table citas (
  id               uuid primary key default gen_random_uuid(),
  barbero_id       uuid not null references barberos(id) on delete restrict,
  servicio_id      uuid not null references servicios(id) on delete restrict,
  nombre_cliente   text not null check (char_length(btrim(nombre_cliente)) between 2 and 80),
  whatsapp_cliente text not null check (whatsapp_cliente ~ '^\+[1-9][0-9]{9,14}$'),  -- ej. +573001234567
  inicio           timestamptz not null,
  fin              timestamptz not null,           -- lo calcula el trigger: inicio + duración del servicio
  estado           estado_cita not null default 'pendiente',
  precio           numeric(12,2) not null,         -- precio congelado al agendar (lo fija el trigger)
  token_cliente    uuid not null default gen_random_uuid(),  -- "llave secreta" para que el cliente vea/gestione sus citas sin cuenta
  created_at       timestamptz not null default now(),
  check (fin > inicio),

  -- Un mismo barbero no puede tener dos citas activas solapadas,
  -- aunque dos clientes agenden en el mismo segundo.
  constraint citas_sin_solape
    exclude using gist (barbero_id with =, tstzrange(inicio, fin) with &&)
    where (estado in ('pendiente', 'asistio'))
);

create index citas_inicio_idx   on citas (inicio);
create index citas_token_idx    on citas (token_cliente);
create index citas_whatsapp_idx on citas (whatsapp_cliente);

-- ---------------------------------------------------------------------
-- 3. FUNCIONES Y TRIGGERS
-- ---------------------------------------------------------------------

-- ¿El usuario actual es el dueño?
create function es_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from administradores where user_id = auth.uid());
$$;

-- Antes de guardar una cita: calcula la hora de fin y fija el precio
create function citas_preparar()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  s servicios%rowtype;
begin
  select * into s from servicios where id = new.servicio_id;

  new.fin := new.inicio + make_interval(mins => s.duracion_min);

  if tg_op = 'INSERT' then
    new.precio := coalesce(new.precio, s.precio);
  elsif new.servicio_id is distinct from old.servicio_id
        and new.precio is not distinct from old.precio then
    new.precio := s.precio;
  end if;

  return new;
end;
$$;

create trigger citas_preparar_trg
  before insert or update on citas
  for each row execute function citas_preparar();

-- DISPONIBILIDAD: devuelve las horas de inicio libres para un servicio en una fecha.
-- Respeta horarios, duración del servicio, citas existentes de cada barbero y que no sea pasado.
-- Si p_barbero_id es null, devuelve una fila por cada barbero libre en cada hora.
create function disponibilidad(
  p_servicio_id   uuid,
  p_fecha         date,
  p_barbero_id    uuid default null,
  p_ignorar_cita  uuid default null     -- sirve al reprogramar: no chocar con la propia cita
)
returns table (barbero_id uuid, inicio timestamptz)
language sql stable security definer set search_path = public
as $$
  with srv as (
    select duracion_min from servicios where id = p_servicio_id and activo
  ),
  franjas as (
    select h.hora_inicio, h.hora_fin
    from horarios h
    where h.activo and h.dia_semana = extract(dow from p_fecha)
  ),
  candidatos as (
    select b.id as barbero_id, g as inicio_local
    from franjas f
    cross join srv
    cross join barberos b
    cross join lateral generate_series(
      p_fecha + f.hora_inicio,
      p_fecha + f.hora_fin - make_interval(mins => srv.duracion_min),
      interval '30 minutes'            -- cada cuánto se ofrece una hora (cambiar aquí si quieres 15 o 60)
    ) as g
    where b.activo
      and (p_barbero_id is null or b.id = p_barbero_id)
  )
  select c.barbero_id,
         c.inicio_local at time zone 'America/Bogota' as inicio
  from candidatos c
  cross join srv
  where (c.inicio_local at time zone 'America/Bogota') > now()
    and not exists (
      select 1
      from citas ci
      where ci.barbero_id = c.barbero_id
        and ci.estado in ('pendiente', 'asistio')
        and ci.id is distinct from p_ignorar_cita
        and tstzrange(ci.inicio, ci.fin) && tstzrange(
              c.inicio_local at time zone 'America/Bogota',
              (c.inicio_local + make_interval(mins => srv.duracion_min)) at time zone 'America/Bogota'
            )
    )
  order by 2, 1;
$$;

-- CREAR CITA (la usa el cliente sin cuenta).
-- p_barbero_id null = "cualquiera disponible". p_token es opcional (el frontend puede
-- generar uno y guardarlo en el navegador); si no se envía, se crea uno y se devuelve.
create function crear_cita(
  p_nombre       text,
  p_whatsapp     text,
  p_servicio_id  uuid,
  p_inicio       timestamptz,
  p_barbero_id   uuid default null,
  p_token        uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_nombre  text := btrim(coalesce(p_nombre, ''));
  v_barbero uuid;
  v_token   uuid := coalesce(p_token, gen_random_uuid());
  v_cita    citas%rowtype;
begin
  if char_length(v_nombre) < 2 or char_length(v_nombre) > 80 then
    raise exception 'Nombre inválido';
  end if;

  if p_whatsapp is null or p_whatsapp !~ '^\+[1-9][0-9]{9,14}$' then
    raise exception 'Número de WhatsApp inválido';
  end if;

  -- Freno básico contra abuso: máximo 2 citas pendientes por número
  if (select count(*) from citas
      where whatsapp_cliente = p_whatsapp and estado = 'pendiente' and inicio > now()) >= 2 then
    raise exception 'Ya tienes 2 citas pendientes con este número';
  end if;

  select d.barbero_id into v_barbero
  from disponibilidad(p_servicio_id, (p_inicio at time zone 'America/Bogota')::date, p_barbero_id) d
  where d.inicio = p_inicio
  limit 1;

  if v_barbero is null then
    raise exception 'Ese horario ya no está disponible';
  end if;

  insert into citas (barbero_id, servicio_id, nombre_cliente, whatsapp_cliente, inicio, token_cliente)
  values (v_barbero, p_servicio_id, v_nombre, p_whatsapp, p_inicio, v_token)
  returning * into v_cita;

  return jsonb_build_object(
    'cita_id',    v_cita.id,
    'token',      v_token,
    'barbero_id', v_cita.barbero_id,
    'inicio',     v_cita.inicio,
    'fin',        v_cita.fin
  );

exception
  when exclusion_violation then
    raise exception 'Ese horario acaba de ser tomado, elige otro';
end;
$$;

-- MIS CITAS: lista las citas ligadas a un token (próxima y historial)
create function mis_citas(p_token uuid)
returns table (
  id        uuid,
  servicio  text,
  barbero   text,
  inicio    timestamptz,
  fin       timestamptz,
  estado    estado_cita,
  precio    numeric
)
language sql stable security definer set search_path = public
as $$
  select c.id, s.nombre, b.nombre, c.inicio, c.fin, c.estado, c.precio
  from citas c
  join servicios s on s.id = c.servicio_id
  join barberos  b on b.id = c.barbero_id
  where c.token_cliente = p_token
  order by c.inicio desc;
$$;

-- CANCELAR: solo citas pendientes y futuras, y solo con el token correcto
create function cancelar_cita(p_token uuid, p_cita_id uuid)
returns boolean
language plpgsql security definer set search_path = public
as $$
begin
  update citas
     set estado = 'cancelado'
   where id = p_cita_id
     and token_cliente = p_token
     and estado = 'pendiente'
     and inicio > now();
  return found;
end;
$$;

-- REPROGRAMAR: mueve una cita pendiente a otra hora disponible
create function reprogramar_cita(
  p_token       uuid,
  p_cita_id     uuid,
  p_inicio      timestamptz,
  p_barbero_id  uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_cita    citas%rowtype;
  v_barbero uuid;
begin
  select * into v_cita
  from citas
  where id = p_cita_id
    and token_cliente = p_token
    and estado = 'pendiente'
    and inicio > now();

  if not found then
    raise exception 'Cita no encontrada o ya no se puede modificar';
  end if;

  -- Prefiere conservar el mismo barbero si está libre
  select d.barbero_id into v_barbero
  from disponibilidad(
         v_cita.servicio_id,
         (p_inicio at time zone 'America/Bogota')::date,
         p_barbero_id,
         v_cita.id
       ) d
  where d.inicio = p_inicio
  order by (d.barbero_id = v_cita.barbero_id) desc
  limit 1;

  if v_barbero is null then
    raise exception 'Ese horario ya no está disponible';
  end if;

  update citas
     set inicio = p_inicio, barbero_id = v_barbero
   where id = v_cita.id
  returning * into v_cita;

  return jsonb_build_object(
    'cita_id',    v_cita.id,
    'barbero_id', v_cita.barbero_id,
    'inicio',     v_cita.inicio,
    'fin',        v_cita.fin
  );

exception
  when exclusion_violation then
    raise exception 'Ese horario acaba de ser tomado, elige otro';
end;
$$;

-- ---------------------------------------------------------------------
-- 4. SEGURIDAD (Row Level Security)
-- El cliente (anónimo) NUNCA toca la tabla citas directamente:
-- todo pasa por las funciones de arriba.
-- ---------------------------------------------------------------------
alter table administradores enable row level security;   -- sin políticas: nadie la lee directo
alter table barberos        enable row level security;
alter table servicios       enable row level security;
alter table productos       enable row level security;
alter table horarios        enable row level security;
alter table citas           enable row level security;

-- Catálogo público (solo lo activo); el dueño ve y gestiona todo
create policy "barberos: lectura publica de activos" on barberos
  for select using (activo or es_admin());
create policy "barberos: admin total" on barberos
  for all using (es_admin()) with check (es_admin());

create policy "servicios: lectura publica de activos" on servicios
  for select using (activo or es_admin());
create policy "servicios: admin total" on servicios
  for all using (es_admin()) with check (es_admin());

create policy "productos: lectura publica de activos" on productos
  for select using (activo or es_admin());
create policy "productos: admin total" on productos
  for all using (es_admin()) with check (es_admin());

create policy "horarios: lectura publica" on horarios
  for select using (true);
create policy "horarios: admin total" on horarios
  for all using (es_admin()) with check (es_admin());

-- Citas: solo el dueño accede directamente
create policy "citas: admin total" on citas
  for all using (es_admin()) with check (es_admin());

-- ---------------------------------------------------------------------
-- 5. DESPUÉS DE EJECUTAR TODO LO ANTERIOR
-- ---------------------------------------------------------------------
-- a) Crea la cuenta del dueño: Authentication > Users > Add user.
-- b) Conviértela en administrador (reemplaza el correo):
--
--    insert into administradores (user_id)
--    select id from auth.users where email = 'dueno@correo.com';
--
-- c) Carga datos de prueba (un barbero, un par de servicios y horarios) para
--    poder probar `disponibilidad` y `crear_cita`.
