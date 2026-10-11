-- =====================================================================
--  COLBily · instalación de la base (Supabase)
--  Toda tu plata en un solo lugar.
--
--  Cómo se usa:
--    1. Crea un proyecto NUEVO en supabase.com.
--    2. Abre SQL Editor → New query, pega TODO este archivo y toca Run.
--    3. Debe decir "Success. No rows returned".
--  Se corre una sola vez, en una base vacía. Si lo corres otra vez en una base
--  que ya tiene COLBily, falla al principio y no cambia nada (tus datos quedan iguales).
-- =====================================================================

-- ---------------------------------------------------------------------
--  MOVIMIENTOS
--  historico = true  ->  vino de un extracto del banco.
--                        No entra en los saldos actuales, solo en el
--                        historial y en plata_por_mes().
-- ---------------------------------------------------------------------
create table movimientos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null default current_date,
  cuenta text not null check (cuenta in ('TC','efectivo','bancolombia','nequi')),
  tipo text not null check (tipo in ('gasto','ingreso','pago_tc','traslado')),
  categoria text,
  monto numeric(12,2) not null check (monto > 0),
  nota text,
  cuenta_origen text check (cuenta_origen in ('efectivo','bancolombia','nequi')),
  historico boolean not null default false,
  -- cambio neto de la billetera por denominación. Ej: {"50000":-1,"2000":1}
  billetes jsonb,
  -- plata que se fue en monedas y no se guarda (el usuario solo guarda billetes)
  monedas numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  constraint movimientos_traslado_check
    check (tipo <> 'traslado' or cuenta_origen is distinct from cuenta)
);

comment on column movimientos.historico is
  'true = vino de los extractos del banco. No entra en los saldos actuales, solo en el historial.';

create index idx_movimientos_fecha     on movimientos (fecha);
create index idx_movimientos_cuenta    on movimientos (cuenta);
create index idx_movimientos_historico on movimientos (historico);

-- ---------------------------------------------------------------------
--  SALDOS Y CONFIGURACIÓN
--  saldos_iniciales -> desde dónde arranca lo que anota el usuario (hoy).
--  saldos_apertura  -> desde dónde arranca el historial de los extractos.
-- ---------------------------------------------------------------------
create table saldos_iniciales (
  cuenta text primary key check (cuenta in ('efectivo','bancolombia','nequi')),
  monto numeric(12,2) not null default 0,
  fecha date not null default current_date
);

insert into saldos_iniciales (cuenta, monto) values
  ('efectivo', 0), ('bancolombia', 0), ('nequi', 0);

create table saldos_apertura (
  cuenta text primary key check (cuenta in ('efectivo','bancolombia','nequi','TC')),
  fecha  date not null,
  monto  numeric(14,2) not null default 0
);

insert into saldos_apertura (cuenta, fecha, monto) values
  ('bancolombia','2025-12-31', 510890.20),
  ('nequi',      '2025-12-31',   4442.97),
  ('efectivo',   '2025-12-31',        0),
  ('TC',         '2025-12-31',        0);

-- ---------------------------------------------------------------------
--  BILLETERA
--  el usuario solo guarda billetes, nunca monedas. Esta tabla es la foto de
--  cuántos billetes hay; se vuelve a escribir desde Ajustes. La función
--  billetera() le suma los movimientos anotados después de esa foto.
--  Billetes en Colombia: 2.000 5.000 10.000 20.000 50.000 100.000
-- ---------------------------------------------------------------------
create table billetera_inicial (
  denominacion   int primary key
                 check (denominacion in (2000,5000,10000,20000,50000,100000)),
  cantidad       int not null default 0 check (cantidad >= 0),
  actualizado_en timestamptz not null default now()
);

insert into billetera_inicial (denominacion, cantidad) values
  (2000,0),(5000,0),(10000,0),(20000,0),(50000,0),(100000,0);

create table config (
  id int primary key default 1 check (id = 1),
  dia_corte_tc int not null default 15
);

insert into config (id, dia_corte_tc) values (1, 15);

-- ---------------------------------------------------------------------
--  CATEGORÍAS
-- ---------------------------------------------------------------------
create table categorias (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  tipo text not null check (tipo in ('gasto','ingreso')),
  icono text not null default '•',
  orden int not null default 99
);

insert into categorias (nombre, tipo, icono, orden) values
  ('Suscripciones','gasto','📺',1),
  ('Seguro moto','gasto','🛡️',2),
  ('Deuda moto','gasto','🏍️',3),
  ('Mantenimiento moto','gasto','🔧',4),
  ('Gasolina','gasto','⛽',5),
  ('Servicios casa','gasto','🏠',6),
  ('Cuota celular','gasto','📲',7),
  ('Gimnasio','gasto','🏋️',8),
  ('Mercado','gasto','🛒',9),
  ('Salud / Farmacia','gasto','💊',10),
  ('Transporte','gasto','🚕',11),
  ('Comida','gasto','🍽️',12),
  ('Software / IA','gasto','🤖',13),
  ('Juegos','gasto','🎮',14),
  ('Salidas','gasto','🍔',15),
  ('Motiladas','gasto','💈',16),
  ('Claro / datos','gasto','📱',17),
  ('Ajuste de cuadre','gasto','⚖️',98),
  ('Otro','gasto','✳️',99),
  ('Cobro suscripciones','ingreso','💸',1),
  ('Desarrollo de software','ingreso','💻',2),
  ('Nómina','ingreso','🧾',3),
  ('Trabajos sueltos','ingreso','🛠️',4),
  ('Préstamos que me pagan','ingreso','🤝',5),
  ('Trabajos para mis papás','ingreso','👨‍👩‍👦',6),
  ('Ventas','ingreso','🏷️',7),
  ('Regalos / bonos','ingreso','🎁',8),
  ('Reembolsos','ingreso','↩️',9),
  ('Otro ingreso','ingreso','✳️',99);

-- ---------------------------------------------------------------------
--  COBROS DE SUSCRIPCIONES
-- ---------------------------------------------------------------------
create table personas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  dia_cobro int not null default 1 check (dia_cobro between 1 and 28),
  activo boolean not null default true,
  orden int not null default 99,
  created_at timestamptz not null default now()
);

create table servicios_persona (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id) on delete cascade,
  servicio text not null,
  monto numeric(12,2) not null default 0
);
create index idx_serv_persona on servicios_persona(persona_id);

create table pagos_suscripcion (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id) on delete cascade,
  mes date not null,                                  -- primer día del mes
  monto numeric(12,2) not null,
  movimiento_id uuid references movimientos(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (persona_id, mes)
);
create index idx_pagos_mes on pagos_suscripcion(mes);

-- =====================================================================
--  VISTAS: cada movimiento partido en (fecha, cuenta, delta)
--  En cuentas de plata, delta > 0 = entra plata.
--  En la TC, delta > 0 = sube la deuda.
-- =====================================================================
create or replace view public.v_efectos as
  select fecha, cuenta,
         case when cuenta = 'TC'
              then case tipo when 'gasto' then monto when 'ingreso' then -monto else 0 end
              else case tipo when 'gasto' then -monto
                             when 'ingreso' then monto
                             when 'traslado' then monto
                             else 0 end
         end as delta
  from movimientos
  where tipo <> 'pago_tc'
union all
  select fecha, cuenta, -monto from movimientos where tipo = 'pago_tc'
union all
  select fecha, cuenta_origen, -monto
  from movimientos
  where cuenta_origen is not null and tipo in ('traslado','pago_tc')
union all
  -- lo que se fue en monedas también sale de la billetera
  select fecha, 'efectivo', -monedas from movimientos where monedas <> 0;

-- lo mismo pero SOLO con lo que anota el usuario (sin los extractos)
create or replace view public.v_efectos_propios as
  select fecha, cuenta,
         case when cuenta = 'TC'
              then case tipo when 'gasto' then monto when 'ingreso' then -monto else 0 end
              else case tipo when 'gasto' then -monto
                             when 'ingreso' then monto
                             when 'traslado' then monto
                             else 0 end
         end as delta
  from movimientos where tipo <> 'pago_tc' and not historico
union all
  select fecha, cuenta, -monto from movimientos where tipo = 'pago_tc' and not historico
union all
  select fecha, cuenta_origen, -monto from movimientos
  where cuenta_origen is not null and tipo in ('traslado','pago_tc') and not historico
union all
  select fecha, 'efectivo', -monedas from movimientos where monedas <> 0 and not historico;

-- saldo de cada cuenta, día por día, desde saldos_apertura
create or replace view public.v_saldos_diarios as
with cal as (
  select generate_series(
           (select min(fecha) from saldos_apertura),
           greatest(current_date, (select max(fecha) from movimientos)),
           interval '1 day')::date as fecha
),
ctas as (select cuenta, monto from saldos_apertura),
dia as (select fecha, cuenta, sum(delta) as delta from v_efectos group by 1,2)
select c.fecha,
       k.cuenta,
       k.monto + sum(coalesce(d.delta,0)) over (partition by k.cuenta order by c.fecha) as saldo
from cal c
cross join ctas k
left join dia d on d.fecha = c.fecha and d.cuenta = k.cuenta;

create or replace view public.v_plata_diaria as
select fecha,
       sum(saldo) filter (where cuenta <> 'TC') as plata,
       coalesce(max(saldo) filter (where cuenta = 'TC'), 0) as deuda_tc,
       coalesce(max(saldo) filter (where cuenta = 'efectivo'), 0) as efectivo,
       coalesce(max(saldo) filter (where cuenta = 'bancolombia'), 0) as bancolombia,
       coalesce(max(saldo) filter (where cuenta = 'nequi'), 0) as nequi
from v_saldos_diarios
group by fecha;

-- =====================================================================
--  PLATA POR MES — cuánta plata tuve, mi máximo, y qué entró y salió
-- =====================================================================
create or replace function public.plata_por_mes()
returns table (
  mes date, plata_max numeric, dia_del_max date, plata_min numeric,
  plata_fin numeric, plata_promedio numeric,
  entradas numeric, salidas numeric, neto numeric,
  efectivo_fin numeric, bancolombia_fin numeric, nequi_fin numeric,
  gastado_con_tc numeric, pagado_a_la_tc numeric, deuda_tc_fin numeric
)
language sql security definer set search_path = public as $$
with d as (select * from v_plata_diaria),
porm as (
  select date_trunc('month', fecha)::date as mes,
         max(plata) as plata_max, min(plata) as plata_min,
         round(avg(plata),2) as plata_promedio,
         (array_agg(plata       order by fecha desc))[1] as plata_fin,
         (array_agg(fecha       order by plata desc, fecha))[1] as dia_del_max,
         (array_agg(efectivo    order by fecha desc))[1] as efectivo_fin,
         (array_agg(bancolombia order by fecha desc))[1] as bancolombia_fin,
         (array_agg(nequi       order by fecha desc))[1] as nequi_fin,
         (array_agg(deuda_tc    order by fecha desc))[1] as deuda_tc_fin
  from d group by 1
),
flujo as (
  select date_trunc('month', fecha)::date as mes,
         coalesce(sum(monto) filter (where tipo='ingreso' and cuenta <> 'TC'
                                       and categoria is distinct from 'Ajuste de cuadre'),0) as entradas,
         coalesce(sum(monto) filter (where (tipo='gasto' and cuenta <> 'TC'
                                            and categoria is distinct from 'Ajuste de cuadre')
                                        or tipo='pago_tc'),0) as salidas,
         coalesce(sum(monto) filter (where tipo='gasto' and cuenta='TC'),0) as gastado_con_tc,
         coalesce(sum(monto) filter (where tipo='pago_tc'),0)               as pagado_a_la_tc
  from movimientos group by 1
)
select p.mes, p.plata_max, p.dia_del_max, p.plata_min, p.plata_fin, p.plata_promedio,
       coalesce(f.entradas,0), coalesce(f.salidas,0),
       coalesce(f.entradas,0) - coalesce(f.salidas,0),
       p.efectivo_fin, p.bancolombia_fin, p.nequi_fin,
       coalesce(f.gastado_con_tc,0), coalesce(f.pagado_a_la_tc,0), p.deuda_tc_fin
from porm p left join flujo f using (mes)
where p.mes >= date_trunc('month', (select min(fecha) from movimientos))
order by p.mes;
$$;

-- el día que más (y menos) plata tuve
create or replace function public.pico_plata()
returns table (resumen text)
language sql security definer set search_path = public as $$
  with m as (select fecha, plata from v_plata_diaria order by plata desc, fecha limit 1),
       h as (select fecha, plata from v_plata_diaria order by plata asc, fecha limit 1)
  select 'Máximo: $' || to_char((select plata from m),'FM999,999,999')
       || ' el ' || to_char((select fecha from m),'DD "de" TMMonth')
       || E'\nMínimo: $' || to_char((select plata from h),'FM999,999,999')
       || ' el ' || to_char((select fecha from h),'DD "de" TMMonth');
$$;

