-- =====================================================================
--  CompraYa - Base de datos (PostgreSQL / Supabase)
--  Pega TODO esto en el SQL Editor de Supabase y dale "Run".
--  Crea: tablas, permisos por rol (RLS) y el registro de auditoria.
-- =====================================================================

-- gen_random_uuid() ya viene en Supabase, pero por si acaso:
create extension if not exists pgcrypto;


-- =====================================================================
--  1) PERFILES  (los datos extra del usuario; la clave es el "rol")
--     El correo y la contraseña los maneja Supabase Auth por su lado.
-- =====================================================================
create table public.perfiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nombre      text not null,
  email       text,
  rol         text not null default 'comprador'
              check (rol in ('comprador','vendedor','admin')),
  creado      timestamptz not null default now()
);


-- =====================================================================
--  2) CATALOGO
-- =====================================================================
create table public.categorias (
  id      serial primary key,
  nombre  text not null,
  slug    text unique not null
);

create table public.productos (
  id              uuid primary key default gen_random_uuid(),
  vendedor_id     uuid not null references public.perfiles(id) on delete cascade,
  categoria_id    int  references public.categorias(id),
  titulo          text not null,
  descripcion     text,
  precio          numeric(10,2) not null check (precio >= 0),
  stock           int not null default 0 check (stock >= 0),
  devolucion      text,                       -- politica de devolucion (texto)
  fecha_entrega   text,                       -- entrega estimada (texto, va como "Proximamente")
  descuento       int default 0,              -- % de oferta, 0 = sin oferta
  estado          text not null default 'activo'
                  check (estado in ('activo','agotado','archivado')),
  creado          timestamptz not null default now()
);

create table public.producto_imagenes (
  id           uuid primary key default gen_random_uuid(),
  producto_id  uuid not null references public.productos(id) on delete cascade,
  url          text not null,
  orden        int default 0
);


-- =====================================================================
--  3) LO QUE VIVE EL COMPRADOR
-- =====================================================================
create table public.favoritos (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references public.perfiles(id) on delete cascade,
  producto_id  uuid not null references public.productos(id) on delete cascade,
  creado       timestamptz not null default now(),
  unique (usuario_id, producto_id)
);

-- "lo ultimo que viste"
create table public.vistos (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid not null references public.perfiles(id) on delete cascade,
  producto_id  uuid not null references public.productos(id) on delete cascade,
  fecha        timestamptz not null default now(),
  unique (usuario_id, producto_id)
);

create table public.cupones (
  id            serial primary key,
  codigo        text unique not null,
  descuento     int not null,                 -- % de descuento
  activo        boolean not null default true,
  valido_hasta  date
);

create table public.pedidos (
  id            uuid primary key default gen_random_uuid(),
  comprador_id  uuid not null references public.perfiles(id) on delete cascade,
  cupon_id      int references public.cupones(id),
  total         numeric(10,2) not null default 0,
  estado        text not null default 'pendiente'
                check (estado in ('pendiente','pagado','enviado','entregado','devuelto')),
  fecha         timestamptz not null default now()
);

create table public.pedido_detalle (
  id            uuid primary key default gen_random_uuid(),
  pedido_id     uuid not null references public.pedidos(id) on delete cascade,
  producto_id   uuid not null references public.productos(id),
  cantidad      int not null check (cantidad > 0),
  precio_unit   numeric(10,2) not null
);


-- =====================================================================
--  4) CHAT  (hablar con el vendedor -> queda archivado)
-- =====================================================================
create table public.conversaciones (
  id            uuid primary key default gen_random_uuid(),
  producto_id   uuid not null references public.productos(id) on delete cascade,
  comprador_id  uuid not null references public.perfiles(id) on delete cascade,
  vendedor_id   uuid references public.perfiles(id) on delete cascade, -- se llena solo
  archivada     boolean not null default false,
  creado        timestamptz not null default now()
);

create table public.mensajes (
  id               uuid primary key default gen_random_uuid(),
  conversacion_id  uuid not null references public.conversaciones(id) on delete cascade,
  emisor_id        uuid not null references public.perfiles(id) on delete cascade,
  texto            text not null,
  fecha            timestamptz not null default now()
);


-- =====================================================================
--  5) AUDITORIA  (lo que SOLO ven los admins: quien mueve que cosa)
-- =====================================================================
create table public.auditoria (
  id           uuid primary key default gen_random_uuid(),
  usuario_id   uuid references public.perfiles(id),
  accion       text not null,                 -- INSERT / UPDATE / DELETE / VENTA
  entidad      text not null,                 -- 'producto', 'pedido', etc.
  entidad_id   uuid,
  detalle      jsonb,
  fecha        timestamptz not null default now()
);


