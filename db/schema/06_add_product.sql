CREATE OR REPLACE PROCEDURE egorov_food.add_product(
    p_product_name varchar,
    p_product_category_id uuid,
    p_price numeric,
    p_restaurant_id uuid,
    p_photo_url text,
    p_rating numeric,
    p_status egorov_food.product_status,
    p_description text
)
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
BEGIN
    -- Для обязательных полей сообщаем, какой параметр не указан.
    IF p_product_name IS NULL THEN
        RAISE EXCEPTION 'Не указано название блюда'
            USING ERRCODE = '23502';
    END IF;

    IF p_product_category_id IS NULL THEN
        RAISE EXCEPTION 'Не указана категория блюда'
            USING ERRCODE = '23502';
    END IF;

    IF p_price IS NULL THEN
        RAISE EXCEPTION 'Не указана цена блюда'
            USING ERRCODE = '23502';
    END IF;

    IF p_restaurant_id IS NULL THEN
        RAISE EXCEPTION 'Не указан ресторан'
            USING ERRCODE = '23502';
    END IF;

    IF p_status IS NULL THEN
        RAISE EXCEPTION 'Не указан статус блюда'
            USING ERRCODE = '23502';
    END IF;

    IF p_description IS NULL THEN
        RAISE EXCEPTION 'Не указано описание блюда'
            USING ERRCODE = '23502';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM restaurant WHERE restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'Ресторан с ID % не существует', p_restaurant_id
            USING ERRCODE = '23503';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM product_category WHERE product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'Категория блюд с ID % не существует', p_product_category_id
            USING ERRCODE = '23503';
    END IF;

    IF p_price < 0 THEN
        RAISE EXCEPTION 'Цена блюда не может быть отрицательной'
            USING ERRCODE = '23514';
    END IF;

    IF p_rating NOT BETWEEN 0 AND 5 THEN
        RAISE EXCEPTION 'Рейтинг блюда должен быть от 0 до 5 или NULL'
            USING ERRCODE = '23514';
    END IF;

    -- Начальный рейтинг сохраняем как передан; при изменении отзывов его пересчитает триггер rating_change.
    INSERT INTO product (product_name, product_category_id, price, restaurant_id,
                         photo_url, rating, status, description)
    VALUES (p_product_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_rating, p_status, p_description);
END;
$$;