-- gastos por categoría de un mes ('2026-05-01' o null = mes actual)
create or replace function public.gastos_por_categoria(p_mes date default null)
returns table (categoria text, total numeric, veces bigint, porcentaje numeric)
language sql security definer set search_path = public as $$
  with base as (
    select coalesce(m.categoria,'Sin categoría') as cat, m.monto
    from movimientos m
    where m.tipo = 'gasto'
      and m.categoria is distinct from 'Ajuste de cuadre'
      and date_trunc('month', m.fecha) = date_trunc('month', coalesce(p_mes, current_date))
  )
  select cat, sum(monto), count(*),
         round(100 * sum(monto) / nullif((select sum(monto) from base),0), 1)
  from base group by cat order by 2 desc;
$$;

-- ---------------------------------------------------------------------
--  billetera() — cuántos billetes hay de cada uno, ahora mismo.
--  Arranca en la foto de billetera_inicial y le suma el campo `billetes`
--  de todo movimiento anotado después de esa foto.
-- ---------------------------------------------------------------------
create or replace function public.billetera()
returns table (denominacion int, cantidad int, subtotal numeric)
language plpgsql security definer set search_path = public as $$
declare v_ancla timestamptz;
begin
  select coalesce(max(actualizado_en), '-infinity'::timestamptz)
    into v_ancla from billetera_inicial;

  return query
  with denoms(d) as (values (2000),(5000),(10000),(20000),(50000),(100000)),
  base as (
    select dn.d as den, coalesce(bi.cantidad,0) as c
    from denoms dn left join billetera_inicial bi on bi.denominacion = dn.d
  ),
  cambios as (
    select kv.key::int as den, sum(kv.value::int) as c
    from movimientos m
    cross join lateral jsonb_each_text(m.billetes) kv
    where m.billetes is not null and not m.historico and m.created_at > v_ancla
    group by 1
  )
  select b.den,
         (b.c + coalesce(ch.c,0))::int,
         ((b.c + coalesce(ch.c,0)) * b.den)::numeric
  from base b left join cambios ch on ch.den = b.den
  order by b.den;
end;
$$;

-- ---------------------------------------------------------------------
--  SALDOS ACTUALES — la que consume el atajo del iPhone.
--  Solo cuenta lo que el usuario anota (historico = false).
-- ---------------------------------------------------------------------
create or replace function public.saldos()
returns table (resumen text)
language plpgsql security definer set search_path = public as $$
declare
  v_dia_corte int; v_fecha_corte date;
  v_ef numeric; v_ba numeric; v_ne numeric;
  v_tc_pend numeric; v_tc_corte numeric; v_tc_total numeric;
begin
  select dia_corte_tc into v_dia_corte from config where id = 1;
  v_fecha_corte := make_date(extract(year from current_date)::int,
                             extract(month from current_date)::int,
                             least(v_dia_corte, 28));
  if current_date < v_fecha_corte then
    v_fecha_corte := v_fecha_corte - interval '1 month';
  end if;

  select coalesce((select monto from saldos_iniciales where cuenta='efectivo'),0)
       + coalesce((select sum(delta) from v_efectos_propios where cuenta='efectivo'),0) into v_ef;
  select coalesce((select monto from saldos_iniciales where cuenta='bancolombia'),0)
       + coalesce((select sum(delta) from v_efectos_propios where cuenta='bancolombia'),0) into v_ba;
  select coalesce((select monto from saldos_iniciales where cuenta='nequi'),0)
       + coalesce((select sum(delta) from v_efectos_propios where cuenta='nequi'),0) into v_ne;
  select coalesce((select sum(delta) from v_efectos_propios where cuenta='TC'),0) into v_tc_pend;

  select coalesce(sum(monto),0) into v_tc_corte
  from movimientos
  where cuenta='TC' and tipo='gasto' and fecha >= v_fecha_corte and not historico;

  select coalesce((select saldo from v_saldos_diarios where cuenta='TC' order by fecha desc limit 1),0)
    into v_tc_total;

  return query select
    'Efectivo: $'    || to_char(v_ef,'FM999,999,999') || E'\n' ||
    'Bancolombia: $' || to_char(v_ba,'FM999,999,999') || E'\n' ||
    'Nequi: $'       || to_char(v_ne,'FM999,999,999') || E'\n' ||
    'Total: $'       || to_char(v_ef+v_ba+v_ne,'FM999,999,999') || E'\n\n' ||
    'TC anotada por ti: $'   || to_char(v_tc_pend,'FM999,999,999') || E'\n' ||
    'TC corte actual: $'     || to_char(v_tc_corte,'FM999,999,999') || E'\n' ||
    'TC real con extractos: $' || to_char(v_tc_total,'FM999,999,999');
end;
$$;

grant execute on function public.saldos()                    to anon;
grant execute on function public.billetera()                 to anon;
grant execute on function public.plata_por_mes()             to anon;
grant execute on function public.pico_plata()                to anon;
grant execute on function public.gastos_por_categoria(date)  to anon;
grant select on public.v_efectos, public.v_efectos_propios,
                public.v_saldos_diarios, public.v_plata_diaria to anon;

-- =====================================================================
--  MOVIMIENTOS, DATOS Y CATEGORÍAS (lo que usa el dashboard)
--  El navegador ya no baja todos los movimientos: los saldos, la
--  búsqueda y las gráficas se calculan aquí.
-- =====================================================================

-- quita tildes y pasa a minúscula, para buscar "almuerzo" = "Almuérzo"
create or replace function public.sin_tildes(t text)
returns text language sql immutable set search_path = public as $$
  select translate(lower(coalesce(t,'')), 'áéíóúüñàèìòùâêîôû', 'aeiouunaeiouaeiou');
$$;

-- ---------------------------------------------------------------------
--  saldos_actuales(hoy) — las tarjetas del inicio, en números.
--  Mismo cálculo que saldos() (solo lo anotado a mano, historico=false),
--  pero en columnas y con el "hoy" del teléfono para el corte de la TC.
-- ---------------------------------------------------------------------
create or replace function public.saldos_actuales(p_hoy date default null)
returns table (efectivo numeric, bancolombia numeric, nequi numeric, total numeric,
               tc_por_pagar numeric, tc_corte numeric, tc_real numeric, desde_corte date)
language plpgsql stable set search_path = public as $$
declare
  v_hoy date := coalesce(p_hoy, current_date);
  v_dc  int;
  v_fc  date;
begin
  select least(greatest(coalesce(c.dia_corte_tc, 15), 1), 28) into v_dc from config c where c.id = 1;
  v_fc := make_date(extract(year from v_hoy)::int, extract(month from v_hoy)::int, coalesce(v_dc, 15));
  if v_hoy < v_fc then v_fc := (v_fc - interval '1 month')::date; end if;

  return query
  with s as (
    select k.cta,
           coalesce((select si.monto from saldos_iniciales si where si.cuenta = k.cta), 0)
         + coalesce((select sum(e.delta) from v_efectos_propios e where e.cuenta = k.cta), 0) as saldo
    from unnest(array['efectivo','bancolombia','nequi','TC']) as k(cta)
  )
  select max(s.saldo) filter (where s.cta = 'efectivo'),
         max(s.saldo) filter (where s.cta = 'bancolombia'),
         max(s.saldo) filter (where s.cta = 'nequi'),
         sum(s.saldo) filter (where s.cta <> 'TC'),
         max(s.saldo) filter (where s.cta = 'TC'),
         (select coalesce(sum(m.monto), 0) from movimientos m
           where m.cuenta = 'TC' and m.tipo = 'gasto' and not m.historico and m.fecha >= v_fc),
         coalesce((select a.monto from saldos_apertura a where a.cuenta = 'TC'), 0)
         + coalesce((select sum(e.delta) from v_efectos e
                      where e.cuenta = 'TC' and e.fecha >= (select min(a.fecha) from saldos_apertura a)), 0),
         v_fc
  from s;
end;
$$;

-- ---------------------------------------------------------------------
--  buscar_movimientos(...) — la lista de Movimientos y su buscador.
--  Todos los filtros son opcionales (null = no filtra). Devuelve una
--  página (p_limite / p_offset; p_limite null = todos), el total que
--  coincide y la suma por tipo.
--  p_cuentas: 'efectivo','bancolombia','nequi','TC'. Un movimiento entra
--  si la cuenta es la de destino o la de origen (traslados, pagos TC).
--  p_texto busca en el resumen y en la categoría, sin tildes, y cada
--  palabra tiene que aparecer.
-- ---------------------------------------------------------------------
create or replace function public.buscar_movimientos(
  p_desde     date    default null,
  p_hasta     date    default null,
  p_tipos     text[]  default null,
  p_cuentas   text[]  default null,
  p_categoria text    default null,
  p_texto     text    default null,
  p_origen    text    default null,     -- 'mios' | 'extractos' | null = todos
  p_limite    int     default 5,
  p_offset    int     default 0)
returns jsonb
language sql stable set search_path = public as $$
  with f as (
    select m.*
    from movimientos m
    where (p_desde is null or m.fecha >= p_desde)
      and (p_hasta is null or m.fecha <= p_hasta)
      and (coalesce(cardinality(p_tipos), 0) = 0 or m.tipo = any(p_tipos))
      and (coalesce(cardinality(p_cuentas), 0) = 0
           or m.cuenta = any(p_cuentas) or m.cuenta_origen = any(p_cuentas))
      and (p_categoria is null or m.categoria = p_categoria)
      and (p_origen is null
           or (p_origen = 'mios' and not m.historico)
           or (p_origen = 'extractos' and m.historico))
      and (nullif(btrim(p_texto), '') is null or not exists (
            select 1
            from unnest(string_to_array(public.sin_tildes(btrim(p_texto)), ' ')) w
            where w <> ''
              and strpos(public.sin_tildes(coalesce(m.nota, '') || ' ' || coalesce(m.categoria, '')), w) = 0))
  ),
  pag as (
    select f.* from f
    order by f.fecha desc, f.created_at desc, f.id desc
    limit p_limite offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'total', (select count(*) from f),
    'sumas', (select coalesce(jsonb_object_agg(t.tipo, t.s), '{}'::jsonb)
                from (select f.tipo, sum(f.monto) as s from f group by f.tipo) t),
    'filas', coalesce((
      select jsonb_agg(
               to_jsonb(p) || jsonb_build_object('cobro_de',
                 (select pe.nombre from pagos_suscripcion ps
                    join personas pe on pe.id = ps.persona_id
                   where ps.movimiento_id = p.id limit 1))
               order by p.fecha desc, p.created_at desc, p.id desc)
      from pag p), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------
--  datos_periodo(desde, hasta) — todo lo que pintan las gráficas de un
--  mes o un año, ya agrupado. Incluye lo de los extractos (como
--  plata_por_mes). "Ajuste de cuadre" no cuenta como gasto ni ingreso.
--  entradas / salidas usan la misma regla que plata_por_mes():
--    entradas = ingresos a cuentas de plata
--    salidas  = gastos desde cuentas de plata + pagos a la TC
-- ---------------------------------------------------------------------
create or replace function public.datos_periodo(p_desde date, p_hasta date)
returns jsonb
language sql stable set search_path = public as $$
  with m as (select * from movimientos where fecha between p_desde and p_hasta),
  g as (select * from m where tipo = 'gasto'   and categoria is distinct from 'Ajuste de cuadre'),
  i as (select * from m where tipo = 'ingreso' and categoria is distinct from 'Ajuste de cuadre')
  select jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'resumen', jsonb_build_object(
      'entradas',       (select coalesce(sum(monto), 0) from i where cuenta <> 'TC'),
      'salidas',        (select coalesce(sum(monto), 0) from g where cuenta <> 'TC')
                      + (select coalesce(sum(monto), 0) from m where tipo = 'pago_tc'),
      'gastos',         (select coalesce(sum(monto), 0) from g),
      'ingresos',       (select coalesce(sum(monto), 0) from i),
      'gastado_con_tc', (select coalesce(sum(monto), 0) from g where cuenta = 'TC'),
      'pagado_a_la_tc', (select coalesce(sum(monto), 0) from m where tipo = 'pago_tc'),
      'traslados',      (select coalesce(sum(monto), 0) from m where tipo = 'traslado'),
      'movimientos',    (select count(*) from m),
      'n_gastos',       (select count(*) from g),
      'n_ingresos',     (select count(*) from i)
    ),
    'gasto_categorias', coalesce((
      select jsonb_agg(x order by x.total desc) from (
        select coalesce(categoria, 'Sin categoría') as categoria, sum(monto) as total, count(*) as veces
        from g group by 1) x), '[]'::jsonb),
    'ingreso_categorias', coalesce((
      select jsonb_agg(x order by x.total desc) from (
        select coalesce(categoria, 'Sin categoría') as categoria, sum(monto) as total, count(*) as veces
        from i group by 1) x), '[]'::jsonb),
    'gasto_cuentas', coalesce((
      select jsonb_agg(x order by x.total desc) from (
        select cuenta, sum(monto) as total, count(*) as veces from g group by 1) x), '[]'::jsonb),
    'por_dia', coalesce((
      select jsonb_agg(x order by x.fecha) from (
        select fecha,
               coalesce(sum(monto) filter (where tipo = 'gasto'   and categoria is distinct from 'Ajuste de cuadre'), 0) as gastos,
               coalesce(sum(monto) filter (where tipo = 'ingreso' and categoria is distinct from 'Ajuste de cuadre'), 0) as ingresos
        from m group by fecha) x), '[]'::jsonb),
    'por_mes', coalesce((
      select jsonb_agg(x order by x.mes) from (
        select date_trunc('month', fecha)::date as mes,
               coalesce(sum(monto) filter (where tipo = 'gasto'   and categoria is distinct from 'Ajuste de cuadre'), 0) as gastos,
               coalesce(sum(monto) filter (where tipo = 'ingreso' and categoria is distinct from 'Ajuste de cuadre'), 0) as ingresos,
               coalesce(sum(monto) filter (where tipo = 'ingreso' and cuenta <> 'TC' and categoria is distinct from 'Ajuste de cuadre'), 0) as entradas,
               coalesce(sum(monto) filter (where (tipo = 'gasto' and cuenta <> 'TC' and categoria is distinct from 'Ajuste de cuadre')
                                               or tipo = 'pago_tc'), 0) as salidas
        from m group by 1) x), '[]'::jsonb),
    'dia_semana', coalesce((
      select jsonb_agg(x order by x.dow) from (
        select extract(isodow from fecha)::int as dow, sum(monto) as total, count(*) as veces
        from g group by 1) x), '[]'::jsonb),
    'top_gastos', coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select id, fecha, cuenta, categoria, nota, monto, historico
        from g order by monto desc, fecha desc limit 5) x), '[]'::jsonb),
    'saldo_diario', coalesce((
      select jsonb_agg(x order by x.fecha) from (
        select fecha, plata, deuda_tc from v_plata_diaria
        where fecha between p_desde and p_hasta) x), '[]'::jsonb)
  );
