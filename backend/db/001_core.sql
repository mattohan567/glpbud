create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  height_cm int,
  sex text check (sex in ('male','female','other')),
  activity_level text,
  timezone text not null default 'America/Los_Angeles',
  created_at timestamptz not null default now()
);

create table if not exists meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  ts timestamptz not null,
  source text check (source in ('image','text','manual')) not null,
  image_url text,
  text_raw text,
  items jsonb not null,
  totals jsonb not null,
  confidence float not null,
  low_confidence boolean not null default false,
  notes text,
  created_at timestamptz not null default now()
);
create index on meals (user_id, ts desc);

create table if not exists exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  ts timestamptz not null,
  type text not null,
  duration_min float not null,
  intensity text,
  est_kcal int,
  source_text text,
  created_at timestamptz not null default now()
);
create index on exercises (user_id, ts desc);

create table if not exists weights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  ts timestamptz not null,
  weight_kg float not null,
  method text,
  created_at timestamptz not null default now()
);
create index on weights (user_id, ts desc);

create table if not exists medications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  drug_name text not null,
  dose_mg float not null,
  schedule_rule text not null,
  start_ts timestamptz not null,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists med_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  drug_name text not null,
  dose_mg float not null,
  ts timestamptz not null,
  injection_site text,
  side_effects jsonb,
  notes text,
  created_at timestamptz not null default now()
);
create index on med_events (user_id, ts desc);

create table if not exists event_bus (
  id bigserial primary key,
  user_id uuid,
  type text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index on event_bus (type, processed_at);

create table if not exists tool_runs (
  id bigserial primary key,
  user_id uuid,
  tool_name text not null,
  input jsonb,
  output jsonb,
  model text,
  latency_ms int,
  cost_usd numeric(10,4),
  success boolean,
  error text,
  created_at timestamptz not null default now()
);

create materialized view if not exists analytics_daily as
with daily_meals as (
  select
    u.id as user_id,
    (m.ts at time zone u.timezone)::date as day,
    sum((m.totals->>'kcal')::int) as kcal_in,
    sum((m.totals->>'protein_g')::float) as protein_g,
    sum((m.totals->>'carbs_g')::float) as carbs_g,
    sum((m.totals->>'fat_g')::float) as fat_g
  from users u
  join meals m on m.user_id = u.id
  group by u.id, (m.ts at time zone u.timezone)::date
),
daily_exercises as (
  select
    u.id as user_id,
    (e.ts at time zone u.timezone)::date as day,
    sum(e.est_kcal) as kcal_out
  from users u
  join exercises e on e.user_id = u.id
  group by u.id, (e.ts at time zone u.timezone)::date
)
select
  coalesce(dm.user_id, de.user_id) as user_id,
  coalesce(dm.day, de.day) as day,
  coalesce(dm.kcal_in, 0) as kcal_in,
  coalesce(dm.protein_g, 0) as protein_g,
  coalesce(dm.carbs_g, 0) as carbs_g,
  coalesce(dm.fat_g, 0) as fat_g,
  coalesce(de.kcal_out, 0) as kcal_out
from daily_meals dm
full outer join daily_exercises de on dm.user_id = de.user_id and dm.day = de.day;

create or replace function refresh_analytics_daily() returns void language sql as $$
  refresh materialized view analytics_daily;
$$;