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

-- 3. Security policies
alter table public.sensor_readings enable row level security;

create policy "Restrict inserts to authenticated devices"
on public.sensor_readings
for insert
to authenticated
with check (
  -- Ensure the row's owner matches the logged-in user ID
  (data->>'user_id') = auth.uid()::text
  -- Optional: still validate payload schema shape
  and data ? 'distance_cm'
);

create policy "Allow public read access"
on public.sensor_readings for select to anon using (true);