$$;

-- gasto por categoría de cada mes (para "categorías mes a mes")
create or replace function public.gastos_categoria_por_mes()
returns table (mes date, categoria text, total numeric)
language sql stable set search_path = public as $$
  select date_trunc('month', fecha)::date, coalesce(categoria, 'Sin categoría'), sum(monto)
  from movimientos
  where tipo = 'gasto' and categoria is distinct from 'Ajuste de cuadre'
  group by 1, 2
  order by 1, 3 desc;
$$;

-- =====================================================================
--  CATEGORÍAS: crear, editar, ordenar y borrar
--  movimientos.categoria guarda el NOMBRE, así que renombrar actualiza
--  también los movimientos. "Ajuste de cuadre" y "Cobro suscripciones"
--  los usa la app por dentro: no se renombran ni se borran.
-- =====================================================================
create or replace function public.categorias_uso()
returns table (id uuid, nombre text, tipo text, icono text, orden int, usos bigint)
language sql stable set search_path = public as $$
  select c.id, c.nombre, c.tipo, c.icono, c.orden,
         (select count(*) from movimientos m where m.categoria = c.nombre)
  from categorias c
  order by c.tipo, c.orden, c.nombre;
$$;

create or replace function public.guardar_categoria(
  p_id uuid, p_nombre text, p_tipo text, p_icono text)
returns jsonb
language plpgsql set search_path = public as $$
declare
  v_old    categorias;
  v_new    categorias;
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_icono  text := coalesce(nullif(btrim(coalesce(p_icono, '')), ''), '•');
  v_usos   bigint;
  v_orden  int;
begin
  if v_nombre = '' then raise exception 'La categoría necesita un nombre'; end if;
  if length(v_nombre) > 40 then raise exception 'El nombre es muy largo (máximo 40 letras)'; end if;
  if p_tipo is null or p_tipo not in ('gasto', 'ingreso') then raise exception 'El tipo tiene que ser gasto o ingreso'; end if;
  if exists (select 1 from categorias c where lower(c.nombre) = lower(v_nombre) and c.id is distinct from p_id) then
    raise exception 'Ya existe una categoría llamada "%"', v_nombre;
  end if;

  if p_id is null then
    select coalesce(max(c.orden), 0) + 1 into v_orden
    from categorias c
    where c.tipo = p_tipo and c.nombre not in ('Otro', 'Otro ingreso', 'Ajuste de cuadre');
    insert into categorias (nombre, tipo, icono, orden)
    values (v_nombre, p_tipo, v_icono, v_orden)
    returning * into v_new;
    -- "Otro" / "Otro ingreso" siguen de últimas
    update categorias c set orden = v_orden + 1
    where c.tipo = p_tipo and c.nombre in ('Otro', 'Otro ingreso') and c.orden <= v_orden;
    return to_jsonb(v_new);
  end if;

  select * into v_old from categorias c where c.id = p_id for update;
  if not found then raise exception 'Esa categoría ya no existe'; end if;
  if v_old.nombre in ('Ajuste de cuadre', 'Cobro suscripciones')
     and (v_nombre <> v_old.nombre or p_tipo <> v_old.tipo) then
    raise exception '"%" la usa la app por dentro: solo se le puede cambiar el ícono', v_old.nombre;
  end if;
  select count(*) into v_usos from movimientos m where m.categoria = v_old.nombre;
  if p_tipo <> v_old.tipo and v_usos > 0 then
    raise exception 'No se puede pasar de % a % porque ya tiene % movimientos', v_old.tipo, p_tipo, v_usos;
  end if;

  update categorias c set nombre = v_nombre, tipo = p_tipo, icono = v_icono
  where c.id = p_id returning * into v_new;
  if v_nombre <> v_old.nombre then
    update movimientos m set categoria = v_nombre where m.categoria = v_old.nombre;
  end if;
  return to_jsonb(v_new) || jsonb_build_object('usos', v_usos);
end;
$$;

create or replace function public.borrar_categoria(p_id uuid, p_mover_a text default null)
returns integer                 -- cuántos movimientos se pasaron a la otra categoría
language plpgsql set search_path = public as $$
declare
  v      categorias;
  v_dest categorias;
  v_n    int;
begin
  select * into v from categorias c where c.id = p_id for update;
  if not found then raise exception 'Esa categoría ya no existe'; end if;
  if v.nombre in ('Ajuste de cuadre', 'Cobro suscripciones') then
    raise exception '"%" la usa la app por dentro y no se puede borrar', v.nombre;
  end if;
  if (select count(*) from categorias c where c.tipo = v.tipo) <= 1 then
    raise exception 'Tiene que quedar al menos una categoría de %', v.tipo;
  end if;

  select count(*) into v_n from movimientos m where m.categoria = v.nombre;
  if v_n > 0 then
    if p_mover_a is null then
      raise exception 'Tiene % movimientos: escoge a qué categoría pasarlos', v_n;
    end if;
    select * into v_dest from categorias c where c.nombre = p_mover_a;
    if not found or v_dest.id = v.id then
      raise exception 'Escoge otra categoría para pasar los movimientos';
    end if;
    if v_dest.tipo <> v.tipo then
      raise exception 'Los movimientos tienen que pasar a una categoría de %', v.tipo;
    end if;
    update movimientos m set categoria = v_dest.nombre where m.categoria = v.nombre;
  end if;

  delete from categorias c where c.id = p_id;
  return v_n;
end;
$$;

-- guarda el orden: el primero del arreglo queda de primero
create or replace function public.ordenar_categorias(p_ids uuid[])
returns void
language sql set search_path = public as $$
  update categorias c set orden = x.i
  from unnest(p_ids) with ordinality as x(id, i)
  where c.id = x.id;
$$;

grant execute on function public.sin_tildes(text)                          to anon;
grant execute on function public.saldos_actuales(date)                     to anon;
grant execute on function public.buscar_movimientos(date, date, text[], text[], text, text, text, int, int) to anon;
grant execute on function public.datos_periodo(date, date)                 to anon;
grant execute on function public.gastos_categoria_por_mes()                to anon;
grant execute on function public.categorias_uso()                          to anon;
grant execute on function public.guardar_categoria(uuid, text, text, text) to anon;
grant execute on function public.borrar_categoria(uuid, text)              to anon;
grant execute on function public.ordenar_categorias(uuid[])                to anon;

-- =====================================================================
--  MONEDAS, COMPRAS A CUOTAS CON LA TC Y COBROS POR MES (septiembre 2026)
--  Va después de todo lo anterior: agrega columnas y reemplaza vistas y
--  funciones (saldos_actuales, saldos) con la versión que usa el dashboard.
-- =====================================================================

-- ---------- MOVIMIENTOS: monedas y cuotas ----------
alter table public.movimientos
  add column if not exists monedas_det  jsonb,
  add column if not exists cuotas       int           check (cuotas between 1 and 72),
  add column if not exists cuota_valor  numeric(14,2) check (cuota_valor > 0),
  add column if not exists tasa_mensual numeric(9,4)  check (tasa_mensual >= 0);

comment on column public.movimientos.monedas is
  'Monedas recibidas − monedas entregadas (el usuario no guarda monedas: no entran a la billetera). '
  'Positivo = se fue plata en monedas; negativo = se pagó con monedas que no estaban en la billetera.';
comment on column public.movimientos.monedas_det is
  'Monedas por denominación, cuando se dijeron una por una. Ej: {"1000":-2} = entregué 2 de $1.000';
comment on column public.movimientos.cuotas is
  'Compras con la TC: a cuántas cuotas. null o 1 = una sola, sin intereses.';
comment on column public.movimientos.cuota_valor is
  'Valor de cada cuota (capital + intereses) cuando cuotas > 1.';
comment on column public.movimientos.tasa_mensual is
  'Tasa de interés mensual (%) de la compra a cuotas.';

-- lo que suma a la deuda de la TC una compra: con cuotas, lo que se termina pagando
create or replace view public.v_efectos as
  select fecha, cuenta,
         case when cuenta = 'TC'
              then case tipo when 'gasto' then case when coalesce(cuotas, 1) > 1 and cuota_valor is not null
                                                    then cuota_valor * cuotas else monto end
                             when 'ingreso' then -monto else 0 end
              else case tipo when 'gasto' then -monto
                             when 'ingreso' then monto
                             when 'traslado' then monto
                             else 0 end
         end as delta
  from movimientos
  where tipo <> 'pago_tc'
union all
  select fecha, cuenta, -monto from movimientos where tipo = 'pago_tc'
union all
  select fecha, cuenta_origen, -monto
  from movimientos
  where cuenta_origen is not null and tipo in ('traslado','pago_tc')
union all
  -- monedas: las que se van restan, las que se usaron para pagar no salieron de la billetera
  select fecha, 'efectivo', -monedas from movimientos where monedas <> 0;

create or replace view public.v_efectos_propios as
  select fecha, cuenta,
         case when cuenta = 'TC'
              then case tipo when 'gasto' then case when coalesce(cuotas, 1) > 1 and cuota_valor is not null
                                                    then cuota_valor * cuotas else monto end
                             when 'ingreso' then -monto else 0 end
              else case tipo when 'gasto' then -monto
                             when 'ingreso' then monto
                             when 'traslado' then monto
                             else 0 end
         end as delta
  from movimientos where tipo <> 'pago_tc' and not historico
union all
  select fecha, cuenta, -monto from movimientos where tipo = 'pago_tc' and not historico
union all
  select fecha, cuenta_origen, -monto from movimientos
  where cuenta_origen is not null and tipo in ('traslado','pago_tc') and not historico
union all
  select fecha, 'efectivo', -monedas from movimientos where monedas <> 0 and not historico;

-- ---------- TARJETA: cortes ----------
-- el corte en el que cae una fecha: el día de corte de ese mes si ya llegó, si no el del mes anterior
create or replace function public.tc_periodo(p_fecha date, p_dia int)
returns date language sql immutable set search_path = public as $$
  select case when p_fecha >= make_date(extract(year from p_fecha)::int, extract(month from p_fecha)::int, p_dia)
              then make_date(extract(year from p_fecha)::int, extract(month from p_fecha)::int, p_dia)
              else (make_date(extract(year from p_fecha)::int, extract(month from p_fecha)::int, p_dia)
                    - interval '1 month')::date end;
$$;

-- cada cobro de la TC en el corte en que se factura: una compra a 3 cuotas son
-- 3 cobros de "cuota_valor" en 3 cortes seguidos; a 1 cuota, el monto completo.
create or replace function public.tc_cargos(p_dia int)
returns table (periodo date, valor numeric, movimiento_id uuid, cuota int)
language sql stable set search_path = public as $$
  select (public.tc_periodo(m.fecha, p_dia) + make_interval(months => k.k))::date,
         case when coalesce(m.cuotas, 1) > 1
              then coalesce(m.cuota_valor, round(m.monto / m.cuotas, 2)) else m.monto end,
         m.id, k.k + 1
  from movimientos m
  cross join lateral generate_series(0, coalesce(m.cuotas, 1) - 1) as k(k)
  where m.cuenta = 'TC' and m.tipo = 'gasto' and not m.historico
  union all
  select public.tc_periodo(m.fecha, p_dia), -m.monto, m.id, 1
  from movimientos m
  where m.cuenta = 'TC' and m.tipo = 'ingreso' and not m.historico;
$$;

