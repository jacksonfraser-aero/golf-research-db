-- Backtest sensitivity: how does the strategy-vs-baseline result change
-- under different assumptions about induced demand (rounds that would NOT
-- have booked at full price, and only book because of the discount)?
--
-- induced_recovery_rate: share of a discount-fired day's rounds assumed
-- incremental. 0.0 = the conservative backtest (04_backtest.sql) -- pure
-- margin cost, no recovery. Higher values assume the discount genuinely
-- wins back otherwise-lost demand.

WITH decision AS (
    SELECT
        b.play_date,
        b.rounds AS actual_rounds,
        f.precipitation_mm > 2.0 AS discount_fired
    FROM bookings_daily b
    CROSS JOIN LATERAL (
        SELECT precipitation_mm
        FROM weather_forecast_snapshot wfs
        WHERE wfs.valid_date = b.play_date AND wfs.lead_days = 3
        ORDER BY wfs.knowledge_time DESC
        LIMIT 1
    ) f
    WHERE NOT b.is_closed
),
rates AS (
    SELECT unnest(ARRAY[0.0, 0.25, 0.5, 0.75, 1.0]) AS induced_recovery_rate
),
discounts AS (
    SELECT unnest(ARRAY[0.2, 0.4, 0.6]) AS discount_pct
)
SELECT
    r.induced_recovery_rate,
    d.discount_pct,
    ROUND(SUM(dec.actual_rounds * 50), 2) AS baseline_revenue,
    ROUND(SUM(
        CASE WHEN dec.discount_fired THEN
            -- non-incremental share: would have played anyway, still full price
            (dec.actual_rounds * (1 - r.induced_recovery_rate)) * 50
            -- incremental share: only books because of the discount
            + (dec.actual_rounds * r.induced_recovery_rate) * 50 * (1 - d.discount_pct)
            -- extra rounds recovered ON TOP of actual_rounds, at the discount price
            + (dec.actual_rounds * r.induced_recovery_rate) * 50 * (1 - d.discount_pct)
        ELSE
            dec.actual_rounds * 50
        END
    ), 2) AS strategy_revenue
FROM decision dec
CROSS JOIN rates r
CROSS JOIN discounts d
GROUP BY r.induced_recovery_rate, d.discount_pct
ORDER BY r.induced_recovery_rate, d.discount_pct;