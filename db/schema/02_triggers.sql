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
