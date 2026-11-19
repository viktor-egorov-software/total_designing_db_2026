CREATE OR REPLACE PROCEDURE egorov_food.erase_test_data()
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
BEGIN
    -- Сначала удаляем данные, которые ссылаются на заказы и курьеров.
    DELETE FROM review;
    DELETE FROM payment;
    DELETE FROM order_structure;
    DELETE FROM courier_pay;

    -- После удаления позиций временно остаются заказы без блюд.
    -- Удаляем и заказы до отложенной проверки наличия позиций.
    DELETE FROM orders;

    -- Блюда ссылаются на рестораны и категории, связи адресов — на клиентов.
    DELETE FROM product;
    DELETE FROM restaurant;
    DELETE FROM product_category;
    DELETE FROM client_address;
    DELETE FROM client;
    DELETE FROM courier;

    -- Адреса удаляем последними: на них больше никто не ссылается.
    DELETE FROM address;
END;
$$;
