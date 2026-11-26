-- TukTak24 Customer + Gift Card database
-- Safe to apply after confirming the existing public.orders table is present.
-- Gift cards are admin-managed: no automatic redemption or discount calculation.

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_code text unique not null default ('CUS-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  name text not null,
  phone text not null unique,
  division text,
  district text,
  upazila text,
  address text,
  first_order_at timestamptz,
  last_order_at timestamptz,
  order_count integer not null default 0,
  total_items integer not null default 0,
  lifetime_value numeric(12,2) not null default 0,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists customers_name_idx on public.customers (name);
create index if not exists customers_last_order_idx on public.customers (last_order_at desc);

create table if not exists public.gift_cards (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_percent numeric(5,2) not null check (discount_percent > 0 and discount_percent <= 100),
  customer_id uuid references public.customers(id) on delete set null,
  status text not null default 'unused' check (status in ('unused', 'used', 'disabled')),
  expires_at date,
  issued_at timestamptz not null default now(),
  redeemed_at timestamptz,
  order_code text,
  admin_note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists gift_cards_status_idx on public.gift_cards (status);
create index if not exists gift_cards_customer_idx on public.gift_cards (customer_id);
create unique index if not exists gift_cards_one_per_customer_idx on public.gift_cards (customer_id) where customer_id is not null;

-- Existing order rows are retained. This source marker lets the admin distinguish
-- website form orders from orders entered manually from WhatsApp.
alter table public.orders
  add column if not exists order_source text not null default 'website'
  check (order_source in ('website', 'whatsapp_manual'));

create or replace function public.tuktak24_sync_customer_from_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_items integer := 0;
  v_order_time timestamptz := coalesce(new.created_at, now());
begin
  if nullif(trim(new.customer_phone), '') is null then
    return new;
  end if;
  if jsonb_typeof(coalesce(new.items, '[]'::jsonb)) = 'array' then
    select coalesce(sum(greatest(0, coalesce((item->>'quantity')::integer, 0))), 0)
      into v_items
      from jsonb_array_elements(coalesce(new.items, '[]'::jsonb)) as item;
  end if;
  insert into public.customers (
    name, phone, division, district, upazila, address,
    first_order_at, last_order_at, order_count, total_items, lifetime_value
  ) values (
    coalesce(nullif(trim(new.customer_name), ''), 'Unknown'),
    trim(new.customer_phone), new.division, new.district, new.upazila, new.address,
    v_order_time, v_order_time, 1, v_items, coalesce(new.total, 0)
  )
  on conflict (phone) do update set
    name = excluded.name,
    division = coalesce(excluded.division, customers.division),
    district = coalesce(excluded.district, customers.district),
    upazila = coalesce(excluded.upazila, customers.upazila),
    address = coalesce(excluded.address, customers.address),
    first_order_at = least(coalesce(customers.first_order_at, excluded.first_order_at), excluded.first_order_at),
    last_order_at = greatest(coalesce(customers.last_order_at, excluded.last_order_at), excluded.last_order_at),
    order_count = customers.order_count + 1,
    total_items = customers.total_items + excluded.total_items,
    lifetime_value = customers.lifetime_value + excluded.lifetime_value,
    updated_at = now();
  return new;
end;
$$;

-- Backfill customers from all existing orders once, without overwriting any
-- customer records that may already have been manually curated.
with order_rollup as (
  select
    trim(customer_phone) as phone,
    (array_agg(nullif(trim(customer_name), '') order by created_at desc))[1] as name,
    (array_agg(division order by created_at desc))[1] as division,
    (array_agg(district order by created_at desc))[1] as district,
    (array_agg(upazila order by created_at desc))[1] as upazila,
    (array_agg(address order by created_at desc))[1] as address,
    min(created_at) as first_order_at,
    max(created_at) as last_order_at,
    count(*)::integer as order_count,
    coalesce(sum((select coalesce(sum(greatest(0, coalesce((item->>'quantity')::integer, 0))),0)
                  from jsonb_array_elements(coalesce(orders.items,'[]'::jsonb)) item)),0)::integer as total_items,
    coalesce(sum(total),0)::numeric(12,2) as lifetime_value
  from public.orders
  where nullif(trim(customer_phone),'') is not null
  group by trim(customer_phone)
)
insert into public.customers(name,phone,division,district,upazila,address,first_order_at,last_order_at,order_count,total_items,lifetime_value)
select coalesce(name,'Unknown'),phone,division,district,upazila,address,first_order_at,last_order_at,order_count,total_items,lifetime_value
from order_rollup
on conflict(phone) do nothing;

drop trigger if exists tuktak24_orders_customer_sync on public.orders;
create trigger tuktak24_orders_customer_sync
after insert on public.orders
for each row execute function public.tuktak24_sync_customer_from_order();

create or replace function public.admin_create_gift_cards(
  p_count integer,
  p_discount numeric,
  p_expires_at date,
  p_customer_id uuid default null
)
returns table(id uuid, code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_id uuid;
begin
  if coalesce(auth.jwt()->>'email', '') <> 'tuktak24.1@gmail.com' then
    raise exception 'Admin access required';
  end if;
  if p_count <> 1 then raise exception 'One gift code per customer only'; end if;
  if p_discount is null or p_discount <= 0 or p_discount > 100 then
    raise exception 'Discount must be between 0 and 100';
  end if;
  if p_customer_id is null or not exists (select 1 from public.customers c where c.id = p_customer_id) then
    raise exception 'Select a valid customer';
  end if;
  if exists (select 1 from public.gift_cards g where g.customer_id = p_customer_id) then
    raise exception 'This customer already has a gift card';
  end if;
  v_code := 'TTG-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  insert into public.gift_cards(code, discount_percent, expires_at, customer_id, created_by)
  values (v_code, p_discount, p_expires_at, p_customer_id, auth.uid())
  returning gift_cards.id into v_id;
  return query select v_id, v_code;
end;
$$;

alter table public.customers enable row level security;
alter table public.gift_cards enable row level security;

drop policy if exists "TukTak24 admins manage customers" on public.customers;
create policy "TukTak24 admins manage customers"
on public.customers for all to authenticated
using ((auth.jwt()->>'email') = 'tuktak24.1@gmail.com')
with check ((auth.jwt()->>'email') = 'tuktak24.1@gmail.com');

drop policy if exists "TukTak24 admins manage gift cards" on public.gift_cards;
create policy "TukTak24 admins manage gift cards"
on public.gift_cards for all to authenticated
using ((auth.jwt()->>'email') = 'tuktak24.1@gmail.com')
with check ((auth.jwt()->>'email') = 'tuktak24.1@gmail.com');

revoke all on public.customers from anon, authenticated;
revoke all on public.gift_cards from anon, authenticated;
grant select, insert, update, delete on public.customers to authenticated;
grant select, insert, update, delete on public.gift_cards to authenticated;
revoke all on function public.admin_create_gift_cards(integer, numeric, date, uuid) from public, anon;
grant execute on function public.admin_create_gift_cards(integer, numeric, date, uuid) to authenticated;
