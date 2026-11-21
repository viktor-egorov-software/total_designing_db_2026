CREATE OR REPLACE FUNCTION egorov_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
DECLARE
    affected_id uuid;
    affected_type review_entity_type;
BEGIN
    IF TG_OP = 'DELETE' THEN
        affected_id := OLD.entity_id;
        affected_type := OLD.entity_type;
    ELSE
        affected_id := NEW.entity_id;
        affected_type := NEW.entity_type;
    END IF;

    -- При удалении последнего отзыва AVG без строк вернет NULL (BR-9.7).
    IF affected_type = 'блюдо' THEN
        -- Пока считаем рейтинг, другой пересчёт этого блюда ждёт.
        -- Блокировку берём отдельным запросом до чтения отзывов.
        PERFORM 1 FROM product
        WHERE product_id = affected_id
        FOR NO KEY UPDATE;

        UPDATE product
        SET rating = (
            SELECT avg(rating) FROM review
            WHERE entity_type = 'блюдо' AND entity_id = affected_id
        )
        WHERE product_id = affected_id;
    ELSIF affected_type = 'ресторан' THEN
        PERFORM 1 FROM restaurant
        WHERE restaurant_id = affected_id
        FOR NO KEY UPDATE;

        UPDATE restaurant
        SET rating = (
            SELECT avg(rating) FROM review
            WHERE entity_type = 'ресторан' AND entity_id = affected_id
        )
        WHERE restaurant_id = affected_id;
    END IF;
    -- Для заказа агрегата нет, рейтинг хранится в самом отзыве.

    RETURN NULL;
END;
$$;

CREATE TRIGGER rating_change
AFTER INSERT OR UPDATE OR DELETE ON egorov_food.review
FOR EACH ROW EXECUTE FUNCTION egorov_food.rating_change();