-- =====================================================================
--  6) FUNCIONES DE APOYO
-- =====================================================================

-- ¿el usuario actual es admin?
create or replace function public.es_admin()
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from public.perfiles
                 where id = auth.uid() and rol = 'admin');
$$;

-- Cuando alguien se registra en Auth, le creamos su perfil automaticamente.
-- OJO: el rol admin NO se puede auto-asignar; solo 'comprador' o 'vendedor'.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public as $$
declare v_rol text := coalesce(new.raw_user_meta_data->>'rol','comprador');
begin
  if v_rol not in ('comprador','vendedor') then
    v_rol := 'comprador';
  end if;
  insert into public.perfiles (id, nombre, email, rol)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)),
    new.email,
    v_rol
  );
  return new;
end; $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Nadie se sube de rol a la mala: si no eres admin, no puedes cambiar tu rol.
create or replace function public.guard_rol()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if new.rol is distinct from old.rol and not public.es_admin() then
    new.rol := old.rol;
  end if;
  return new;
end; $$;

create trigger trg_guard_rol
  before update on public.perfiles
  for each row execute function public.guard_rol();

-- Al abrir un chat, llenamos solo quien es el vendedor (dueño del producto).
create or replace function public.set_conv_vendedor()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  select vendedor_id into new.vendedor_id
  from public.productos where id = new.producto_id;
  return new;
end; $$;

create trigger trg_conv_vendedor
  before insert on public.conversaciones
  for each row execute function public.set_conv_vendedor();

-- AUDITORIA: cada movimiento de producto queda registrado.
create or replace function public.log_producto()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
  values (
    auth.uid(), tg_op, 'producto',
    coalesce(new.id, old.id),
    jsonb_build_object('titulo', coalesce(new.titulo, old.titulo))
  );
  return coalesce(new, old);
end; $$;

create trigger trg_log_producto
  after insert or update or delete on public.productos
  for each row execute function public.log_producto();

-- AUDITORIA: cada venta (pedido nuevo) queda registrada.
create or replace function public.log_pedido()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.auditoria (usuario_id, accion, entidad, entidad_id, detalle)
  values (auth.uid(), 'VENTA', 'pedido', new.id,
          jsonb_build_object('total', new.total));
  return new;
end; $$;

create trigger trg_log_pedido
  after insert on public.pedidos
  for each row execute function public.log_pedido();


-- =====================================================================
--  7) PERMISOS POR ROL (RLS)  - aqui se decide quien ve y toca que
-- =====================================================================
alter table public.perfiles          enable row level security;
alter table public.categorias        enable row level security;
alter table public.productos         enable row level security;
alter table public.producto_imagenes enable row level security;
alter table public.favoritos         enable row level security;
alter table public.vistos            enable row level security;
alter table public.cupones           enable row level security;
alter table public.pedidos           enable row level security;
alter table public.pedido_detalle    enable row level security;
alter table public.conversaciones    enable row level security;
alter table public.mensajes          enable row level security;
alter table public.auditoria         enable row level security;

-- ---- perfiles ----
create policy "perfiles_select" on public.perfiles for select
  using (id = auth.uid() or public.es_admin());
create policy "perfiles_update" on public.perfiles for update
  using (id = auth.uid() or public.es_admin())
  with check (id = auth.uid() or public.es_admin());

-- ---- categorias (todos leen, solo admin escribe) ----
create policy "cat_select" on public.categorias for select using (true);
create policy "cat_admin"  on public.categorias for all
  using (public.es_admin()) with check (public.es_admin());

-- ---- productos ----
-- Ven los activos cualquiera; el vendedor ve los suyos; el admin ve todo.
create policy "prod_select" on public.productos for select
  using (estado = 'activo' or vendedor_id = auth.uid() or public.es_admin());
-- Solo vendedores/admin crean, y a nombre propio.
create policy "prod_insert" on public.productos for insert
  with check (
    vendedor_id = auth.uid()
    and exists (select 1 from public.perfiles
                where id = auth.uid() and rol in ('vendedor','admin'))
  );
create policy "prod_update" on public.productos for update
  using (vendedor_id = auth.uid() or public.es_admin());