-- ---------------------------------------------------------------------
--  saldos_actuales(hoy) — las tarjetas del inicio.
--  TC:  corte anterior = lo facturado en cortes que ya cerraron − lo pagado
--       corte actual   = lo que se factura en el corte que va corriendo
--                        (compras de ahora + cuotas de compras viejas)
--       total a pagar  = los dos juntos
--       cuotas futuras = cuotas que caen en cortes que todavía no empiezan
-- ---------------------------------------------------------------------
drop function if exists public.saldos_actuales(date);
create function public.saldos_actuales(p_hoy date default null)
returns table (efectivo numeric, bancolombia numeric, nequi numeric, total numeric,
               tc_corte_anterior numeric, tc_corte_actual numeric, tc_total_pagar numeric,
               tc_cuotas_futuras numeric, tc_deuda_total numeric,
               corte_desde date, corte_hasta date)
language plpgsql stable set search_path = public as $$
declare
  v_hoy date := coalesce(p_hoy, (now() at time zone 'America/Bogota')::date);
  v_dc  int;
  v_c0  date;
  v_ant numeric; v_act numeric; v_fut numeric; v_pag numeric; v_resta numeric;
begin
  select least(greatest(coalesce(c.dia_corte_tc, 15), 1), 28) into v_dc from config c where c.id = 1;
  v_dc := coalesce(v_dc, 15);
  v_c0 := public.tc_periodo(v_hoy, v_dc);

  select coalesce(sum(c.valor) filter (where c.periodo <  v_c0), 0),
         coalesce(sum(c.valor) filter (where c.periodo =  v_c0), 0),
         coalesce(sum(c.valor) filter (where c.periodo >  v_c0), 0)
    into v_ant, v_act, v_fut
  from public.tc_cargos(v_dc) c;
  select coalesce(sum(m.monto), 0) into v_pag
  from movimientos m where m.tipo = 'pago_tc' and not m.historico;

  -- lo pagado (y las devoluciones) cubre primero lo más viejo: lo que queda se reparte
  -- desde lo más nuevo (cuotas futuras, luego el corte actual) y el resto es del corte anterior
  v_resta := greatest(v_ant + v_act + v_fut - v_pag, 0);
  v_fut   := least(greatest(v_fut, 0), v_resta);
  v_act   := least(greatest(v_act, 0), v_resta - v_fut);
  v_ant   := v_resta - v_fut - v_act;

  return query
  with s as (
    select k.cta,
           coalesce((select si.monto from saldos_iniciales si where si.cuenta = k.cta), 0)
         + coalesce((select sum(e.delta) from v_efectos_propios e where e.cuenta = k.cta), 0) as saldo
    from unnest(array['efectivo','bancolombia','nequi','TC']) as k(cta)
  )
  select max(s.saldo) filter (where s.cta = 'efectivo'),
         max(s.saldo) filter (where s.cta = 'bancolombia'),
         max(s.saldo) filter (where s.cta = 'nequi'),
         sum(s.saldo) filter (where s.cta <> 'TC'),
         v_ant, v_act, v_ant + v_act, v_fut,
         max(s.saldo) filter (where s.cta = 'TC'),
         v_c0, (v_c0 + interval '1 month')::date
  from s;
end;
$$;

-- el texto del atajo del iPhone, con los mismos números del dashboard
create or replace function public.saldos()
returns table (resumen text)
language sql stable security definer set search_path = public as $$
  select 'Efectivo: $'    || to_char(s.efectivo,'FM999,999,999') || E'\n' ||
         'Bancolombia: $' || to_char(s.bancolombia,'FM999,999,999') || E'\n' ||
         'Nequi: $'       || to_char(s.nequi,'FM999,999,999') || E'\n' ||
         'Total: $'       || to_char(s.total,'FM999,999,999') || E'\n\n' ||
         'TC corte anterior: $' || to_char(s.tc_corte_anterior,'FM999,999,990') || E'\n' ||
         'TC corte actual: $'   || to_char(s.tc_corte_actual,'FM999,999,990') || E'\n' ||
         'TC total a pagar: $'  || to_char(s.tc_total_pagar,'FM999,999,990')
  from public.saldos_actuales() s;
$$;

-- ---------- COBROS: historial por mes ----------
-- desde_mes: desde qué mes aparece (null = siempre). baja_mes: desde qué mes ya no.
alter table public.personas
  add column if not exists desde_mes date,
  add column if not exists baja_mes  date;
-- cada versión de lo que paga una persona vale desde desde_mes hasta antes de hasta_mes
alter table public.servicios_persona
  add column if not exists desde_mes date not null default '2000-01-01',
  add column if not exists hasta_mes date;
create index if not exists idx_pagos_movimiento on public.pagos_suscripcion(movimiento_id);
-- las que ya estaban inactivas no vuelven a aparecer de aquí en adelante
update public.personas set baja_mes = date_trunc('month', current_date)::date
where not activo and baja_mes is null;

-- guarda una persona; si cambian sus servicios o montos, el cambio vale desde
-- p_desde (primer día del mes) en adelante y los meses anteriores quedan igual
create or replace function public.guardar_persona(
  p_id uuid, p_nombre text, p_dia int, p_desde date, p_servicios jsonb)
returns uuid
language plpgsql set search_path = public as $$
declare
  v_id     uuid := p_id;
  v_desde  date := date_trunc('month', coalesce(p_desde, current_date))::date;
  v_dia    int  := least(greatest(coalesce(p_dia, 1), 1), 28);
  v_actual jsonb;
  v_nuevo  jsonb;
  v_hasta  date;
begin
  if btrim(coalesce(p_nombre, '')) = '' then raise exception 'Ponle un nombre'; end if;
  if v_id is null then
    insert into personas (nombre, dia_cobro, desde_mes, orden)
    values (btrim(p_nombre), v_dia, v_desde, coalesce((select max(orden) from personas), 0) + 1)
    returning id into v_id;
  else
    update personas set nombre = btrim(p_nombre), dia_cobro = v_dia where id = v_id;
    if not found then raise exception 'Esa persona ya no existe'; end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('s', s.servicio, 'm', s.monto::numeric)
                            order by s.servicio, s.monto), '[]'::jsonb)
    into v_actual
  from servicios_persona s
  where s.persona_id = v_id and s.desde_mes <= v_desde and (s.hasta_mes is null or s.hasta_mes > v_desde);

  select coalesce(jsonb_agg(jsonb_build_object('s', x.s, 'm', x.m) order by x.s, x.m), '[]'::jsonb)
    into v_nuevo
  from (select btrim(e->>'servicio') as s, coalesce((e->>'monto')::numeric, 0) as m
        from jsonb_array_elements(coalesce(p_servicios, '[]'::jsonb)) e
        where btrim(coalesce(e->>'servicio', '')) <> '') x;

  if v_actual = v_nuevo then return v_id; end if;       -- no cambió lo que paga

  -- el cambio vale desde v_desde hasta que empiece el próximo cambio que ya estuviera anotado
  select min(s.desde_mes) into v_hasta from servicios_persona s
  where s.persona_id = v_id and s.desde_mes > v_desde;
  delete from servicios_persona where persona_id = v_id and desde_mes = v_desde;
  update servicios_persona set hasta_mes = v_desde
  where persona_id = v_id and desde_mes < v_desde and (hasta_mes is null or hasta_mes > v_desde);
  insert into servicios_persona (persona_id, servicio, monto, desde_mes, hasta_mes)
  select v_id, x->>'s', (x->>'m')::numeric, v_desde, v_hasta from jsonb_array_elements(v_nuevo) x;
  return v_id;
end;
$$;

grant execute on function public.tc_periodo(date, int)                   to anon;
grant execute on function public.tc_cargos(int)                          to anon;
grant execute on function public.saldos_actuales(date)                   to anon;
grant execute on function public.saldos()                                to anon;
grant execute on function public.guardar_persona(uuid, text, int, date, jsonb) to anon;

-- =====================================================================
--  CUENTAS Y TARJETAS DINÁMICAS + PAPELERA (octubre 2026)
--  Cuentas y tarjetas que se crean, renombran y van a la papelera.
--  Categorías a la papelera sin tocar los movimientos.
--  Los movimientos guardan el id de la cuenta: renombrar cambia el nombre en
--  todos los movimientos solo, y borrar (papelera) no toca ninguno.
--  Las cuentas de siempre conservan su id (efectivo, bancolombia, nequi, TC)
--  para que el atajo del iPhone siga funcionando igual.
-- =====================================================================

-- ---------- CUENTAS ----------
create table if not exists public.cuentas (
  id         text primary key,
  nombre     text not null,
  tipo       text not null check (tipo in ('efectivo', 'virtual', 'tarjeta')),
  dia_corte  int  check (dia_corte between 1 and 28),     -- solo tarjetas
  color      text not null default '#3B9EFF',
  orden      int  not null default 99,
  borrada_en timestamptz,                                  -- no null = en la papelera
  creada_en  timestamptz not null default now(),
  constraint cuentas_tarjeta_con_corte check (tipo <> 'tarjeta' or dia_corte is not null)
);
create unique index if not exists cuentas_nombre_unico on public.cuentas (lower(nombre));
alter table public.cuentas drop constraint if exists cuentas_color_hex;
alter table public.cuentas add constraint cuentas_color_hex check (color ~ '^#[0-9A-Fa-f]{6}$');
comment on table public.cuentas is
  'Billeteras/cuentas (efectivo = con billetes; virtual = banco, Nequi…) y tarjetas de crédito.';

insert into public.cuentas (id, nombre, tipo, dia_corte, color, orden) values
  ('efectivo',    'Efectivo',           'efectivo', null, '#34D399', 1),
  ('bancolombia', 'Bancolombia',        'virtual',  null, '#3B9EFF', 2),
  ('nequi',       'Nequi',              'virtual',  null, '#E5257A', 3),
  ('TC',          'Tarjeta de crédito', 'tarjeta',
     (select least(greatest(coalesce(c.dia_corte_tc, 15), 1), 28) from public.config c where c.id = 1),
     '#8B5CF6', 10)
on conflict (id) do nothing;

alter table public.cuentas enable row level security;
drop policy if exists "todo_cuentas" on public.cuentas;
create policy "todo_cuentas" on public.cuentas for all using (true) with check (true);
grant select, insert, update, delete on public.cuentas to anon;

-- de lista fija a llave hacia cuentas
alter table public.movimientos drop constraint if exists movimientos_cuenta_check;
alter table public.movimientos drop constraint if exists movimientos_cuenta_origen_check;
alter table public.movimientos drop constraint if exists movimientos_cuenta_fk;
alter table public.movimientos drop constraint if exists movimientos_cuenta_origen_fk;
alter table public.movimientos
  add constraint movimientos_cuenta_fk        foreign key (cuenta)        references public.cuentas(id) on update cascade,
  add constraint movimientos_cuenta_origen_fk foreign key (cuenta_origen) references public.cuentas(id) on update cascade;
create index if not exists idx_movimientos_cuenta_origen on public.movimientos (cuenta_origen);

alter table public.saldos_iniciales drop constraint if exists saldos_iniciales_cuenta_check;
alter table public.saldos_iniciales drop constraint if exists saldos_iniciales_cuenta_fk;
alter table public.saldos_iniciales
  add constraint saldos_iniciales_cuenta_fk foreign key (cuenta) references public.cuentas(id) on update cascade on delete cascade;
alter table public.saldos_apertura drop constraint if exists saldos_apertura_cuenta_check;
alter table public.saldos_apertura drop constraint if exists saldos_apertura_cuenta_fk;
alter table public.saldos_apertura
  add constraint saldos_apertura_cuenta_fk foreign key (cuenta) references public.cuentas(id) on update cascade on delete cascade;

-- cada cuenta en efectivo tiene sus propios billetes
alter table public.billetera_inicial
  add column if not exists cuenta text not null default 'efectivo'
    references public.cuentas(id) on update cascade on delete cascade;
alter table public.billetera_inicial drop constraint if exists billetera_inicial_pkey;
alter table public.billetera_inicial add constraint billetera_inicial_pkey primary key (cuenta, denominacion);

-- la cuenta en efectivo a la que le tocan los billetes y monedas de un movimiento:
-- la de origen si es en efectivo; si no, la de destino
create or replace function public.caja_de(p_cuenta text, p_origen text)
returns text language sql stable set search_path = public as $$
  select case when exists (select 1 from cuentas k where k.id = p_origen and k.tipo = 'efectivo')
              then p_origen else p_cuenta end;
$$;

-- ---------- EFECTOS: cuánto mueve cada movimiento en cada cuenta ----------
-- en una tarjeta, delta > 0 = sube la deuda (con cuotas, lo que se termina pagando)
create or replace view public.v_efectos as
  select m.fecha, m.cuenta,
         case when k.tipo = 'tarjeta'
              then case m.tipo when 'gasto' then case when coalesce(m.cuotas, 1) > 1 and m.cuota_valor is not null
                                                      then m.cuota_valor * m.cuotas else m.monto end
                               when 'ingreso' then -m.monto else 0 end
              else case m.tipo when 'gasto' then -m.monto
                               when 'ingreso' then m.monto
                               when 'traslado' then m.monto
                               else 0 end
         end as delta
  from movimientos m join cuentas k on k.id = m.cuenta
  where m.tipo <> 'pago_tc'
