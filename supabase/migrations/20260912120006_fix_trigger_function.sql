CREATE OR REPLACE FUNCTION public.notify_cesspit_full()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, vault, extensions, pg_catalog
AS $$
DECLARE
  v_last_sent TIMESTAMPTZ;
  v_api_key TEXT;
  v_to_email TEXT;
  v_from_email TEXT;
  v_threshold_cm NUMERIC;
  v_cooldown_minutes INT;
  v_current_cm   NUMERIC;
BEGIN
  -- 1. Fetch threshold from system_config (defaults to 20 cm)
  SELECT COALESCE(value::numeric, 20) INTO v_threshold_cm
  FROM public.system_config
  WHERE key = 'critical_distance_cm'
  LIMIT 1;

  -- 2. Fetch cooldown from system_config (defaults to 360 min / 6 hours)
  SELECT COALESCE(value::integer, 360) INTO v_cooldown_minutes
  FROM public.system_config
  WHERE key = 'cooldown_minutes'
  LIMIT 1;

  -- 3. Fetch secrets from Vault
  SELECT decrypted_secret INTO v_api_key
  FROM vault.decrypted_secrets
  WHERE name = 'resend_api_key'
  LIMIT 1;

  SELECT decrypted_secret INTO v_to_email
  FROM vault.decrypted_secrets
  WHERE name = 'alert_to_email'
  LIMIT 1;

  SELECT decrypted_secret INTO v_from_email
  FROM vault.decrypted_secrets
  WHERE name = 'alert_from_email'
  LIMIT 1;

  -- 4. Safely extract nested jsonb distance reading
  v_current_cm := (NEW.data->>'distance_cm')::numeric;
  
  -- 5. Evaluate threshold and secret availability
  IF v_current_cm IS NOT NULL AND v_current_cm <= v_threshold_cm 
     AND v_api_key IS NOT NULL 
     AND v_to_email IS NOT NULL 
     AND v_from_email IS NOT NULL THEN
    
    -- 6. Lock alert state row in public.alert_state
    SELECT last_alert_sent_at INTO v_last_sent
    FROM public.alert_state
    WHERE id = 1
    FOR UPDATE;

    -- 7. Evaluate cooldown
    IF v_last_sent IS NULL OR (NOW() - v_last_sent) >= (v_cooldown_minutes * INTERVAL '1 minute') THEN
      
      -- 8. Dispatch HTTP request using official net.http_post with explicit text casting
      PERFORM net.http_post(
        url := 'https://api.resend.com/emails'::text,
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

      -- 9. Update state timestamp
      UPDATE public.alert_state
      SET last_alert_sent_at = NOW()
      WHERE id = 1;

    END IF;
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error in notify_cesspit_full trigger: %', SQLERRM;
    RETURN NEW;
END;
$$;