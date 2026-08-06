-- 1. Create table for raw sensor logs
create table if not exists public.sensor_readings (
  id bigint generated always as identity primary key,
  created_at timestamptz default now() not null,
  device_id text not null,
  data jsonb not null
);

-- 2. Indexes for fast queries on time & JSON parameters
create index if not exists idx_sensor_data on public.sensor_readings using gin (data);
create index if not exists idx_device_created on public.sensor_readings (device_id, created_at desc);

-- 3. Security policies (check this later)
alter table public.sensor_readings enable row level security;

create policy "Allow public inserts"
on public.sensor_readings for insert to anon with check (true);

create policy "Allow public read access"
on public.sensor_readings for select to anon using (true);