union all
  select fecha, cuenta, -monto from movimientos where tipo = 'pago_tc'
union all
  select fecha, cuenta_origen, -monto
  from movimientos
  where cuenta_origen is not null and tipo in ('traslado','pago_tc')
union all
  -- monedas: las que se van restan, las que se usaron para pagar no salieron de la billetera
  select m.fecha, public.caja_de(m.cuenta, m.cuenta_origen), -m.monedas from movimientos m where m.monedas <> 0;

create or replace view public.v_efectos_propios as
  select m.fecha, m.cuenta,
         case when k.tipo = 'tarjeta'
              then case m.tipo when 'gasto' then case when coalesce(m.cuotas, 1) > 1 and m.cuota_valor is not null
                                                      then m.cuota_valor * m.cuotas else m.monto end
                               when 'ingreso' then -m.monto else 0 end
              else case m.tipo when 'gasto' then -m.monto
                               when 'ingreso' then m.monto
                               when 'traslado' then m.monto
                               else 0 end
         end as delta
  from movimientos m join cuentas k on k.id = m.cuenta
  where m.tipo <> 'pago_tc' and not m.historico
union all
  select fecha, cuenta, -monto from movimientos where tipo = 'pago_tc' and not historico
union all
  select fecha, cuenta_origen, -monto from movimientos
  where cuenta_origen is not null and tipo in ('traslado','pago_tc') and not historico
union all
  select m.fecha, public.caja_de(m.cuenta, m.cuenta_origen), -m.monedas
  from movimientos m where m.monedas <> 0 and not m.historico;

-- saldo de cada cuenta (todas, también las nuevas) día por día
create or replace view public.v_saldos_diarios as
with cal as (
  select generate_series(
           (select min(fecha) from saldos_apertura),
           greatest(current_date, (select max(fecha) from movimientos)),
           interval '1 day')::date as fecha
),
ctas as (select k.id as cuenta, coalesce(a.monto, 0) as monto
         from cuentas k left join saldos_apertura a on a.cuenta = k.id),
dia as (select fecha, cuenta, sum(delta) as delta from (
          select fecha, cuenta, delta from v_efectos
          union all
          -- las cuentas nuevas (sin saldo de apertura) arrancan el día que se crearon, con su saldo inicial
          select (k.creada_en at time zone 'America/Bogota')::date, k.id, si.monto
          from cuentas k join saldos_iniciales si on si.cuenta = k.id
          where not exists (select 1 from saldos_apertura a where a.cuenta = k.id)
        ) e group by 1,2)
select c.fecha,
       k.cuenta,
       k.monto + sum(coalesce(d.delta,0)) over (partition by k.cuenta order by c.fecha) as saldo
from cal c
cross join ctas k
left join dia d on d.fecha = c.fecha and d.cuenta = k.cuenta;

create or replace view public.v_plata_diaria as
select s.fecha,
       sum(s.saldo) filter (where k.tipo <> 'tarjeta') as plata,
       coalesce(sum(s.saldo) filter (where k.tipo = 'tarjeta'), 0) as deuda_tc,
       coalesce(max(s.saldo) filter (where s.cuenta = 'efectivo'), 0) as efectivo,
       coalesce(max(s.saldo) filter (where s.cuenta = 'bancolombia'), 0) as bancolombia,
       coalesce(max(s.saldo) filter (where s.cuenta = 'nequi'), 0) as nequi
from v_saldos_diarios s join cuentas k on k.id = s.cuenta
group by s.fecha;

-- con qué cerró cada cuenta cada mes (para "plata por cuenta" con cualquier cuenta)
create or replace function public.saldos_por_mes()
returns table (mes date, cuenta text, saldo_fin numeric)
language sql stable set search_path = public as $$
  select date_trunc('month', s.fecha)::date,
         s.cuenta,
         (array_agg(s.saldo order by s.fecha desc))[1]
  from v_saldos_diarios s
  where s.fecha >= date_trunc('month', (select min(fecha) from movimientos))
  group by 1, 2
  order by 1, 2;
$$;

create or replace function public.plata_por_mes()
returns table (
  mes date, plata_max numeric, dia_del_max date, plata_min numeric,
  plata_fin numeric, plata_promedio numeric,
  entradas numeric, salidas numeric, neto numeric,
  efectivo_fin numeric, bancolombia_fin numeric, nequi_fin numeric,
  gastado_con_tc numeric, pagado_a_la_tc numeric, deuda_tc_fin numeric
)
language sql security definer set search_path = public as $$
with d as (select * from v_plata_diaria),
porm as (
  select date_trunc('month', fecha)::date as mes,
         max(plata) as plata_max, min(plata) as plata_min,
         round(avg(plata),2) as plata_promedio,
         (array_agg(plata       order by fecha desc))[1] as plata_fin,
         (array_agg(fecha       order by plata desc, fecha))[1] as dia_del_max,
         (array_agg(efectivo    order by fecha desc))[1] as efectivo_fin,
         (array_agg(bancolombia order by fecha desc))[1] as bancolombia_fin,
         (array_agg(nequi       order by fecha desc))[1] as nequi_fin,
         (array_agg(deuda_tc    order by fecha desc))[1] as deuda_tc_fin
  from d group by 1
),
flujo as (
  select date_trunc('month', m.fecha)::date as mes,
         coalesce(sum(m.monto) filter (where m.tipo='ingreso' and k.tipo <> 'tarjeta'
                                         and m.categoria is distinct from 'Ajuste de cuadre'),0) as entradas,
         coalesce(sum(m.monto) filter (where (m.tipo='gasto' and k.tipo <> 'tarjeta'
                                              and m.categoria is distinct from 'Ajuste de cuadre')
                                          or m.tipo='pago_tc'),0) as salidas,
         coalesce(sum(m.monto) filter (where m.tipo='gasto' and k.tipo = 'tarjeta'),0) as gastado_con_tc,
         coalesce(sum(m.monto) filter (where m.tipo='pago_tc'),0)                     as pagado_a_la_tc
  from movimientos m join cuentas k on k.id = m.cuenta group by 1
)
select p.mes, p.plata_max, p.dia_del_max, p.plata_min, p.plata_fin, p.plata_promedio,
       coalesce(f.entradas,0), coalesce(f.salidas,0),
       coalesce(f.entradas,0) - coalesce(f.salidas,0),
       p.efectivo_fin, p.bancolombia_fin, p.nequi_fin,
       coalesce(f.gastado_con_tc,0), coalesce(f.pagado_a_la_tc,0), p.deuda_tc_fin
from porm p left join flujo f using (mes)
where p.mes >= date_trunc('month', (select min(fecha) from movimientos))
order by p.mes;
$$;

create or replace function public.datos_periodo(p_desde date, p_hasta date)
returns jsonb
language sql stable set search_path = public as $$
  with m as (select mv.*, (k.tipo = 'tarjeta') as es_tc
             from movimientos mv join cuentas k on k.id = mv.cuenta
             where mv.fecha between p_desde and p_hasta),
  g as (select * from m where tipo = 'gasto'   and categoria is distinct from 'Ajuste de cuadre'),
  i as (select * from m where tipo = 'ingreso' and categoria is distinct from 'Ajuste de cuadre')
  select jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'resumen', jsonb_build_object(
      'entradas',       (select coalesce(sum(monto), 0) from i where not es_tc),
      'salidas',        (select coalesce(sum(monto), 0) from g where not es_tc)
                      + (select coalesce(sum(monto), 0) from m where tipo = 'pago_tc'),
      'gastos',         (select coalesce(sum(monto), 0) from g),
      'ingresos',       (select coalesce(sum(monto), 0) from i),
      'gastado_con_tc', (select coalesce(sum(monto), 0) from g where es_tc),
      'pagado_a_la_tc', (select coalesce(sum(monto), 0) from m where tipo = 'pago_tc'),
      'traslados',      (select coalesce(sum(monto), 0) from m where tipo = 'traslado'),
      'movimientos',    (select count(*) from m),
      'n_gastos',       (select count(*) from g),
      'n_ingresos',     (select count(*) from i)
    ),
    'gasto_categorias', coalesce((
      select jsonb_agg(x order by x.total desc) from (
        select coalesce(categoria, 'Sin categoría') as categoria, sum(monto) as total, count(*) as veces
        from g group by 1) x), '[]'::jsonb),
    'ingreso_categorias', coalesce((
      select jsonb_agg(x order by x.total desc) from (
        select coalesce(categoria, 'Sin categoría') as categoria, sum(monto) as total, count(*) as veces
        from i group by 1) x), '[]'::jsonb),
    'gasto_cuentas', coalesce((
      select jsonb_agg(x order by x.total desc) from (
        select cuenta, sum(monto) as total, count(*) as veces from g group by 1) x), '[]'::jsonb),
    'por_dia', coalesce((
      select jsonb_agg(x order by x.fecha) from (
        select fecha,
               coalesce(sum(monto) filter (where tipo = 'gasto'   and categoria is distinct from 'Ajuste de cuadre'), 0) as gastos,
               coalesce(sum(monto) filter (where tipo = 'ingreso' and categoria is distinct from 'Ajuste de cuadre'), 0) as ingresos
        from m group by fecha) x), '[]'::jsonb),
    'por_mes', coalesce((
      select jsonb_agg(x order by x.mes) from (
        select date_trunc('month', fecha)::date as mes,
               coalesce(sum(monto) filter (where tipo = 'gasto'   and categoria is distinct from 'Ajuste de cuadre'), 0) as gastos,
               coalesce(sum(monto) filter (where tipo = 'ingreso' and categoria is distinct from 'Ajuste de cuadre'), 0) as ingresos,
               coalesce(sum(monto) filter (where tipo = 'ingreso' and not es_tc and categoria is distinct from 'Ajuste de cuadre'), 0) as entradas,
               coalesce(sum(monto) filter (where (tipo = 'gasto' and not es_tc and categoria is distinct from 'Ajuste de cuadre')
                                               or tipo = 'pago_tc'), 0) as salidas
        from m group by 1) x), '[]'::jsonb),
    'dia_semana', coalesce((
      select jsonb_agg(x order by x.dow) from (
        select extract(isodow from fecha)::int as dow, sum(monto) as total, count(*) as veces
        from g group by 1) x), '[]'::jsonb),
    'top_gastos', coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select id, fecha, cuenta, categoria, nota, monto, historico
        from g order by monto desc, fecha desc limit 5) x), '[]'::jsonb),
    'saldo_diario', coalesce((
      select jsonb_agg(x order by x.fecha) from (
        select fecha, plata, deuda_tc from v_plata_diaria
        where fecha between p_desde and p_hasta) x), '[]'::jsonb)
  );
$$;

-- ---------- TARJETAS: cada una con su día de corte ----------
create or replace function public.tc_cargos_todas()
returns table (cuenta text, periodo date, valor numeric, movimiento_id uuid, cuota int)
language sql stable set search_path = public as $$
  select m.cuenta,
         (public.tc_periodo(m.fecha, k.dia_corte) + make_interval(months => n.k))::date,
         case when coalesce(m.cuotas, 1) > 1
              then coalesce(m.cuota_valor, round(m.monto / m.cuotas, 2)) else m.monto end,
         m.id, n.k + 1
  from movimientos m
  join cuentas k on k.id = m.cuenta and k.tipo = 'tarjeta'
  cross join lateral generate_series(0, coalesce(m.cuotas, 1) - 1) as n(k)
  where m.tipo = 'gasto' and not m.historico
  union all
  select m.cuenta, public.tc_periodo(m.fecha, k.dia_corte), -m.monto, m.id, 1
  from movimientos m
  join cuentas k on k.id = m.cuenta and k.tipo = 'tarjeta'
  where m.tipo = 'ingreso' and not m.historico;
$$;

-- ---------------------------------------------------------------------
--  saldos_cuentas(hoy) — una fila por cuenta o tarjeta (también las de la
--  papelera, marcadas) con su saldo. Para tarjetas: corte anterior, corte
--  actual, total a pagar y cuotas que caen en cortes que todavía no empiezan.
--  Lo pagado (y las devoluciones) cubre primero lo más viejo.
-- ---------------------------------------------------------------------
create or replace function public.saldos_cuentas(p_hoy date default null)
returns table (id text, nombre text, tipo text, color text, orden int, borrada boolean, dia_corte int,
               saldo numeric, saldo_inicial numeric,
               corte_anterior numeric, corte_actual numeric, total_pagar numeric, cuotas_futuras numeric,
               corte_desde date, corte_hasta date)
