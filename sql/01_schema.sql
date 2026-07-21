CREATE TABLE weather_forecast_snapshot (
    id              BIGSERIAL PRIMARY KEY,
    valid_date      DATE        NOT NULL,   -- the day the forecast is ABOUT
    knowledge_time  TIMESTAMPTZ NOT NULL,   -- when this forecast was fetched
    lead_days       INT         NOT NULL,   -- valid_date - knowledge_time::date
    precipitation_mm NUMERIC,
    wind_kmh        NUMERIC,
    temp_c          NUMERIC,
    sunshine_hours  NUMERIC,
    UNIQUE (valid_date, knowledge_time)
);

CREATE INDEX idx_forecast_valid_knowledge
    ON weather_forecast_snapshot (valid_date, knowledge_time);

CREATE TABLE weather_actual (
    valid_date       DATE PRIMARY KEY,      -- what really happened, ground truth
    precipitation_mm NUMERIC,
    wind_kmh         NUMERIC,
    temp_c           NUMERIC,
    sunshine_hours   NUMERIC
);

CREATE TABLE bookings_daily (
    play_date   DATE PRIMARY KEY,
    rounds      INT NOT NULL,
    buggies     INT NOT NULL,
    is_closed   BOOLEAN NOT NULL DEFAULT FALSE
);