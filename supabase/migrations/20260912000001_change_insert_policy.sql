-- 1. Add the user_id column (defaults to the JWT user ID automatically)
ALTER TABLE public.sensor_readings 
ADD COLUMN IF NOT EXISTS user_id uuid DEFAULT auth.uid() REFERENCES auth.users(id);

-- 2. Drop the overly permissive insert policy
DROP POLICY IF EXISTS "Allow authenticated inserts" ON public.sensor_readings;

-- 3. Create the secure insert policy
CREATE POLICY "Allow authenticated inserts"
ON public.sensor_readings
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL AND user_id = auth.uid()
);

-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';