-- For each (valid_date, lead_days) pair, take the LATEST snapshot known —
-- i.e. the most recent forecast fetch that still respects the lead time.
CREATE OR REPLACE VIEW forecast_as_known AS
SELECT DISTINCT ON (valid_date, lead_days)
    valid_date,
    lead_days,
    knowledge_time,
    precipitation_mm,
    wind_kmh,
    temp_c,
    sunshine_hours
FROM weather_forecast_snapshot
ORDER BY valid_date, lead_days, knowledge_time DESC;
