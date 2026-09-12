-- 1. Ensure public/anon and authenticated roles have schema and table read access
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON TABLE public.sensor_readings TO anon, authenticated;

-- 2. Drop existing SELECT policies to prevent conflicts
DROP POLICY IF EXISTS "Allow public read access" ON public.sensor_readings;
DROP POLICY IF EXISTS "Allow dashboard read access" ON public.sensor_readings;

-- 3. Create the SELECT policy allowing both anonymous visitors and authenticated sessions
CREATE POLICY "Allow public read access"
ON public.sensor_readings
FOR SELECT
TO anon, authenticated
USING (true);

-- 4. Flush PostgREST schema permissions cache
NOTIFY pgrst, 'reload schema';