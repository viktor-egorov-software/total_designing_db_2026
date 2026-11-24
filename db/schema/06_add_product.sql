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
    INSERT INTO product (product_name, product_category_id, price, restaurant_id,
                                     photo_url, status, description)
    VALUES (p_product_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_status, p_description);
END;
$$;
