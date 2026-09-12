-- 1. Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS supabase_vault;

-- 2. Create system configuration table for UI-configurable settings
CREATE TABLE IF NOT EXISTS system_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT
);

-- Seed distance threshold and cooldown settings
INSERT INTO system_config (key, value, description)
VALUES 
  ('critical_distance_cm', '20', 'Distance threshold in cm to trigger alert email'),
  ('cooldown_minutes', '360', 'Minimum minutes between consecutive alert emails (e.g. 360 = 6 hours)')
ON CONFLICT (key) DO NOTHING;

-- 3. Create state table for the alert cooldown
CREATE TABLE IF NOT EXISTS alert_state (
  id INT PRIMARY KEY DEFAULT 1,
  last_alert_sent_at TIMESTAMPTZ,
  CONSTRAINT single_row CHECK (id = 1)
);

INSERT INTO alert_state (id, last_alert_sent_at)
VALUES (1, NULL)
ON CONFLICT (id) DO NOTHING;

-- 4. Trigger Function
CREATE OR REPLACE FUNCTION notify_cesspit_full()
RETURNS TRIGGER AS $$
DECLARE
  v_last_sent TIMESTAMPTZ;
  v_api_key TEXT;
  v_to_email TEXT;
  v_from_email TEXT;
  v_threshold_cm NUMERIC;
  v_cooldown_minutes INT;
  v_current_cm   NUMERIC;
BEGIN
  -- Fetch threshold (defaults to 20 cm)
  SELECT COALESCE(value::numeric, 20) INTO v_threshold_cm
  FROM system_config
  WHERE key = 'critical_distance_cm'
  LIMIT 1;

  -- Fetch cooldown in minutes (defaults to 360 minutes / 6 hours)
  SELECT COALESCE(value::integer, 360) INTO v_cooldown_minutes
  FROM system_config
  WHERE key = 'cooldown_minutes'
  LIMIT 1;

  -- Fetch API Key from Vault
  SELECT decrypted_secret INTO v_api_key
  FROM vault.decrypted_secrets
  WHERE name = 'resend_api_key'
  LIMIT 1;

  -- Fetch target recipient email from Vault
  SELECT decrypted_secret INTO v_to_email
  FROM vault.decrypted_secrets
  WHERE name = 'alert_to_email'
  LIMIT 1;

  -- Fetch sender email from Vault
  SELECT decrypted_secret INTO v_from_email
  FROM vault.decrypted_secrets
  WHERE name = 'alert_from_email'
  LIMIT 1;

  -- Proceed if current reading is <= dynamic threshold AND all secrets exist
  v_current_cm := (NEW.data->>'distance_cm')::numeric;
  
  IF v_current_cm IS NOT NULL AND v_current_cm <= v_threshold_cm 
     AND v_api_key IS NOT NULL 
     AND v_to_email IS NOT NULL 
     AND v_from_email IS NOT NULL THEN
    
    -- Lock row to evaluate cooldown
    SELECT last_alert_sent_at INTO v_last_sent
    FROM alert_state
    WHERE id = 1
    FOR UPDATE;

    IF v_last_sent IS NULL OR (NOW() - v_last_sent) >= (v_cooldown_minutes * INTERVAL '1 minute') THEN
      
      -- Dispatch HTTP POST request to Resend API
      PERFORM net.http_post(
        url := 'https://api.resend.com/emails',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_api_key
        ),
        body := jsonb_build_object(
          'from', v_from_email,
          'to', jsonb_build_array(v_to_email),
          'subject', '🚨 Alert: Cesspit Level Critical!',
          'html', format(
            '<p>Warning: Cesspit reading (<strong>%s cm</strong>) crossed threshold of <strong>%s cm</strong>.</p><p><strong>Time:</strong> %s</p>',
            v_current_cm,
            v_threshold_cm,
            NOW() AT TIME ZONE 'Europe/Berlin'
          )
        )
      );

      -- Update cooldown timestamp
      UPDATE alert_state
      SET last_alert_sent_at = NOW()
      WHERE id = 1;

    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Attach Trigger to sensor readings table
DROP TRIGGER IF EXISTS trigger_cesspit_alert ON sensor_readings;

CREATE TRIGGER trigger_cesspit_alert
AFTER INSERT ON sensor_readings
FOR EACH ROW
EXECUTE FUNCTION notify_cesspit_full();