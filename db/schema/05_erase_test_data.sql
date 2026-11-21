CREATE OR REPLACE PROCEDURE egorov_food.erase_test_data()
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
BEGIN
    TRUNCATE TABLE
        address, client, client_address, courier, courier_pay,
        restaurant, product_category, product,
        orders, order_structure, payment, review;
END;
$$;
