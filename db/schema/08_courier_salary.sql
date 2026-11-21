CREATE OR REPLACE PROCEDURE egorov_food.courier_salary()
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
DECLARE
    v_month timestamp := date_trunc('month', localtimestamp);
    v_year smallint := extract(year FROM v_month)::smallint;
    v_month_number smallint := extract(month FROM v_month)::smallint;
    v_salary record;
    v_amount numeric;
BEGIN
    FOR v_salary IN
        SELECT c.courier_id, c.status,
               p.coefficient_used IS NOT NULL AS payment_exists,
               coalesce(p.coefficient_used, c.coefficient) AS coefficient_used,
               count(o.order_id) AS deliveries,
               coalesce(sum(o.commission), 0) AS commission
        FROM courier c
        LEFT JOIN courier_pay p ON p.courier_id = c.courier_id
            AND p.year = v_year AND p.month = v_month_number
        -- LEFT JOIN сохраняет курьеров без доставок. В расчет попадают заказы с завершенной доставкой в текущем месяце.
        LEFT JOIN orders o ON o.courier_id = c.courier_id
            AND o.status = 'доставлен'
            AND o.delivery_timestamp >= v_month
            AND o.delivery_timestamp < v_month + interval '1 month'
        WHERE c.hire_date < v_month + interval '1 month'
          AND (c.status <> 'уволен' OR c.dismissal_date >= v_month)
        GROUP BY c.courier_id, p.coefficient_used
    LOOP
        v_amount := round(v_salary.coefficient_used * v_salary.commission, 2);
        IF v_salary.payment_exists THEN
            UPDATE courier_pay
            SET amount = v_amount
            WHERE year = v_year AND month = v_month_number
              AND courier_id = v_salary.courier_id;
        ELSE
            INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
            VALUES (v_year, v_month_number, v_salary.courier_id, v_amount, v_salary.coefficient_used);
        END IF;

        IF v_salary.status <> 'уволен' THEN
            UPDATE courier
            SET coefficient = CASE WHEN v_salary.deliveries > 500 THEN 0.5
                                   WHEN v_salary.deliveries > 250 THEN 0.3
                                   WHEN v_salary.deliveries > 150 THEN 0.2
                                   ELSE 0.1 END
            WHERE courier_id = v_salary.courier_id;
        END IF;
    END LOOP;
END;
$$;