create policy "prod_delete" on public.productos for delete
  using (vendedor_id = auth.uid() or public.es_admin());

-- ---- imagenes de producto ----
create policy "img_select" on public.producto_imagenes for select
  using (exists (select 1 from public.productos p where p.id = producto_id
                 and (p.estado='activo' or p.vendedor_id=auth.uid() or public.es_admin())));
create policy "img_write" on public.producto_imagenes for all
  using (exists (select 1 from public.productos p where p.id = producto_id
                 and (p.vendedor_id=auth.uid() or public.es_admin())))
  with check (exists (select 1 from public.productos p where p.id = producto_id
                 and (p.vendedor_id=auth.uid() or public.es_admin())));

-- ---- favoritos (solo lo tuyo) ----
create policy "fav_select" on public.favoritos for select
  using (usuario_id = auth.uid() or public.es_admin());
create policy "fav_write" on public.favoritos for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---- vistos (solo lo tuyo) ----
create policy "vis_select" on public.vistos for select
  using (usuario_id = auth.uid() or public.es_admin());
create policy "vis_write" on public.vistos for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---- cupones (todos leen, admin escribe) ----
create policy "cup_select" on public.cupones for select using (true);
create policy "cup_admin"  on public.cupones for all
  using (public.es_admin()) with check (public.es_admin());

-- ---- pedidos (tus compras) ----
create policy "ped_select" on public.pedidos for select
  using (comprador_id = auth.uid() or public.es_admin());
create policy "ped_insert" on public.pedidos for insert
  with check (comprador_id = auth.uid());
create policy "ped_update" on public.pedidos for update
  using (comprador_id = auth.uid() or public.es_admin());

-- ---- detalle del pedido ----
-- Lo ve el comprador dueño, el admin, y el vendedor de ESE producto (sus ventas).
create policy "det_select" on public.pedido_detalle for select
  using (
    exists (select 1 from public.pedidos pe where pe.id = pedido_id and pe.comprador_id = auth.uid())
    or public.es_admin()
    or exists (select 1 from public.productos p where p.id = producto_id and p.vendedor_id = auth.uid())
  );
create policy "det_insert" on public.pedido_detalle for insert
  with check (exists (select 1 from public.pedidos pe
                      where pe.id = pedido_id and pe.comprador_id = auth.uid()));

-- ---- conversaciones (chat) ----
create policy "conv_select" on public.conversaciones for select
  using (comprador_id = auth.uid() or vendedor_id = auth.uid() or public.es_admin());
create policy "conv_insert" on public.conversaciones for insert
  with check (comprador_id = auth.uid());
create policy "conv_update" on public.conversaciones for update
  using (comprador_id = auth.uid() or vendedor_id = auth.uid() or public.es_admin());

-- ---- mensajes ----
create policy "msg_select" on public.mensajes for select
  using (exists (select 1 from public.conversaciones c where c.id = conversacion_id
                 and (c.comprador_id=auth.uid() or c.vendedor_id=auth.uid() or public.es_admin())));
create policy "msg_insert" on public.mensajes for insert
  with check (
    emisor_id = auth.uid()
    and exists (select 1 from public.conversaciones c where c.id = conversacion_id
                and (c.comprador_id=auth.uid() or c.vendedor_id=auth.uid()))
  );

-- ---- auditoria (SOLO admins leen; nadie escribe a mano, lo hacen los triggers) ----
create policy "aud_select" on public.auditoria for select
  using (public.es_admin());


-- =====================================================================
--  8) DATOS INICIALES (para que no arranque vacio)
-- =====================================================================
insert into public.categorias (nombre, slug) values
  ('Tecnología','tecnologia'),
  ('Gaming','gaming'),
  ('Moda','moda'),
  ('Hogar','hogar'),
  ('Belleza','belleza'),
  ('Deportes','deportes'),
  ('Juguetería','jugueteria'),
  ('Mascotas','mascotas');

insert into public.cupones (codigo, descuento, valido_hasta) values
  ('BIENVENIDO10', 10, '2026-12-31'),
  ('COMPRAYA15',   15, '2026-12-31');


-- =====================================================================
--  9) COMO CREAR EL PRIMER ADMIN
--     1. Registrate normal en la web (sale como comprador).
--     2. Vuelve a este SQL Editor y corre esto con TU correo:
--
--        update public.perfiles set rol = 'admin'
--        where email = 'tucorreo@sistemas.com';
--
--     Listo, ese correo ya es de administracion de sistemas.
-- =====================================================================
