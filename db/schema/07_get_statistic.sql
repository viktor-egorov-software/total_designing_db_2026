CREATE OR REPLACE FUNCTION egorov_food.get_statistic()
RETURNS TABLE (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
LANGUAGE sql
SET search_path TO egorov_food, pg_temp
AS $$
    -- CTE используется несколько раз: исходная таблица заказов читается один раз.
    WITH delivered_orders AS (
        SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount
        FROM orders o
        WHERE o.status = 'доставлен'
    ), order_totals AS (
        -- Суммы считаем до соединения с позициями, чтобы не умножать их на число блюд.
        SELECT restaurant_id,
               sum(total_amount) AS total_amount,
               avg(total_amount) AS avg_amount
        FROM delivered_orders
        GROUP BY restaurant_id
    ), product_quantities AS (
        SELECT o.restaurant_id, os.product_id, sum(os.quantity) AS quantity
        FROM delivered_orders o
        JOIN order_structure os ON os.order_id = o.order_id
        GROUP BY o.restaurant_id, os.product_id
    ), best_products AS (
        SELECT restaurant_id,
               (array_agg(product_id ORDER BY quantity DESC, random()))[1] AS product_id
        FROM product_quantities
        GROUP BY restaurant_id
    ), client_orders AS (
        -- Частота покупок клиента — число заказов, а не число позиций или порций.
        SELECT restaurant_id, client_id, count(*) AS order_count
        FROM delivered_orders
        GROUP BY restaurant_id, client_id
    ), best_clients AS (
        -- random() выбирает победителя только среди равных по основному показателю.
        SELECT restaurant_id,
               (array_agg(client_id ORDER BY order_count DESC, random()))[1] AS client_id
        FROM client_orders
        GROUP BY restaurant_id
    )
    SELECT r.restaurant_name,
           p.product_name AS best_product_name,
           coalesce(t.total_amount, 0) AS total_amount,
           t.avg_amount,
           c.login AS best_user
    FROM restaurant r
    LEFT JOIN order_totals t ON t.restaurant_id = r.restaurant_id
    LEFT JOIN best_products bp ON bp.restaurant_id = r.restaurant_id
    LEFT JOIN product p ON p.product_id = bp.product_id
    LEFT JOIN best_clients bc ON bc.restaurant_id = r.restaurant_id
    LEFT JOIN client c ON c.client_id = bc.client_id;
$$;
