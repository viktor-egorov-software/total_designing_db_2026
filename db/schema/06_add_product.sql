CREATE OR REPLACE PROCEDURE egorov_food.add_product(
    p_product_name varchar,
    p_product_category_id uuid,
    p_price numeric,
    p_restaurant_id uuid,
    p_photo_url text,
    p_status egorov_food.product_status,
    p_description text
)
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
BEGIN
    -- Для обязательных полей сообщаем, какой параметр не указан.
    IF p_product_name IS NULL THEN
        RAISE EXCEPTION 'Не указано название блюда';
    END IF;

    IF p_product_category_id IS NULL THEN
        RAISE EXCEPTION 'Не указана категория блюда';
    END IF;

    IF p_price IS NULL THEN
        RAISE EXCEPTION 'Не указана цена блюда';
    END IF;

    IF p_restaurant_id IS NULL THEN
        RAISE EXCEPTION 'Не указан ресторан';
    END IF;

    IF p_status IS NULL THEN
        RAISE EXCEPTION 'Не указан статус блюда';
    END IF;

    IF p_description IS NULL THEN
        RAISE EXCEPTION 'Не указано описание блюда';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM restaurant WHERE restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'Ресторан с ID % не существует', p_restaurant_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM product_category WHERE product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'Категория блюд с ID % не существует', p_product_category_id;
    END IF;

    IF p_price < 0 THEN
        RAISE EXCEPTION 'Цена блюда не может быть отрицательной';
    END IF;

    INSERT INTO product (product_name, product_category_id, price, restaurant_id,
                                     photo_url, status, description)
    VALUES (p_product_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_status, p_description);
END;
$$;
