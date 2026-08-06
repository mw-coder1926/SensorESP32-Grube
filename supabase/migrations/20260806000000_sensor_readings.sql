-- supabase/migrations/20260806000000_sensor_readings.sql

-- Drop the old policy created in 20260802
DROP POLICY IF EXISTS "Allow public inserts" ON public.sensor_readings;

-- Add the new authenticated insert policy
CREATE POLICY "Allow authenticated inserts"
ON public.sensor_readings
FOR INSERT
TO authenticated
WITH CHECK (true);
