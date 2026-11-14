SET search_path TO egorov_food;

CREATE FUNCTION check_order_structure_restaurant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM orders o
        JOIN product p ON p.product_id = NEW.product_id
        WHERE o.order_id = NEW.order_id
          AND o.restaurant_id <> p.restaurant_id
    ) THEN
        RAISE EXCEPTION 'Блюдо должно принадлежать ресторану заказа'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER order_structure_restaurant_check
BEFORE INSERT OR UPDATE OF order_id, product_id ON order_structure
FOR EACH ROW EXECUTE FUNCTION check_order_structure_restaurant();

CREATE FUNCTION reject_restaurant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.restaurant_id <> OLD.restaurant_id THEN
        RAISE EXCEPTION 'Нельзя изменить ресторан в таблице %. Создайте новую запись', TG_TABLE_NAME
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER orders_restaurant_check
BEFORE UPDATE OF restaurant_id ON orders
FOR EACH ROW EXECUTE FUNCTION reject_restaurant_change();

CREATE TRIGGER product_restaurant_check
BEFORE UPDATE OF restaurant_id ON product
FOR EACH ROW EXECUTE FUNCTION reject_restaurant_change();

CREATE FUNCTION check_order_has_items()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
DECLARE
    checked_order_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'orders' THEN
        checked_order_id := NEW.order_id;
    ELSE
        checked_order_id := OLD.order_id;
    END IF;

    IF EXISTS (SELECT 1 FROM orders WHERE order_id = checked_order_id)
       AND NOT EXISTS (SELECT 1 FROM order_structure WHERE order_id = checked_order_id) THEN
        RAISE EXCEPTION 'Заказ должен содержать хотя бы одну позицию'
            USING ERRCODE = '23514';
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER orders_items_check
AFTER INSERT OR UPDATE OF order_id ON orders
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_has_items();

CREATE CONSTRAINT TRIGGER order_structure_items_check
AFTER DELETE OR UPDATE OF order_id ON order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_has_items();

CREATE FUNCTION reject_payment_order_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.order_id <> OLD.order_id THEN
        RAISE EXCEPTION 'Нельзя изменить заказ попытки оплаты. Создайте новую попытку'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER payment_order_check
BEFORE UPDATE OF order_id ON payment
FOR EACH ROW EXECUTE FUNCTION reject_payment_order_change();

CREATE FUNCTION calculate_order_pay_status(checked_order_id uuid)
RETURNS order_pay_status
LANGUAGE sql
SET search_path TO egorov_food, pg_temp
AS $$
    SELECT CASE
        WHEN count(CASE WHEN status = 'успех' THEN 1 END) > 0 THEN 'оплачен'
        WHEN count(*) = 0
          OR count(CASE WHEN status = 'в_обработке' THEN 1 END) > 0 THEN 'ожидает'
        ELSE 'ошибка'
    END::order_pay_status
    FROM payment
    WHERE order_id = checked_order_id;
$$;

CREATE FUNCTION check_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM orders
        WHERE order_id = NEW.order_id
          AND pay_status <> calculate_order_pay_status(order_id)
    ) THEN
        RAISE EXCEPTION 'Статус оплаты заказа должен соответствовать попыткам оплаты'
            USING ERRCODE = '23514';
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER orders_pay_status_check
AFTER INSERT OR UPDATE OF order_id, pay_status ON orders
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_order_pay_status();

CREATE FUNCTION refresh_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
BEGIN
    UPDATE orders
    SET pay_status = calculate_order_pay_status(order_id)
    WHERE order_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;

    RETURN NULL;
END;
$$;

CREATE TRIGGER payment_pay_status_refresh
AFTER INSERT OR DELETE OR UPDATE OF status ON payment
FOR EACH ROW EXECUTE FUNCTION refresh_order_pay_status();

CREATE FUNCTION check_review_entity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
DECLARE
    checked_order_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'review' THEN
        checked_order_id := NEW.order_id;
    ELSE
        checked_order_id := OLD.order_id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM review r
        JOIN orders o ON o.order_id = r.order_id
        WHERE r.order_id = checked_order_id
          AND (
              (r.entity_type = 'блюдо' AND NOT EXISTS (
                  SELECT 1
                  FROM order_structure os
                  WHERE os.order_id = r.order_id AND os.product_id = r.entity_id
              ))
              OR (r.entity_type = 'ресторан' AND r.entity_id <> o.restaurant_id)
              OR (r.entity_type = 'заказ' AND r.entity_id <> r.order_id)
          )
    ) THEN
        RAISE EXCEPTION 'Объект отзыва должен относиться к указанному заказу'
            USING ERRCODE = '23514';
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER review_entity_check
AFTER INSERT OR UPDATE OF order_id, entity_id, entity_type ON review
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_review_entity();

CREATE CONSTRAINT TRIGGER order_structure_review_check
AFTER DELETE OR UPDATE OF order_id, product_id ON order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_review_entity();
