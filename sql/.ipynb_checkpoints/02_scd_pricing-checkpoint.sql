CREATE TABLE pricing_rule_history (
    id                BIGSERIAL PRIMARY KEY,
    rule_name         TEXT NOT NULL,
    discount_pct      NUMERIC NOT NULL,
    trigger_rain_mm   NUMERIC NOT NULL,
    trigger_lead_days INT NOT NULL,
    valid_from        TIMESTAMPTZ NOT NULL,
    valid_to          TIMESTAMPTZ,
    is_current        BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE OR REPLACE FUNCTION set_pricing_rule(
    p_name TEXT, p_discount NUMERIC, p_rain NUMERIC, p_lead INT
) RETURNS VOID AS $$
BEGIN
    UPDATE pricing_rule_history
    SET valid_to = now(), is_current = FALSE
    WHERE rule_name = p_name AND is_current = TRUE;

    INSERT INTO pricing_rule_history
        (rule_name, discount_pct, trigger_rain_mm, trigger_lead_days, valid_from)
    VALUES (p_name, p_discount, p_rain, p_lead, now());
END;
$$ LANGUAGE plpgsql;