-- =====================================================================
--  CompraYa - Cambios v2 (CONSOLIDADO - usar SOLO este)
--  Pega TODO en el SQL Editor de Supabase y dale Run.
--  Es seguro y se puede re-correr: solo agrega/ajusta, no borra datos.
--
--  Incluye:
--   - Registro publico solo crea compradores (vendedor lo crea el admin)
--   - Soporte por tickets
--   - Vista de ventas del vendedor
--   - TODA la capa de control del admin (moderacion):
--       deshabilitar/suspender cuentas, ocultar/bloquear mensajes,
--       reportes de usuarios, y auditoria de cada accion de control.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1) Registro publico = SOLO comprador. Vendedor lo crea el admin.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.perfiles (id, nombre, email, rol)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)),
    new.email,
    'comprador'
  );
  return new;
end; $$;


-- ---------------------------------------------------------------------
--  2) Campos de CONTROL en perfiles
--     activo           -> cuenta habilitada o no
--     creado_por       -> que admin creo la cuenta
--     motivo_bloqueo   -> por que se deshabilito
--     suspendido_hasta -> suspension temporal (se reactiva sola)
-- ---------------------------------------------------------------------
alter table public.perfiles add column if not exists activo boolean not null default true;
alter table public.perfiles add column if not exists creado_por uuid references public.perfiles(id);
alter table public.perfiles add column if not exists motivo_bloqueo text;
alter table public.perfiles add column if not exists suspendido_hasta timestamptz;


-- ---------------------------------------------------------------------
--  3) Campos de MODERACION en chats
-- ---------------------------------------------------------------------
alter table public.mensajes       add column if not exists oculto boolean not null default false;
alter table public.mensajes       add column if not exists oculto_por uuid references public.perfiles(id);
alter table public.conversaciones add column if not exists bloqueada boolean not null default false;


-- ---------------------------------------------------------------------
--  4) FUNCIONES DE APOYO
-- ---------------------------------------------------------------------
-- ¿es admin?
create or replace function public.es_admin()
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from public.perfiles
                 where id = auth.uid() and rol = 'admin');
$$;

-- ¿la cuenta esta activa? (habilitada y sin suspension vigente)
create or replace function public.esta_activo()
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (
    select 1 from public.perfiles
    where id = auth.uid()
      and activo = true
      and (suspendido_hasta is null or suspendido_hasta < now())
  );
$$;


-- ---------------------------------------------------------------------
--  5) SOPORTE: tickets para contactar al admin
-- ---------------------------------------------------------------------
create table if not exists public.tickets (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references public.perfiles(id) on delete cascade,
  asunto       text not null,
  estado       text not null default 'abierto'
               check (estado in ('abierto','en_proceso','cerrado')),
  creado       timestamptz not null default now()
);

create table if not exists public.ticket_mensajes (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.tickets(id) on delete cascade,
  emisor_id   uuid not null references public.perfiles(id) on delete cascade,
  texto       text not null,
  fecha       timestamptz not null default now()
);


-- ---------------------------------------------------------------------
--  6) REPORTES: cualquiera reporta contenido, el admin revisa
-- ---------------------------------------------------------------------
create table if not exists public.reportes (
  id             uuid primary key default gen_random_uuid(),
  reportante_id  uuid not null references public.perfiles(id) on delete cascade,
  tipo           text not null check (tipo in ('producto','mensaje','usuario','conversacion')),
  referencia_id  uuid,                       -- id de lo reportado
  motivo         text,
  estado         text not null default 'pendiente'
                 check (estado in ('pendiente','revisado','resuelto')),
  creado         timestamptz not null default now()
);


-- =====================================================================
--  7) PERMISOS (RLS) - se re-crean para meter el control de cuenta activa
-- =====================================================================
alter table public.tickets         enable row level security;
alter table public.ticket_mensajes enable row level security;
alter table public.reportes        enable row level security;

-- ---- limpio politicas que voy a re-crear (para poder re-correr sin error) ----
drop policy if exists "prod_insert" on public.productos;
drop policy if exists "ped_insert"  on public.pedidos;
drop policy if exists "det_insert"  on public.pedido_detalle;
drop policy if exists "conv_insert" on public.conversaciones;
drop policy if exists "msg_insert"  on public.mensajes;
drop policy if exists "msg_update"  on public.mensajes;
drop policy if exists "msg_delete"  on public.mensajes;
drop policy if exists "tk_select"   on public.tickets;
drop policy if exists "tk_insert"   on public.tickets;
drop policy if exists "tk_update"   on public.tickets;
drop policy if exists "tkm_select"  on public.ticket_mensajes;
drop policy if exists "tkm_insert"  on public.ticket_mensajes;
drop policy if exists "rep_select"  on public.reportes;
drop policy if exists "rep_insert"  on public.reportes;
drop policy if exists "rep_update"  on public.reportes;

-- ---- productos: crear solo vendedor/admin Y con cuenta activa ----
create policy "prod_insert" on public.productos for insert
  with check (
    vendedor_id = auth.uid()
    and public.esta_activo()
    and exists (select 1 from public.perfiles
                where id = auth.uid() and rol in ('vendedor','admin'))
  );

-- ---- comprar: solo con cuenta activa ----
create policy "ped_insert" on public.pedidos for insert
  with check (comprador_id = auth.uid() and public.esta_activo());

create policy "det_insert" on public.pedido_detalle for insert
  with check (exists (select 1 from public.pedidos pe
                      where pe.id = pedido_id and pe.comprador_id = auth.uid()));

