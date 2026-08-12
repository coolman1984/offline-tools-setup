CREATE TABLE raw_sales(period VARCHAR, division VARCHAR, product VARCHAR, qty INTEGER, revenue DOUBLE, target_value DOUBLE);
INSERT INTO raw_sales VALUES
('2026-W31','VD','TV-A',120,96000,90000),
('2026-W31','MX','MOB-A',210,126000,130000),
('2026-W32','VD','TV-A',135,108000,95000),
('2026-W32','MX','MOB-A',225,135000,132000);
CREATE OR REPLACE VIEW v_period_summary AS
SELECT period,
       SUM(qty) AS qty,
       SUM(revenue) AS revenue,
       SUM(target_value) AS target_total,
       CASE WHEN SUM(target_value)=0 THEN NULL ELSE SUM(revenue)/SUM(target_value) END AS target_achievement
FROM raw_sales
GROUP BY period
ORDER BY period;
