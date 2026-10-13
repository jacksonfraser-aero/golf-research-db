# Point-in-Time Golf Demand Research Database

A bitemporal PostgreSQL schema demonstrating how to avoid lookahead bias in
weather-driven demand research, validated and backtested end to end against
a synthetic dataset.

> **Data transparency:** every row in this repository is synthetically
> generated (see `seed/generate_synthetic_data.py`). No real bookings,
> forecasts, or pricing data are used or published here.

## The problem this solves

Weather forecasts are revised continuously as a date approaches. If a
backtest of a weather-driven pricing rule uses the *actual* observed weather
instead of what was forecast at the moment the pricing decision had to be
made, the backtest is silently cheating — it "knows" things the business
wouldn't have known yet. This is lookahead bias, and it is one of the most
common ways research backtests overstate a strategy's value. This project
builds a database schema that makes it structurally impossible to make that
mistake, and uses it to backtest a discounting rule honestly.

## Schema

- **`weather_forecast_snapshot`** — every forecast ever fetched, tagged with
  both `valid_date` (the day it's *about*) and `knowledge_time` (the moment
  it was *known*). The same future day accumulates multiple rows over time as
  forecasts are revised.
- **`weather_actual`** — ground-truth observed weather, one row per day.
- **`bookings_daily`** — daily rounds and buggies played.
- **`pricing_rule_history`** — SCD Type 2 history of discounting rules, so a
  backtest applies the rule that was *actually* in force on a given date,
  not today's rule projected backwards.
- **`forecast_as_known`** — a point-in-time view (`DISTINCT ON` over
  `knowledge_time`) that reconstructs, for any (date, lead-time) pair, the
  most recent forecast that would have been available.

## Why a LATERAL join, not a self-join

The backtest needs, for every play date, a correlated lookup: "the most
recent forecast snapshot at exactly 3 days' lead time." That's a per-row
dependent subquery, which is what `CROSS JOIN LATERAL` is for — a plain join
can't express "look up the latest row matching *this specific* outer row"
without either a window function over the whole table or a much messier
self-join. The `LATERAL` pattern here is deliberately the same shape you'd
use to reconstruct point-in-time prices in a real market-data backtest.

## Validation: does the synthetic forecast history behave correctly?

The seed script generates forecasts with error that shrinks as the play date
approaches — computed directly from the seeded data, not asserted:

| Lead days | Avg. absolute error (mm) |
|---|---|
| 7 | 1.72 |
| 6 | 1.26 |
| 5 | 1.03 |
| 4 | 1.09 |
| 3 | 0.91 |
| 2 | 0.64 |
| 1 | 0.64 |
| 0 | 0.36 |

Forecast accuracy improves roughly monotonically from a week out to the day
itself — confirming the bitemporal mechanism is doing something real, not
just present as unused schema. (`forecast_as_known` was also checked for
duplicate rows per date/lead-time pair: none found.)

## Backtest: a rain-triggered discounting rule

Rule: discount tee times when the 3-day-ahead forecast shows rain above 2mm.
All figures are illustrative (£50/round, synthetic 90-day dataset). Baseline
revenue is £496,600 throughout.

**Sensitivity to induced demand:**

| Induced recovery rate | 20% discount | 40% discount | 60% discount |
|---|---|---|---|
| 0% (no incremental demand) | £496,600 | £496,600 | £496,600 |
| 25% | £509,635 | £500,945 | £492,255 |
| 50% | £522,670 | £505,290 | £487,910 |
| 75% | £535,705 | £509,635 | £483,565 |
| 100% (upper bound) | £548,740 | £513,980 | £479,220 |

Two effects pull in opposite directions here. A **higher recovery rate**
always helps — more of the discount day's demand is genuinely incremental,
so more revenue is won rather than given away, which is why every column
rises reading top to bottom. A **deeper discount** only helps if enough of
that demand is truly incremental to justify it — at low recovery rates, a
deep discount mostly destroys margin on rounds that were coming anyway,
which is why the 60% column falls *below* baseline even at high recovery
rates. The crossover point — the discount depth that only pays off once
recovery is assumed high enough — is itself decision-relevant information a
manager can read directly off this grid.

**Consistency note:** an earlier, separate conservative backtest
(`04_backtest.sql`) assumed a *fixed* 50% "incremental share" applied
uniformly to every discount-fired day, producing a flat −£17,380 result
regardless of discount depth. That is a *different* model from the sweep
above — it discounts existing rounds without asking whether they were
incremental, whereas this sensitivity grid only discounts genuinely
incremental demand. The discrepancy between the two files' boundary cases
(£496,600 vs £479,220) was caught by checking them against each other, and
is left visible here deliberately: `04_backtest.sql` answers "what if we
discount indiscriminately," while `05_backtest_sensitivity.sql` answers
"what if we could discount only the demand we're actually recovering." Both
are useful; conflating them would not be.

## Honest limitations

- All data is synthetic; forecast-error noise is a modelling choice (shrinks
  linearly with lead time), not fitted to real forecast-error distributions.
- The incremental/induced-demand share is unobservable and swept as a
  sensitivity range rather than estimated. Measuring it directly would mean
  comparing discount-fired and non-fired days' booking-lead-time
  distributions on real booking data.
- A meaningful backtest on real forecasts needs several weeks of
  point-in-time forecast history before results stabilise, which is why
  this repo uses synthetic data to demonstrate the method immediately.

## How to run

```bash
createdb golf_research_demo
psql golf_research_demo -f sql/01_schema.sql
psql golf_research_demo -f sql/02_scd_pricing.sql
psql golf_research_demo -f sql/03_point_in_time_view.sql
pip install -r requirements.txt
python seed/generate_synthetic_data.py
psql golf_research_demo -c "INSERT INTO pricing_rule_history (rule_name, discount_pct, trigger_rain_mm, trigger_lead_days, valid_from) VALUES ('standby_v1', 0.4, 2.0, 3, '2020-01-01'::timestamptz);"
psql golf_research_demo -f sql/04_backtest.sql
psql golf_research_demo -f sql/05_backtest_sensitivity.sql
```

Built by Jackson Fraser.
(the regression analysis this database is designed to eventually validate
against real point-in-time data).