-- ---- abrir chat: solo con cuenta activa ----
create policy "conv_insert" on public.conversaciones for insert
  with check (comprador_id = auth.uid() and public.esta_activo());

-- ---- mandar mensaje: cuenta activa Y conversacion no bloqueada ----
create policy "msg_insert" on public.mensajes for insert
  with check (
    emisor_id = auth.uid()
    and public.esta_activo()
    and exists (select 1 from public.conversaciones c where c.id = conversacion_id
                and (c.comprador_id = auth.uid() or c.vendedor_id = auth.uid())
                and c.bloqueada = false)
  );

-- ---- el admin puede ocultar (update) o eliminar (delete) mensajes ----
create policy "msg_update" on public.mensajes for update
  using (public.es_admin()) with check (public.es_admin());
create policy "msg_delete" on public.mensajes for delete
  using (public.es_admin());

-- ---- soporte: el dueño ve lo suyo, el admin ve todo ----
create policy "tk_select" on public.tickets for select
  using (usuario_id = auth.uid() or public.es_admin());
create policy "tk_insert" on public.tickets for insert
  with check (usuario_id = auth.uid() and public.esta_activo());
create policy "tk_update" on public.tickets for update
  using (usuario_id = auth.uid() or public.es_admin());

create policy "tkm_select" on public.ticket_mensajes for select
  using (exists (select 1 from public.tickets t where t.id = ticket_id
                 and (t.usuario_id = auth.uid() or public.es_admin())));
create policy "tkm_insert" on public.ticket_mensajes for insert
  with check (
    emisor_id = auth.uid()
    and exists (select 1 from public.tickets t where t.id = ticket_id
                and (t.usuario_id = auth.uid() or public.es_admin()))
  );

-- ---- reportes: el que reporta ve lo suyo, el admin ve y resuelve todo ----
create policy "rep_select" on public.reportes for select
  using (reportante_id = auth.uid() or public.es_admin());
create policy "rep_insert" on public.reportes for insert
  with check (reportante_id = auth.uid());
create policy "rep_update" on public.reportes for update
  using (public.es_admin()) with check (public.es_admin());


-- =====================================================================
--  8) AUDITORIA DE MODERACION (que el admin no escape a nada tampoco)
-- =====================================================================

-- Cambios en una cuenta: bloqueo, suspension, cambio de rol.
create or replace function public.log_perfil_mod()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if new.activo is distinct from old.activo then
    insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(),
            case when new.activo then 'DESBLOQUEO' else 'BLOQUEO' end,
            'usuario', new.id,
            jsonb_build_object('a', new.email, 'motivo', new.motivo_bloqueo));
  end if;
  if new.suspendido_hasta is distinct from old.suspendido_hasta then
    insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(), 'SUSPENSION', 'usuario', new.id,
            jsonb_build_object('hasta', new.suspendido_hasta));
  end if;
  if new.rol is distinct from old.rol then
    insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(), 'CAMBIO_ROL', 'usuario', new.id,
            jsonb_build_object('de', old.rol, 'a', new.rol));
  end if;
  return new;
end; $$;

drop trigger if exists trg_log_perfil_mod on public.perfiles;
create trigger trg_log_perfil_mod
  after update on public.perfiles
  for each row execute function public.log_perfil_mod();

-- Mensajes ocultados o eliminados por moderacion.
create or replace function public.log_mensaje_mod()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(), 'ELIMINA_MENSAJE', 'mensaje', old.id, null);
    return old;
  elsif new.oculto is distinct from old.oculto then
    insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(),
            case when new.oculto then 'OCULTA_MENSAJE' else 'MUESTRA_MENSAJE' end,
            'mensaje', new.id, null);
  end if;
  return new;
end; $$;

drop trigger if exists trg_log_mensaje_mod on public.mensajes;
create trigger trg_log_mensaje_mod
  after update or delete on public.mensajes
  for each row execute function public.log_mensaje_mod();

-- Conversaciones bloqueadas o archivadas.
create or replace function public.log_conv_mod()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if new.bloqueada is distinct from old.bloqueada then
    insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(),
            case when new.bloqueada then 'BLOQUEA_CHAT' else 'DESBLOQUEA_CHAT' end,
            'conversacion', new.id, null);
  end if;
  if new.archivada is distinct from old.archivada then
    insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
    values (auth.uid(), 'ARCHIVA_CHAT', 'conversacion', new.id, null);
  end if;
  return new;
end; $$;

drop trigger if exists trg_log_conv_mod on public.conversaciones;
create trigger trg_log_conv_mod
  after update on public.conversaciones
  for each row execute function public.log_conv_mod();


-- =====================================================================
--  9) VISTA de ventas del vendedor (cuanto vendio por mes)
-- =====================================================================
create or replace view public.ventas_vendedor
with (security_invoker = true) as
select
  p.vendedor_id,
  date_trunc('month', pe.fecha)        as mes,
  count(*)                             as ventas,
  sum(d.cantidad)                      as unidades,
  sum(d.cantidad * d.precio_unit)      as ingresos
from public.pedido_detalle d
join public.productos p  on p.id  = d.producto_id
join public.pedidos   pe on pe.id = d.pedido_id
group by p.vendedor_id, date_trunc('month', pe.fecha);

-- =====================================================================
--  Listo. El admin ya tiene control total y todo queda auditado.
-- =====================================================================
