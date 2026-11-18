SET search_path TO egorov_food, pg_temp;

CREATE OR REPLACE VIEW how_much_money AS
WITH RECURSIVE monthly_orders AS (
    -- Доход относится к месяцу завершения доставки.
    SELECT date_trunc('month', o.delivery_timestamp) AS month_start,
           sum(o.order_amount) AS sum_no_commission,
           sum(o.total_amount) AS sum_with_commission
    FROM orders o
    WHERE o.status = 'доставлен'
    GROUP BY date_trunc('month', o.delivery_timestamp)
), months AS (
    SELECT min(month_start) AS month_start, max(month_start) AS last_month
    FROM monthly_orders
    -- При отсутствии доставок начальной строки нет, и отчёт остаётся пустым.
    HAVING count(*) > 0

    UNION ALL

    SELECT month_start + interval '1 month', last_month
    FROM months
    WHERE month_start < last_month
), monthly_pay AS (
    SELECT p.year, p.month, sum(p.amount) AS courier_pay
    FROM courier_pay p
    GROUP BY p.year, p.month
), monthly_totals AS (
    -- Заказы и выплаты уже посчитаны отдельно по месяцам.
    SELECT m.month_start,
           coalesce(o.sum_no_commission, 0) AS sum_no_commission,
           coalesce(o.sum_with_commission, 0) AS sum_with_commission,
           coalesce(o.sum_with_commission - o.sum_no_commission, 0) AS commission,
           coalesce(p.courier_pay, 0) AS courier_pay
    FROM months m
    LEFT JOIN monthly_orders o ON o.month_start = m.month_start
    LEFT JOIN monthly_pay p ON p.year = date_part('year', m.month_start)
                          AND p.month = date_part('month', m.month_start)
), with_previous AS (
    -- Пустые месяцы уже добавлены с нулевой комиссией.
    -- LAG берёт комиссию предыдущего месяца, даже если в нём не было доставок.
    SELECT t.*,
           lag(t.commission) OVER (ORDER BY t.month_start) AS prev_commission
    FROM monthly_totals t
)
SELECT to_char(month_start, 'YYYY-MM') AS year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission - prev_commission AS commission_diff,
       courier_pay,
       commission - courier_pay AS net_profit
FROM with_previous
ORDER BY month_start;
