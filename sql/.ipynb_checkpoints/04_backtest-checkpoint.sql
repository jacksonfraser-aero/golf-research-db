-- Backtest a forecast-driven discounting rule using ONLY point-in-time
-- correct data: for each play date, the forecast used is exactly what was
-- known 3 days before, via the same LATERAL pattern as forecast_as_known.
-- The pricing rule applied is whatever was in force on that play date,
-- looked up from the SCD Type 2 history — not today's rule applied
-- retroactively.

WITH decision AS (
    SELECT
        b.play_date,
        b.rounds          AS actual_rounds,
        f.precipitation_mm AS forecast_rain_3d_out,
        pr.discount_pct,
        pr.trigger_rain_mm
    FROM bookings_daily b
    CROSS JOIN LATERAL (
        SELECT precipitation_mm
        FROM weather_forecast_snapshot wfs
        WHERE wfs.valid_date = b.play_date
          AND wfs.lead_days = 3
        ORDER BY wfs.knowledge_time DESC
        LIMIT 1
    ) f
    JOIN pricing_rule_history pr
        ON pr.rule_name = 'standby_v1'
        AND b.play_date::timestamptz >= pr.valid_from
        AND (pr.valid_to IS NULL OR b.play_date::timestamptz < pr.valid_to)
    WHERE NOT b.is_closed
),
priced AS (
    SELECT
        *,
        forecast_rain_3d_out > trigger_rain_mm AS discount_fired,
        -- Illustrative revenue-per-round; edit to taste.
        50 AS rev_per_round,
        -- Assumption: only a share of a discount-triggered day's rounds are
        -- INCREMENTAL (i.e. would not have booked at full price). This is
        -- the one unavoidable, unobservable assumption in the whole
        -- backtest -- stated explicitly rather than hidden in a formula.
        0.5 AS incremental_share
    FROM decision
)
SELECT
    play_date,
    actual_rounds,
    forecast_rain_3d_out,
    discount_fired,
    ROUND(actual_rounds * rev_per_round, 2) AS baseline_revenue,
    ROUND(
        CASE WHEN discount_fired THEN
            -- rounds NOT assumed incremental: sold at full price anyway
            (actual_rounds * (1 - incremental_share)) * rev_per_round
            -- rounds assumed incremental: sold at the discounted price
            + (actual_rounds * incremental_share) * rev_per_round * (1 - discount_pct)
        ELSE
            actual_rounds * rev_per_round
        END, 2
    ) AS strategy_revenue
FROM priced
ORDER BY play_date;

-- Summary: total baseline vs strategy revenue, and the lift/(loss) from
-- applying the discount rule instead of static pricing.
WITH backtest AS (
    -- paste the query above here, or run 04_backtest.sql first and
    -- wrap it as a view/CTE if you want a one-shot summary query
    SELECT * FROM priced  -- placeholder if run interactively after the block above
)
SELECT
    SUM(baseline_revenue)  AS total_baseline_revenue,
    SUM(strategy_revenue)  AS total_strategy_revenue,
    ROUND(100.0 * (SUM(strategy_revenue) - SUM(baseline_revenue)) / SUM(baseline_revenue), 2) AS pct_uplift
FROM backtest;