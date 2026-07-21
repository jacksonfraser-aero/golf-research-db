"""Generate a synthetic bitemporal dataset: 90 days of bookings, weather,
and — the interesting part — a full history of forecast revisions per day,
with realistic uncertainty that shrinks as the play date approaches.
No real operational data is used anywhere in this repository."""

import datetime as dt
import numpy as np
import psycopg2

rng = np.random.default_rng(42)
conn = psycopg2.connect(dbname="golf_research_demo")
cur = conn.cursor()

start = dt.date.today() - dt.timedelta(days=90)

for day_offset in range(90):
    valid_date = start + dt.timedelta(days=day_offset)
    actual_rain = float(max(0, rng.exponential(2.0) - 1.0))
    actual_wind = float(rng.normal(22, 8))
    actual_temp = float(12 + 8 * np.sin((day_offset / 90) * np.pi) + rng.normal(0, 2))
    actual_sun = float(max(0, rng.normal(6, 3)))

    cur.execute("""INSERT INTO weather_actual VALUES (%s,%s,%s,%s,%s)
                   ON CONFLICT DO NOTHING""",
                (valid_date, actual_rain, actual_wind, actual_temp, actual_sun))

    # forecast history: noisier further out, converging to "actual" as lead -> 0
    for lead in range(7, -1, -1):
        knowledge_time = dt.datetime.combine(valid_date - dt.timedelta(days=lead), dt.time(9, 0))
        noise = rng.normal(0, 0.3 + 0.15 * lead)
        forecast_rain = max(0, actual_rain + noise * max(actual_rain, 1))
        cur.execute("""
            INSERT INTO weather_forecast_snapshot
                (valid_date, knowledge_time, lead_days, precipitation_mm, wind_kmh, temp_c, sunshine_hours)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT DO NOTHING
        """, (valid_date, knowledge_time, lead, round(forecast_rain, 1),
              round(actual_wind + rng.normal(0, 3), 1),
              round(actual_temp + rng.normal(0, 1), 1),
              round(max(0, actual_sun + rng.normal(0, 1)), 1)))

    # bookings, reusing the same weather-sensitivity formula as the public regression project
    base = 90 + 40 * np.sin((day_offset / 90) * np.pi)
    rounds = max(0, round(base - 2.5 * actual_rain - 0.3 * max(0, actual_wind - 20) + rng.normal(0, 10)))
    cur.execute("""INSERT INTO bookings_daily VALUES (%s,%s,%s,%s)
                   ON CONFLICT DO NOTHING""",
                (valid_date, rounds, round(rounds * 0.2), False))

conn.commit()
print("Seeded 90 days of synthetic bitemporal history.")