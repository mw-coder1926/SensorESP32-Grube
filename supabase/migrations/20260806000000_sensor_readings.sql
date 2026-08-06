-- 1. Ensure schema/table permissions are granted to both roles
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON TABLE public.sensor_readings TO anon, authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

-- 2. Drop the old anon-only insert policy
DROP POLICY IF EXISTS "Allow public inserts" ON public.sensor_readings;

-- 3. Allow authenticated devices (ESP32 with JWT) to INSERT
CREATE POLICY "Allow authenticated inserts"
ON public.sensor_readings
FOR INSERT
TO authenticated
WITH CHECK (true);

-- 4. Allow public visitors (GitHub Pages frontend using anon/publishable key) to SELECT
CREATE POLICY "Allow public read access"
ON public.sensor_readings
FOR SELECT
TO anon, authenticated
USING (true);