language sql stable set search_path = public as $$
  with hoy as (select coalesce(p_hoy, (now() at time zone 'America/Bogota')::date) as d),
  base as (
    select k.*,
           coalesce((select si.monto from saldos_iniciales si where si.cuenta = k.id), 0) as ini,
           coalesce((select sum(e.delta) from v_efectos_propios e where e.cuenta = k.id), 0) as mov,
           case when k.tipo = 'tarjeta' then public.tc_periodo((select d from hoy), k.dia_corte) end as c0
    from cuentas k),
  car as (select * from public.tc_cargos_todas()),
  tar as (
    select b.id,
           coalesce((select sum(c.valor) from car c where c.cuenta = b.id and c.periodo <  b.c0), 0) as ant,
           coalesce((select sum(c.valor) from car c where c.cuenta = b.id and c.periodo =  b.c0), 0) as act,
           coalesce((select sum(c.valor) from car c where c.cuenta = b.id and c.periodo >  b.c0), 0) as fut,
           coalesce((select sum(m.monto) from movimientos m
                      where m.tipo = 'pago_tc' and m.cuenta = b.id and not m.historico), 0) as pag
    from base b where b.tipo = 'tarjeta'),
  rep as (select t.id, greatest(t.ant + t.act + t.fut - t.pag, 0) as resta, t.act, t.fut from tar t),
  rep2 as (select r.id, r.resta, least(greatest(r.fut, 0), r.resta) as fut2, r.act from rep r),
  rep3 as (select r.id, r.resta, r.fut2, least(greatest(r.act, 0), r.resta - r.fut2) as act2 from rep2 r)
  select b.id, b.nombre, b.tipo, b.color, b.orden, b.borrada_en is not null, b.dia_corte,
         b.ini + b.mov, b.ini,
         r.resta - r.fut2 - r.act2, r.act2, r.resta - r.fut2, r.fut2,
         b.c0, (b.c0 + interval '1 month')::date
  from base b left join rep3 r on r.id = b.id
  order by (b.tipo = 'tarjeta'), b.orden, b.nombre;
$$;

-- el texto del atajo del iPhone: las cuentas y tarjetas que están en uso
create or replace function public.saldos()
returns table (resumen text)
language sql stable security definer set search_path = public as $$
  with s as (select * from public.saldos_cuentas() where not borrada)
  select coalesce((select string_agg(s.nombre || ': $' || to_char(s.saldo, 'FM999,999,990'), E'\n' order by s.orden, s.nombre)
                     from s where s.tipo <> 'tarjeta'), '')
      || E'\nTotal: $' || to_char(coalesce((select sum(s.saldo) from s where s.tipo <> 'tarjeta'), 0), 'FM999,999,990')
      || coalesce((select string_agg(E'\n\n' || s.nombre
                     || E'\nCorte anterior: $' || to_char(s.corte_anterior, 'FM999,999,990')
                     || E'\nCorte actual: $'   || to_char(s.corte_actual, 'FM999,999,990')
                     || E'\nTotal a pagar: $'  || to_char(s.total_pagar, 'FM999,999,990'), '' order by s.orden, s.nombre)
                   from s where s.tipo = 'tarjeta'), '');
$$;

-- ---------- BILLETES por cuenta en efectivo ----------
create or replace function public.billeteras()
returns table (cuenta text, denominacion int, cantidad int)
language sql stable set search_path = public as $$
  with cajas as (select k.id from cuentas k where k.tipo = 'efectivo'),
  denoms(d) as (values (2000),(5000),(10000),(20000),(50000),(100000)),
  anclas as (select c.id as cuenta,
                    coalesce((select max(b.actualizado_en) from billetera_inicial b where b.cuenta = c.id),
                             '-infinity'::timestamptz) as ancla
             from cajas c),
  base as (select c.id as cuenta, dn.d, coalesce(bi.cantidad, 0) as c
           from cajas c cross join denoms dn
           left join billetera_inicial bi on bi.cuenta = c.id and bi.denominacion = dn.d),
  movs as (
    select public.caja_de(m.cuenta, m.cuenta_origen) as cuenta, m.billetes, 1 as signo, m.created_at
    from movimientos m where m.billetes is not null and not m.historico
    union all
    -- traslado entre dos cuentas en efectivo: lo que salió de una entró a la otra
    select m.cuenta, m.billetes, -1, m.created_at
    from movimientos m
    join cuentas o on o.id = m.cuenta_origen and o.tipo = 'efectivo'
    join cuentas t on t.id = m.cuenta and t.tipo = 'efectivo'
    where m.tipo = 'traslado' and m.billetes is not null and not m.historico),
  cambios as (
    select mv.cuenta, kv.key::int as den, sum(kv.value::int * mv.signo) as c
    from movs mv
    join anclas a on a.cuenta = mv.cuenta
    cross join lateral jsonb_each_text(mv.billetes) kv
    where mv.created_at > a.ancla
    group by 1, 2)
  select b.cuenta, b.d, (b.c + coalesce(ch.c, 0))::int
  from base b left join cambios ch on ch.cuenta = b.cuenta and ch.den = b.d
  order by 1, 2;
$$;

-- la de siempre (solo la cuenta "efectivo"), para la versión anterior de la página
create or replace function public.billetera()
returns table (denominacion int, cantidad int, subtotal numeric)
language sql stable security definer set search_path = public as $$
  select b.denominacion, b.cantidad, (b.cantidad * b.denominacion)::numeric
  from public.billeteras() b where b.cuenta = 'efectivo' order by 1;
$$;

-- ---------- crear, editar, papelera y orden de cuentas ----------
create or replace function public.guardar_cuenta(
  p_id text, p_nombre text, p_tipo text, p_color text, p_dia_corte int,
  p_saldo numeric default null, p_billetes jsonb default null)
returns text
language plpgsql set search_path = public as $$
declare
  v_id     text := p_id;
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_otra   cuentas;
  v_old    cuentas;
  v_suma   numeric := 0;
begin
  if v_nombre = '' then raise exception 'Ponle un nombre'; end if;
  if length(v_nombre) > 30 then raise exception 'El nombre es muy largo (máximo 30 letras)'; end if;
  if nullif(btrim(coalesce(p_color, '')), '') is not null and p_color !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Ese color no sirve';
  end if;
  select * into v_otra from cuentas k where lower(k.nombre) = lower(v_nombre) and k.id is distinct from p_id;
  if found then
    raise exception 'Ya hay una cuenta o tarjeta llamada "%"%', v_otra.nombre,
      case when v_otra.borrada_en is not null then ' en la papelera: recupérala desde ahí' else '' end;
  end if;

  if v_id is null then
    if p_tipo is null or p_tipo not in ('efectivo', 'virtual', 'tarjeta') then
      raise exception 'Escoge si es en efectivo, virtual o tarjeta';
    end if;
    if p_tipo = 'tarjeta' and p_dia_corte is null then raise exception 'Escribe el día de corte'; end if;
    v_id := 'c_' || substr(md5(random()::text || clock_timestamp()::text), 1, 10);
    insert into cuentas (id, nombre, tipo, dia_corte, color, orden)
    values (v_id, v_nombre, p_tipo,
            case when p_tipo = 'tarjeta' then least(greatest(p_dia_corte, 1), 28) end,
            coalesce(nullif(btrim(coalesce(p_color, '')), ''), '#3B9EFF'),
            coalesce((select max(k.orden) from cuentas k where (k.tipo = 'tarjeta') = (p_tipo = 'tarjeta')), 0) + 1);
    if p_tipo = 'efectivo' then
      insert into billetera_inicial (cuenta, denominacion, cantidad, actualizado_en)
      select v_id, dn.d, greatest(coalesce((p_billetes ->> dn.d::text)::int, 0), 0), now()
      from (values (2000),(5000),(10000),(20000),(50000),(100000)) dn(d);
      select coalesce(sum(b.cantidad * b.denominacion), 0) into v_suma from billetera_inicial b where b.cuenta = v_id;
      insert into saldos_iniciales (cuenta, monto) values (v_id, v_suma);
    elsif p_tipo = 'virtual' then
      insert into saldos_iniciales (cuenta, monto) values (v_id, coalesce(p_saldo, 0));
    end if;
    return v_id;
  end if;

  select * into v_old from cuentas k where k.id = v_id for update;
  if not found then raise exception 'Esa cuenta ya no existe'; end if;
  update cuentas k set
    nombre    = v_nombre,
    color     = coalesce(nullif(btrim(coalesce(p_color, '')), ''), k.color),
    dia_corte = case when k.tipo = 'tarjeta' then least(greatest(coalesce(p_dia_corte, k.dia_corte), 1), 28) end
  where k.id = v_id;
  if v_id = 'TC' then           -- lo usa la versión anterior de la página
    update config set dia_corte_tc = (select k.dia_corte from cuentas k where k.id = 'TC') where id = 1;
  end if;
  return v_id;
end;
$$;

-- a la papelera: deja de salir para usarla y en los saldos; los movimientos no se tocan
create or replace function public.borrar_cuenta(p_id text)
returns void
language plpgsql set search_path = public as $$
declare v cuentas;
begin
  select * into v from cuentas k where k.id = p_id for update;
  if not found then raise exception 'Esa cuenta ya no existe'; end if;
  if v.tipo <> 'tarjeta' and not exists (
       select 1 from cuentas k where k.tipo <> 'tarjeta' and k.borrada_en is null and k.id <> p_id) then
    raise exception 'Tiene que quedar al menos una cuenta para la plata';
  end if;
  update cuentas set borrada_en = now() where id = p_id;
end;
$$;

create or replace function public.restaurar_cuenta(p_id text)
returns void
language sql set search_path = public as $$
  update cuentas set borrada_en = null where id = p_id;
$$;

create or replace function public.ordenar_cuentas(p_ids text[])
returns void
language sql set search_path = public as $$
  update cuentas k set orden = x.i
  from unnest(p_ids) with ordinality as x(id, i)
  where k.id = x.id;
$$;

-- ---------- CATEGORÍAS: papelera ----------
alter table public.categorias add column if not exists borrada_en timestamptz;

drop function if exists public.categorias_uso();
create function public.categorias_uso()
returns table (id uuid, nombre text, tipo text, icono text, orden int, usos bigint, borrada boolean)
language sql stable set search_path = public as $$
  select c.id, c.nombre, c.tipo, c.icono, c.orden,
         (select count(*) from movimientos m where m.categoria = c.nombre),
         c.borrada_en is not null
  from categorias c
  order by c.tipo, c.orden, c.nombre;
$$;

create or replace function public.guardar_categoria(
  p_id uuid, p_nombre text, p_tipo text, p_icono text)
returns jsonb
language plpgsql set search_path = public as $$
declare
  v_old    categorias;
  v_new    categorias;
  v_otra   categorias;
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_icono  text := coalesce(nullif(btrim(coalesce(p_icono, '')), ''), '•');
  v_usos   bigint;
  v_orden  int;
begin
  if v_nombre = '' then raise exception 'La categoría necesita un nombre'; end if;
  if length(v_nombre) > 40 then raise exception 'El nombre es muy largo (máximo 40 letras)'; end if;
  if length(v_icono) > 16 then raise exception 'El ícono tiene que ser un solo emoji'; end if;
  if p_tipo is null or p_tipo not in ('gasto', 'ingreso') then raise exception 'El tipo tiene que ser gasto o ingreso'; end if;
  select * into v_otra from categorias c where lower(c.nombre) = lower(v_nombre) and c.id is distinct from p_id;
  if found then
    raise exception 'Ya existe una categoría llamada "%"%', v_otra.nombre,
      case when v_otra.borrada_en is not null then ' en la papelera: recupérala desde ahí' else '' end;
  end if;

  if p_id is null then
    select coalesce(max(c.orden), 0) + 1 into v_orden
    from categorias c
    where c.tipo = p_tipo and c.nombre not in ('Otro', 'Otro ingreso', 'Ajuste de cuadre');
    insert into categorias (nombre, tipo, icono, orden)
    values (v_nombre, p_tipo, v_icono, v_orden)
    returning * into v_new;
    update categorias c set orden = v_orden + 1
    where c.tipo = p_tipo and c.nombre in ('Otro', 'Otro ingreso') and c.orden <= v_orden;
    return to_jsonb(v_new);
  end if;

  select * into v_old from categorias c where c.id = p_id for update;
  if not found then raise exception 'Esa categoría ya no existe'; end if;
  if v_old.nombre in ('Ajuste de cuadre', 'Cobro suscripciones')
     and (v_nombre <> v_old.nombre or p_tipo <> v_old.tipo) then
    raise exception '"%" la usa la app por dentro: solo se le puede cambiar el ícono', v_old.nombre;
  end if;
  select count(*) into v_usos from movimientos m where m.categoria = v_old.nombre;
  if p_tipo <> v_old.tipo and v_usos > 0 then
    raise exception 'No se puede pasar de % a % porque ya tiene % movimientos', v_old.tipo, p_tipo, v_usos;
  end if;

  update categorias c set nombre = v_nombre, tipo = p_tipo, icono = v_icono
  where c.id = p_id returning * into v_new;
  if v_nombre <> v_old.nombre then
    update movimientos m set categoria = v_nombre where m.categoria = v_old.nombre;
  end if;
  return to_jsonb(v_new) || jsonb_build_object('usos', v_usos);
end;
$$;

