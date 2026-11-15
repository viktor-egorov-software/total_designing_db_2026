CREATE OR REPLACE FUNCTION egorov_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
DECLARE
    affected record;
BEGIN
    -- При переносе отзыва учитываем старый и новый объект. UNION убирает повтор,
    -- если переноса не было, а изменились только оценка, текст или другие атрибуты отзыва.
    FOR affected IN
        SELECT OLD.entity_type AS entity_type, OLD.entity_id AS entity_id
        WHERE TG_OP IN ('UPDATE', 'DELETE')
        UNION
        SELECT NEW.entity_type, NEW.entity_id
        WHERE TG_OP IN ('INSERT', 'UPDATE')
        ORDER BY entity_type, entity_id
    LOOP
        -- При удалении последнего отзыва AVG без строк вернет NULL (BR-9.7).
        IF affected.entity_type = 'блюдо' THEN
            -- Пока считаем рейтинг, другой пересчёт этого блюда ждёт.
            -- Блокировку берём отдельным запросом до чтения отзывов.
            PERFORM 1 FROM product
            WHERE product_id = affected.entity_id
            FOR NO KEY UPDATE;

            UPDATE product
            SET rating = (
                SELECT avg(rating) FROM review
                WHERE entity_type = 'блюдо' AND entity_id = affected.entity_id
            )
            WHERE product_id = affected.entity_id;
        ELSIF affected.entity_type = 'ресторан' THEN
            PERFORM 1 FROM restaurant
            WHERE restaurant_id = affected.entity_id
            FOR NO KEY UPDATE;

            UPDATE restaurant
            SET rating = (
                SELECT avg(rating) FROM review
                WHERE entity_type = 'ресторан' AND entity_id = affected.entity_id
            )
            WHERE restaurant_id = affected.entity_id;
        END IF;
        -- Для заказа агрегата нет, рейтинг хранится в самом отзыве.
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE TRIGGER rating_change
AFTER INSERT OR UPDATE OR DELETE ON egorov_food.review
FOR EACH ROW EXECUTE FUNCTION egorov_food.rating_change();