-- a la papelera: los movimientos siguen con su categoría. (p_mover_a ya no se usa)
create or replace function public.borrar_categoria(p_id uuid, p_mover_a text default null)
returns integer
language plpgsql set search_path = public as $$
declare v categorias;
begin
  select * into v from categorias c where c.id = p_id for update;
  if not found then raise exception 'Esa categoría ya no existe'; end if;
  if v.nombre in ('Ajuste de cuadre', 'Cobro suscripciones') then
    raise exception '"%" la usa la app por dentro y no se puede borrar', v.nombre;
  end if;
  if (select count(*) from categorias c where c.tipo = v.tipo and c.borrada_en is null and c.id <> p_id
        and c.nombre <> 'Ajuste de cuadre') = 0 then
    raise exception 'Tiene que quedar al menos una categoría de %', v.tipo;
  end if;
  update categorias set borrada_en = now() where id = p_id;
  return 0;
end;
$$;

create or replace function public.restaurar_categoria(p_id uuid)
returns void
language sql set search_path = public as $$
  update categorias set borrada_en = null where id = p_id;
$$;

grant execute on function public.caja_de(text, text)                 to anon;
grant execute on function public.saldos_por_mes()                    to anon;
grant execute on function public.plata_por_mes()                     to anon;
grant execute on function public.datos_periodo(date, date)           to anon;
grant execute on function public.tc_cargos_todas()                   to anon;
grant execute on function public.saldos_cuentas(date)                to anon;
grant execute on function public.saldos()                            to anon;
grant execute on function public.billeteras()                        to anon;
grant execute on function public.billetera()                         to anon;
grant execute on function public.guardar_cuenta(text, text, text, text, int, numeric, jsonb) to anon;
grant execute on function public.borrar_cuenta(text)                 to anon;
grant execute on function public.restaurar_cuenta(text)              to anon;
grant execute on function public.ordenar_cuentas(text[])             to anon;
grant execute on function public.categorias_uso()                    to anon;
grant execute on function public.guardar_categoria(uuid, text, text, text) to anon;
grant execute on function public.borrar_categoria(uuid, text)        to anon;
grant execute on function public.restaurar_categoria(uuid)           to anon;

-- =====================================================================
--  PERSONALIZAR (octubre 2026): colores, nombres y logo
--  Una sola fila en config, así sale igual en el celular y el computador.
--  tema = id de la paleta (ver PALETAS en index.html).
-- =====================================================================
alter table public.config add column if not exists tema           text not null default 'principal';
alter table public.config add column if not exists app_nombre     text;
alter table public.config add column if not exists usuario_nombre text;
alter table public.config add column if not exists logo           text;   -- imagen en data URL (256 px)
alter table public.config add column if not exists logo_v         text;   -- cambia cada vez que se sube un logo
comment on column public.config.logo is 'Logo propio como data URL (256x256). null = el logo original.';
--  estilo = id del estilo de la interfaz (ver ESTILOS en index.html): la forma y
--  el movimiento. Va aparte de tema: cualquier estilo con cualquier paleta.
alter table public.config add column if not exists estilo         text not null default 'original';
comment on column public.config.estilo is 'Estilo de la interfaz (id de ESTILOS en index.html). La paleta va aparte, en tema.';

-- =====================================================================
--  BOLSILLOS Y LISTAS DE COBROS / PAGOS (octubre 2026)
--  Bolsillos: dividir la plata de una cuenta (no cambia su saldo).
--  Cobros: listas (Suscripciones, Deudas…) con grupos que se renombran.
--  Regla de siempre: borrar (papelera) nunca toca los movimientos.
-- =====================================================================
-- ---------- BOLSILLOS: dividir la plata de una cuenta ----------
create table if not exists public.bolsillos (
  id         uuid primary key default gen_random_uuid(),
  cuenta     text not null references public.cuentas(id) on update cascade on delete cascade,
  nombre     text not null,
  icono      text not null default '👛',
  orden      int  not null default 99,
  borrada_en timestamptz,                                  -- no null = en la papelera
  creada_en  timestamptz not null default now()
);
create unique index if not exists bolsillos_nombre_unico on public.bolsillos (cuenta, lower(nombre));
comment on table public.bolsillos is
  'Divisiones de la plata de una cuenta (como los bolsillos de Nequi). Lo que no está en ninguno es "sin dividir".';

-- pasar plata entre "sin dividir" (null) y los bolsillos de una misma cuenta
create table if not exists public.bolsillo_movs (
  id         uuid primary key default gen_random_uuid(),
  cuenta     text not null references public.cuentas(id) on update cascade on delete cascade,
  desde      uuid references public.bolsillos(id) on delete cascade,     -- null = sin dividir
  hacia      uuid references public.bolsillos(id) on delete cascade,     -- null = sin dividir
  monto      numeric(14,2) not null check (monto > 0),
  nota       text,
  created_at timestamptz not null default now(),
  constraint bolsillo_movs_distintos check (desde is distinct from hacia)
);
create index if not exists idx_bolsillo_movs_cuenta on public.bolsillo_movs (cuenta);

-- de qué bolsillo sale o a cuál entra la plata de un movimiento
-- bolsillo = el de `cuenta`; bolsillo_origen = el de `cuenta_origen` (traslados y pagos a la TC)
alter table public.movimientos add column if not exists bolsillo        uuid references public.bolsillos(id) on delete set null;
alter table public.movimientos add column if not exists bolsillo_origen uuid references public.bolsillos(id) on delete set null;

-- si un movimiento cambia de cuenta, su bolsillo ya no aplica: queda en "sin dividir"
create or replace function public.ajustar_bolsillos_mov()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.bolsillo is not null and not exists (
       select 1 from bolsillos b where b.id = new.bolsillo and b.cuenta = new.cuenta) then
    new.bolsillo := null;
  end if;
  if new.bolsillo_origen is not null and not exists (
       select 1 from bolsillos b where b.id = new.bolsillo_origen and b.cuenta = new.cuenta_origen) then
    new.bolsillo_origen := null;
  end if;
  return new;
end;
$$;
create or replace trigger movimientos_bolsillos before insert or update of bolsillo, bolsillo_origen, cuenta, cuenta_origen
  on public.movimientos for each row execute function public.ajustar_bolsillos_mov();

-- saldo de cada bolsillo = lo que se le pasó + lo que movieron los movimientos marcados con él
create or replace function public.bolsillos_saldos()
returns table (id uuid, cuenta text, nombre text, icono text, orden int, borrada boolean,
               saldo numeric, pasado numeric, movido numeric, usos bigint)
language sql stable set search_path = public as $$
  with ef as (
    select m.bolsillo as b,
           case m.tipo when 'gasto' then -m.monto when 'ingreso' then m.monto
                       when 'traslado' then m.monto else 0 end as d
    from movimientos m
    where m.bolsillo is not null and not m.historico and m.tipo <> 'pago_tc'
    union all
    select m.bolsillo_origen, -m.monto
    from movimientos m
    where m.bolsillo_origen is not null and not m.historico and m.tipo in ('traslado', 'pago_tc')
    union all
    -- monedas: igual que en la cuenta, van a la caja (origen si es en efectivo, si no destino)
    select case when public.caja_de(m.cuenta, m.cuenta_origen) = m.cuenta_origen
                then m.bolsillo_origen else m.bolsillo end, -m.monedas
    from movimientos m
    where m.monedas <> 0 and not m.historico),
  mv as (
    select hacia as b, monto as d from bolsillo_movs where hacia is not null
    union all
    select desde, -monto from bolsillo_movs where desde is not null)
  select b.id, b.cuenta, b.nombre, b.icono, b.orden, b.borrada_en is not null,
         coalesce((select sum(mv.d) from mv where mv.b = b.id), 0)
           + coalesce((select sum(ef.d) from ef where ef.b = b.id), 0),
         coalesce((select sum(mv.d) from mv where mv.b = b.id), 0),
         coalesce((select sum(ef.d) from ef where ef.b = b.id), 0),
         (select count(*) from movimientos m where m.bolsillo = b.id or m.bolsillo_origen = b.id)
  from bolsillos b
  order by b.cuenta, b.orden, b.nombre;
$$;

create or replace function public.guardar_bolsillo(
  p_id uuid, p_cuenta text, p_nombre text, p_icono text, p_monto numeric default null)
returns uuid
language plpgsql set search_path = public as $$
declare
  v_id     uuid := p_id;
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_icono  text := coalesce(nullif(btrim(coalesce(p_icono, '')), ''), '👛');
  v_cuenta text := p_cuenta;
  v_otro   bolsillos;
begin
  if v_nombre = '' then raise exception 'Ponle un nombre al bolsillo'; end if;
  if length(v_nombre) > 30 then raise exception 'El nombre es muy largo (máximo 30 letras)'; end if;
  if length(v_icono) > 16 then raise exception 'El ícono tiene que ser un solo emoji'; end if;
  if v_id is not null then select b.cuenta into v_cuenta from bolsillos b where b.id = v_id; end if;
  if v_cuenta is null or not exists (select 1 from cuentas k where k.id = v_cuenta and k.tipo <> 'tarjeta') then
    raise exception 'Los bolsillos son de una cuenta (no de una tarjeta)';
  end if;
  select * into v_otro from bolsillos b
  where b.cuenta = v_cuenta and lower(b.nombre) = lower(v_nombre) and b.id is distinct from v_id;
  if found then
    raise exception 'Ya hay un bolsillo llamado "%"%', v_otro.nombre,
      case when v_otro.borrada_en is not null then ' en la papelera: recupéralo desde ahí' else '' end;
  end if;
  if v_id is null then
    insert into bolsillos (cuenta, nombre, icono, orden)
    values (v_cuenta, v_nombre, v_icono,
            coalesce((select max(b.orden) from bolsillos b where b.cuenta = v_cuenta), 0) + 1)
    returning id into v_id;
    if coalesce(p_monto, 0) > 0 then
      insert into bolsillo_movs (cuenta, desde, hacia, monto, nota) values (v_cuenta, null, v_id, p_monto, 'Al crearlo');
    end if;
  else
    update bolsillos set nombre = v_nombre, icono = v_icono where id = v_id;
  end if;
  return v_id;
end;
$$;

-- pasar plata dentro de una cuenta: de sin dividir (null) a un bolsillo, al revés, o entre bolsillos
create or replace function public.mover_bolsillo(
  p_cuenta text, p_desde uuid, p_hacia uuid, p_monto numeric, p_nota text default null)
returns uuid
language plpgsql set search_path = public as $$
declare v_id uuid;
begin
  if coalesce(p_monto, 0) <= 0 then raise exception 'Escribe cuánto vas a pasar'; end if;
  if p_desde is not distinct from p_hacia then raise exception 'Escoge de dónde y a dónde, distintos'; end if;
  if p_desde is not null and not exists (select 1 from bolsillos b where b.id = p_desde and b.cuenta = p_cuenta) then
    raise exception 'Ese bolsillo no es de esta cuenta';
  end if;
  if p_hacia is not null and not exists (select 1 from bolsillos b where b.id = p_hacia and b.cuenta = p_cuenta) then
    raise exception 'Ese bolsillo no es de esta cuenta';
  end if;
  insert into bolsillo_movs (cuenta, desde, hacia, monto, nota)
  values (p_cuenta, p_desde, p_hacia, p_monto, nullif(btrim(coalesce(p_nota, '')), ''))
  returning id into v_id;
  return v_id;
end;
$$;

-- a la papelera: la plata que tenía vuelve a "sin dividir"; los movimientos no se tocan
create or replace function public.borrar_bolsillo(p_id uuid)
returns void language sql set search_path = public as $$
  update bolsillos set borrada_en = now() where id = p_id;
$$;
create or replace function public.restaurar_bolsillo(p_id uuid)
returns void language sql set search_path = public as $$
  update bolsillos set borrada_en = null where id = p_id;
$$;

-- ---------- LISTAS DE COBROS Y DE PAGOS ----------
-- tipo ingreso = me pagan (crea un ingreso); tipo gasto = yo pago (crea un gasto, ej. deudas)
create table if not exists public.cobro_listas (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  tipo       text not null default 'ingreso' check (tipo in ('ingreso', 'gasto')),
  categoria  text,                                         -- la de los movimientos que crea
  icono      text not null default '💰',
  orden      int  not null default 99,
  borrada_en timestamptz,
  creada_en  timestamptz not null default now()
);
-- los grupos de cada lista ("Día 1 del mes"…): el nombre se puede cambiar
create table if not exists public.cobro_grupos (
  id        uuid primary key default gen_random_uuid(),
  lista_id  uuid not null references public.cobro_listas(id) on delete cascade,
  nombre    text not null,
  dia       int  check (dia between 1 and 28),             -- el día que se propone al marcar un mes pasado
  orden     int  not null default 99,
  borrada_en timestamptz,                                  -- borrado: ya no sale; su gente queda sin grupo
  creada_en timestamptz not null default now()
);
create index if not exists idx_cobro_grupos_lista on public.cobro_grupos (lista_id);

-- la lista de siempre
insert into public.cobro_listas (id, nombre, tipo, categoria, icono, orden)
values ('00000000-0000-4000-8000-000000000001', 'Suscripciones', 'ingreso', 'Cobro suscripciones', '📺', 1)
on conflict (id) do nothing;

alter table public.personas add column if not exists lista_id uuid not null
  default '00000000-0000-4000-8000-000000000001' references public.cobro_listas(id);
alter table public.personas add column if not exists grupo_id  uuid references public.cobro_grupos(id) on delete set null;
alter table public.personas add column if not exists categoria text;   -- si no, la de la lista
create index if not exists idx_personas_lista on public.personas (lista_id);

-- un grupo por cada día de cobro que hay hoy (solo la primera vez: si se vuelve a correr, no
-- toca los grupos ni lo que la persona haya cambiado)
do $$
begin
  if not exists (select 1 from public.cobro_grupos g where g.lista_id = '00000000-0000-4000-8000-000000000001') then
    insert into public.cobro_grupos (lista_id, nombre, dia, orden)
    select '00000000-0000-4000-8000-000000000001', 'Día ' || x.d || ' del mes', x.d, row_number() over (order by x.d)
    from (select distinct p.dia_cobro as d from public.personas p where p.baja_mes is null) x;
    update public.personas p set grupo_id = g.id
    from public.cobro_grupos g
    where p.grupo_id is null and p.baja_mes is null and g.lista_id = p.lista_id and g.dia = p.dia_cobro;
  end if;
end $$;

-- crear o editar una persona (o un pago, en una lista de pagos)
create or replace function public.guardar_item_cobro(
  p_id uuid, p_lista uuid, p_grupo uuid, p_nombre text, p_desde date, p_servicios jsonb, p_categoria text default null)
returns uuid
language plpgsql set search_path = public as $$
declare v_id uuid; v_dia int;
begin
  if p_grupo is not null then
    if not exists (select 1 from cobro_grupos g where g.id = p_grupo and g.borrada_en is null
                     and g.lista_id = coalesce(p_lista, (select p.lista_id from personas p where p.id = p_id))) then
      raise exception 'Ese grupo no es de esta lista';
    end if;
    select g.dia into v_dia from cobro_grupos g where g.id = p_grupo;
  end if;
  if v_dia is null and p_id is not null then select p.dia_cobro into v_dia from personas p where p.id = p_id; end if;
  v_id := public.guardar_persona(p_id, p_nombre, coalesce(v_dia, 1), p_desde, p_servicios);
  update personas set lista_id  = coalesce(p_lista, lista_id),
                      grupo_id  = p_grupo,
                      categoria = nullif(btrim(coalesce(p_categoria, '')), '')
  where id = v_id;
  return v_id;
end;
$$;

-- crear o editar un grupo y decir quiénes están en él
create or replace function public.guardar_grupo(
  p_id uuid, p_lista uuid, p_nombre text, p_dia int, p_miembros uuid[])
returns uuid
language plpgsql set search_path = public as $$
declare v_id uuid := p_id; v_lista uuid := p_lista; v_dia int := case when p_dia between 1 and 28 then p_dia end;
begin
  if btrim(coalesce(p_nombre, '')) = '' then raise exception 'Ponle un nombre al grupo'; end if;
  if v_id is null then
    if v_lista is null then raise exception 'Falta la lista'; end if;
    insert into cobro_grupos (lista_id, nombre, dia, orden)
    values (v_lista, btrim(p_nombre), v_dia,
            coalesce((select max(g.orden) from cobro_grupos g where g.lista_id = v_lista), 0) + 1)
    returning id into v_id;
  else
    update cobro_grupos set nombre = btrim(p_nombre), dia = v_dia
    where id = v_id and borrada_en is null returning lista_id into v_lista;
    if v_lista is null then raise exception 'Ese grupo ya no existe'; end if;
  end if;
  if p_miembros is not null then
    update personas set grupo_id = null where grupo_id = v_id and not (id = any(p_miembros));
    update personas set grupo_id = v_id, dia_cobro = coalesce(v_dia, dia_cobro)
    where id = any(p_miembros) and lista_id = v_lista;
  end if;
  return v_id;
end;
$$;

-- borrar un grupo: deja de salir y la gente que tenía queda "sin grupo"; nada más cambia
create or replace function public.borrar_grupo(p_id uuid)
returns void language sql set search_path = public as $$
  update personas set grupo_id = null where grupo_id = p_id;
  update cobro_grupos set borrada_en = now() where id = p_id;
$$;

create or replace function public.ordenar_grupos(p_ids uuid[])
returns void language sql set search_path = public as $$
  update cobro_grupos g set orden = x.i from unnest(p_ids) with ordinality as x(id, i) where g.id = x.id;
$$;

create or replace function public.guardar_lista(
  p_id uuid, p_nombre text, p_tipo text, p_categoria text, p_icono text)
returns uuid
language plpgsql set search_path = public as $$
declare v_id uuid := p_id; v_old cobro_listas;
begin
  if btrim(coalesce(p_nombre, '')) = '' then raise exception 'Ponle un nombre a la lista'; end if;
  if v_id is null then
    if p_tipo not in ('ingreso', 'gasto') then raise exception 'Escoge si te pagan o si pagas tú'; end if;
    insert into cobro_listas (nombre, tipo, categoria, icono, orden)
    values (btrim(p_nombre), p_tipo, nullif(btrim(coalesce(p_categoria, '')), ''),
            coalesce(nullif(btrim(coalesce(p_icono, '')), ''), case when p_tipo = 'gasto' then '🧾' else '💰' end),
            coalesce((select max(l.orden) from cobro_listas l), 0) + 1)
    returning id into v_id;
    insert into cobro_grupos (lista_id, nombre, dia, orden) values (v_id, 'Día 1 del mes', 1, 1);
  else
    select * into v_old from cobro_listas where id = v_id for update;
    if not found then raise exception 'Esa lista ya no existe'; end if;
    update cobro_listas set nombre = btrim(p_nombre),
                            categoria = nullif(btrim(coalesce(p_categoria, '')), ''),
                            icono = coalesce(nullif(btrim(coalesce(p_icono, '')), ''), icono)
    where id = v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.borrar_lista(p_id uuid)
returns void language sql set search_path = public as $$
  update cobro_listas set borrada_en = now() where id = p_id;
$$;
create or replace function public.restaurar_lista(p_id uuid)
returns void language sql set search_path = public as $$
  update cobro_listas set borrada_en = null where id = p_id;
$$;

-- renombrar una categoría también la cambia en las listas y en las personas que la usan
create or replace function public.renombrar_categoria_en_cobros()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.nombre is distinct from old.nombre then
    update cobro_listas set categoria = new.nombre where categoria = old.nombre;
    update personas     set categoria = new.nombre where categoria = old.nombre;
  end if;
  return new;
end;
$$;
create or replace trigger categorias_renombrar_cobros after update of nombre on public.categorias
  for each row execute function public.renombrar_categoria_en_cobros();

-- ---------- permisos (políticas abiertas, como el resto) ----------
alter table public.bolsillos     enable row level security;
alter table public.bolsillo_movs enable row level security;
alter table public.cobro_listas  enable row level security;
alter table public.cobro_grupos  enable row level security;
do $$
declare t text;
begin
  foreach t in array array['bolsillos', 'bolsillo_movs', 'cobro_listas', 'cobro_grupos'] loop
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'todo_' || t) then
      execute format('create policy %I on public.%I for all using (true) with check (true)', 'todo_' || t, t);
    end if;
  end loop;
end $$;
grant select, insert, update, delete on public.bolsillos, public.bolsillo_movs,
  public.cobro_listas, public.cobro_grupos to anon;

grant execute on function public.bolsillos_saldos()                                      to anon;
grant execute on function public.guardar_bolsillo(uuid, text, text, text, numeric)       to anon;
grant execute on function public.mover_bolsillo(text, uuid, uuid, numeric, text)         to anon;
grant execute on function public.borrar_bolsillo(uuid)                                   to anon;
grant execute on function public.restaurar_bolsillo(uuid)                                to anon;
grant execute on function public.guardar_item_cobro(uuid, uuid, uuid, text, date, jsonb, text) to anon;
grant execute on function public.guardar_grupo(uuid, uuid, text, int, uuid[])            to anon;
grant execute on function public.borrar_grupo(uuid)                                      to anon;
grant execute on function public.ordenar_grupos(uuid[])                                  to anon;
grant execute on function public.guardar_lista(uuid, text, text, text, text)             to anon;
grant execute on function public.borrar_lista(uuid)                                      to anon;
grant execute on function public.restaurar_lista(uuid)                                   to anon;

-- ---------------------------------------------------------------------
--  RLS
--  ⚠️ Políticas abiertas: cualquiera con la llave anon puede leer y
--     escribir. Es aceptable solo si el repo y el sitio son privados.
--     Cada persona usa su propio proyecto de Supabase y su llave queda solo en su aparato.
-- ---------------------------------------------------------------------
alter table movimientos        enable row level security;
alter table saldos_iniciales   enable row level security;
alter table saldos_apertura    enable row level security;
alter table config             enable row level security;
alter table categorias         enable row level security;
alter table personas           enable row level security;
alter table servicios_persona  enable row level security;
alter table pagos_suscripcion  enable row level security;
alter table billetera_inicial  enable row level security;

create policy "acceso_total_movimientos" on movimientos       for all using (true) with check (true);
create policy "acceso_total_saldos"      on saldos_iniciales  for all using (true) with check (true);
create policy "todo_apertura"            on saldos_apertura   for all using (true) with check (true);
create policy "acceso_total_config"      on config            for all using (true) with check (true);
create policy "todo_categorias"          on categorias        for all using (true) with check (true);
create policy "todo_personas"            on personas          for all using (true) with check (true);
create policy "todo_servicios"           on servicios_persona for all using (true) with check (true);
create policy "todo_pagos"               on pagos_suscripcion for all using (true) with check (true);
create policy "todo_billetera"           on billetera_inicial for all using (true) with check (true);


-- =====================================================================
--  COLBILY · BASE EN BLANCO
--  Lo de arriba es la base completa. Aquí se deja limpia para una persona
--  nueva: sin cuentas, saldos ni categorías de ejemplo, con categorías generales,
--  la marca COLBily y lo que necesita el tutorial inicial.
-- =====================================================================
delete from public.billetera_inicial;
delete from public.saldos_iniciales;
delete from public.saldos_apertura;
delete from public.cuentas
 where not exists (select 1 from public.movimientos m where m.cuenta = cuentas.id or m.cuenta_origen = cuentas.id);

-- categorías generales (Ajuste de cuadre, Cobro suscripciones, Otro y Otro ingreso las usa la app por dentro)
delete from public.categorias c
 where not exists (select 1 from public.movimientos m where m.categoria = c.nombre);
insert into public.categorias (nombre, tipo, icono, orden) values
  ('Mercado','gasto','🛒',1), ('Comida','gasto','🍽️',2), ('Transporte','gasto','🚌',3),
  ('Arriendo','gasto','🔑',4), ('Servicios del hogar','gasto','🏠',5), ('Celular e internet','gasto','📱',6),
  ('Salud','gasto','💊',7), ('Educación','gasto','📚',8), ('Ropa','gasto','👕',9),
  ('Salidas','gasto','🎉',10), ('Suscripciones','gasto','📺',11), ('Deudas','gasto','💳',12),
  ('Mascotas','gasto','🐾',13), ('Regalos','gasto','🎁',14),
  ('Ajuste de cuadre','gasto','⚖️',98), ('Otro','gasto','✳️',99),
  ('Salario','ingreso','💼',1), ('Trabajos extra','ingreso','🛠️',2), ('Ventas','ingreso','🏷️',3),
  ('Cobro suscripciones','ingreso','💸',4), ('Reembolsos','ingreso','↩️',5),
  ('Regalos recibidos','ingreso','🎁',6), ('Otro ingreso','ingreso','✳️',99)
on conflict (nombre) do nothing;

-- la lista de cobros de siempre arranca con un grupo
insert into public.cobro_grupos (lista_id, nombre, dia, orden)
select '00000000-0000-4000-8000-000000000001', 'Día 1 del mes', 1, 1
 where not exists (select 1 from public.cobro_grupos g where g.lista_id = '00000000-0000-4000-8000-000000000001');

-- marca, edición (personal o business) y avance del tutorial
alter table public.config add column if not exists edicion text not null default 'personal';
alter table public.config drop constraint if exists config_edicion_check;
alter table public.config add constraint config_edicion_check check (edicion in ('personal', 'business'));
alter table public.config add column if not exists onboarding jsonb not null default '{}'::jsonb;
comment on column public.config.edicion is
  'personal = la app se llama COLBily y lleva su logo · business = nombre y logo propios (con código de activación).';
comment on column public.config.onboarding is 'Avance del tutorial inicial: {terminado, hechos, omitidos, excel}.';
update public.config set tema = 'principal', estilo = 'original', app_nombre = 'COLBily',
       usuario_nombre = null, logo = null, logo_v = null, edicion = 'personal', onboarding = '{}'::jsonb
 where id = 1;

-- la app la llama al conectarse: confirma que la base es de COLBily y cuánto se ha anotado
create or replace function public.colbily_info()
returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'app', 'COLBily',
    'version', 1,
    'cuentas', (select count(*) from cuentas where borrada_en is null),
    'movimientos', (select count(*) from movimientos where not historico),
    'primer_movimiento', (select min(fecha) from movimientos where not historico));
$$;

-- permisos para la llave pública (anon) de este proyecto
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
