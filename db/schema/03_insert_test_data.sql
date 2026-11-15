CREATE OR REPLACE PROCEDURE egorov_food.insert_test_data(value int)
LANGUAGE plpgsql
SET search_path TO egorov_food, pg_temp
AS $$
DECLARE
    -- Только ID текущего вызова: новые данные не меняют прежние выплаты и рейтинги.
    v_clients uuid[];
    v_addresses uuid[];
    v_restaurants uuid[];
    v_categories uuid[];
    v_couriers uuid[];
    v_courier_statuses courier_status[];
    -- v_products и v_prices вмещают ID блюд и их цены для всех ресторанов
    v_products uuid[];
    v_prices numeric[];
    v_orders uuid[];
    -- Начальный индекс блюд ресторана в v_products и v_prices.
    v_product_starts int[];
    -- Количество блюд в ресторане.
    v_product_counts int[];
    v_quantities numeric[];
    v_words text[];
    v_cyrillic text := 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
    v_latin text := 'abcdefghijklmnopqrstuvwxyz';
    v_login_base text;
    v_login_suffix text;
    v_login_attempt int;
    v_suffix_number int;
    v_street text;
    v_house bigint;
    v_apartment text;
    v_description text;
    v_category_name text;
    v_fio text;
    v_id uuid;
    v_order_id uuid;
    v_status order_status;
    v_courier_status courier_status;
    v_other_statuses order_status[];
    -- Общая переменная для телефонов клиентов и курьеров: при вставке
    -- добавляем '+' и получаем формат +7 и 10 цифр. Начальный номер случайный,
    -- далее берём следующий номер с возвратом к началу диапазона.
    v_phone bigint := 70000000000 + floor(random() * 10000000000)::bigint;

    v_now timestamp := localtimestamp;
    -- Для генерации берем 6 календарных месяцев, включая текущий.
    v_first_month timestamp := date_trunc('month', localtimestamp) - interval '5 months';
    v_month timestamp;
    v_month_end timestamp;
    v_order_time timestamp;
    v_delivery_time timestamp;
    v_work_start time;
    v_amount numeric;
    v_quantity numeric;
    v_client_index int;
    v_restaurant_index int;
    v_courier_index int;
    v_product_index int;
    v_local_product int;
    v_attempt_count int;
    v_delivered_count int := 0;
    v_min_delivered int;
    v_review record;
    i int;
    j int;
    k int;
BEGIN
    IF value IS NULL OR value <= 0 THEN
        RAISE EXCEPTION 'value должен быть положительным целым числом'
            USING ERRCODE = '22023';
    END IF;

    -- 1. Адреса: первые value — ресторанам, остальные 4 * value — клиентам.
    -- Строки для названий улиц собираем из случайных букв кириллического алфавита, длина от 8 до 32 символов.
    -- floor(random() * N) + 1 даёт 1..N даже при random() = 0.
    -- Номер квартиры оставляем NULL с вероятностью 15%.
    FOR i IN 1..value * 5 LOOP
        SELECT string_agg(substring(v_cyrillic, floor(random() * 33)::int + 1, 1),
                          '' ORDER BY letter)
        INTO v_street
        FROM generate_series(1, floor(random() * 25)::int + 8) AS letters(letter);
        v_house := floor(random() * 200)::int + 1;
        v_apartment := CASE WHEN random() < 0.15 THEN NULL
                           ELSE (floor(random() * 100)::int + 1)::text END;
        LOOP
            INSERT INTO address (street, house_number, apartment_office)
            VALUES (v_street, v_house::text, v_apartment)
            ON CONFLICT DO NOTHING
            RETURNING address_id INTO v_id;
            EXIT WHEN v_id IS NOT NULL;
            -- При коллизии адреса инкрементируем номер дома и пробуем снова.
            v_house := v_house + 1;
        END LOOP;
        v_addresses[i] := v_id;
    END LOOP;

    -- 2. Клиенты и их связи с адресами.
    -- ID новых сущностей генерируются через DEFAULT exts.uuid_generate_v4().
    -- При коллизии любого уникального поля происходит еще одна попытка вставки и так до успеха.
    -- Строки для логина собираем из случайных букв латинского алфавита, длина основы от 8 до 20 символов.
    -- При коллизии к основе добавляем буквенный суффикс a..z, aa..az и далее.
    -- Телефон меняем на следующий в диапазоне; пароль и ID генерируем заново.
    FOR i IN 1..value LOOP
        SELECT string_agg(substring(v_latin, floor(random() * 26)::int + 1, 1),
                          '' ORDER BY letter)
        INTO v_login_base
        FROM generate_series(1, floor(random() * 13)::int + 8) AS letters(letter);
        v_login_attempt := 0;
        LOOP
            v_login_suffix := '';
            v_suffix_number := v_login_attempt;
            WHILE v_suffix_number > 0 LOOP
                v_login_suffix := substring(v_latin, (v_suffix_number - 1) % 26 + 1, 1)
                                  || v_login_suffix;
                v_suffix_number := (v_suffix_number - 1) / 26;
            END LOOP;
            v_phone := 70000000000 + (v_phone - 70000000000 + 1) % 10000000000;
            INSERT INTO client (login, password, phone_number)
            VALUES (v_login_base || v_login_suffix, md5(random()::text), '+' || v_phone::text)
            ON CONFLICT DO NOTHING
            RETURNING client_id INTO v_id;
            EXIT WHEN v_id IS NOT NULL;
            v_login_attempt := v_login_attempt + 1;
        END LOOP;
        v_clients[i] := v_id;

        -- Четыре адреса на клиента.
        FOR j IN 1..4 LOOP
            INSERT INTO client_address (client_id, address_id)
            VALUES (v_clients[i], v_addresses[value + (i - 1) * 4 + j]);
        END LOOP;
    END LOOP;

    -- 3. Категории блюд. Название из 5..24 кириллических букв.
    FOR i IN 1..value LOOP
        SELECT string_agg(substring(v_cyrillic, floor(random() * 33)::int + 1, 1),
                          '' ORDER BY letter)
        INTO v_category_name
        FROM generate_series(1, floor(random() * 20)::int + 5) AS letters(letter);
        INSERT INTO product_category (product_category_name)
        VALUES (v_category_name) RETURNING product_category_id INTO v_id;
        v_categories[i] := v_id;
    END LOOP;

    -- 4. Курьеры. ФИО из трёх кириллических слов по 8..20 букв.
    -- Между словами по одному пробелу: всего два пробела и 26..62 символа.
    FOR i IN 1..value LOOP
        FOR k IN 1..3 LOOP
            SELECT string_agg(substring(v_cyrillic, floor(random() * 33)::int + 1, 1),
                              '' ORDER BY letter)
            INTO v_description
            FROM generate_series(1, floor(random() * 13)::int + 8) AS letters(letter);
            v_words[k] := v_description;
        END LOOP;
        v_fio := concat_ws(' ', v_words[1], v_words[2], v_words[3]);
        v_phone := 70000000000 + (v_phone - 70000000000 + 1) % 10000000000;
        -- В enum первые три статуса рабочие, четвёртый — увольнение.
        -- Первый курьер гарантированно работает даже при value = 1 (BR-6.6).
        v_courier_status := (enum_range(NULL::courier_status))[
            floor(random() * CASE WHEN i = 1 THEN 3 ELSE 4 END)::int + 1];
        INSERT INTO courier (fio, phone_number, status, hire_date, dismissal_date)
        VALUES (v_fio, '+' || v_phone::text, v_courier_status,
                v_first_month::date,
                CASE WHEN v_courier_status = 'уволен' THEN v_now::date END)
        RETURNING courier_id INTO v_id;
        v_couriers[i] := v_id;
        v_courier_statuses[i] := v_courier_status;
    END LOOP;

    -- 5. Рестораны. Используем первые value адресов из блока 1.
    FOR i IN 1..value LOOP
        -- Три независимых слова: название, описание, реквизиты.
        -- Длины 5..24 заведомо помещаются в фактические varchar(256).
        FOR k IN 1..3 LOOP
            SELECT string_agg(substring(v_cyrillic, floor(random() * 33)::int + 1, 1),
                              '' ORDER BY letter)
            INTO v_description
            FROM generate_series(1, floor(random() * 20)::int + 5) AS letters(letter);
            v_words[k] := v_description;
        END LOOP;
        -- Времена зависимы: закрытие всегда позже открытия и до полуночи.
        v_work_start := time '06:00' + floor(random() * 6) * interval '1 hour';
        INSERT INTO restaurant (restaurant_name, address_id, description,
                                work_start, work_end, company_details, status)
        VALUES (v_words[1], v_addresses[i], v_words[2],
                v_work_start, v_work_start + interval '10 hours', v_words[3],
                (enum_range(NULL::restaurant_status))[floor(random() * 2)::int + 1])
        RETURNING restaurant_id INTO v_id;
        v_restaurants[i] := v_id;
    END LOOP;

    -- 6. Меню. По одному блюду обязательно, остальные 4 * value распределяем
    -- случайно. Всего ровно 5 * value, но рестораны имеют разные размеры меню.
    FOR i IN 1..value LOOP
        v_product_counts[i] := 1;
    END LOOP;
    FOR i IN 1..value * 4 LOOP
        v_restaurant_index := floor(random() * value)::int + 1;
        v_product_counts[v_restaurant_index] := v_product_counts[v_restaurant_index] + 1;
    END LOOP;
    v_product_index := 0;
    FOR i IN 1..value LOOP
        v_product_starts[i] := v_product_index + 1;
        FOR j IN 1..v_product_counts[i] LOOP
            v_product_index := v_product_index + 1;
            FOR k IN 1..2 LOOP
                SELECT string_agg(substring(v_cyrillic, floor(random() * 33)::int + 1, 1),
                                  '' ORDER BY letter)
                INTO v_description
                FROM generate_series(1, floor(random() * 20)::int + 5) AS letters(letter);
                v_words[k] := v_description;
            END LOOP;
            -- Цена 50..1500 рублей, до копейки: не подгоняем под минимум заказа.
            -- Положительная нижняя граница обеспечивает завершение набора суммы.
            -- Нулевая цена разрешена схемой, но в этой выборке не генерируется.
            v_prices[v_product_index] := (5000 + floor(random() * 145001)::int) / 100.0;
            INSERT INTO product (product_name, product_category_id, price,
                                 restaurant_id, photo_url, status, description)
            VALUES (v_words[1], v_categories[floor(random() * value)::int + 1],
                    v_prices[v_product_index], v_restaurants[i],
                    CASE WHEN random() < 0.5 THEN NULL
                         ELSE 'https://example.org/food/' || md5(random()::text) || '.jpg' END,
                    (enum_range(NULL::product_status))[floor(random() * 3)::int + 1],
                    v_words[2])
            RETURNING product_id INTO v_id;
            v_products[v_product_index] := v_id;
        END LOOP;
    END LOOP;

    -- 7. Заказы и оплаты. Около 70% заказов доставлены; дополнительно гарантируем
    -- минимум ceil(5 * value / 3) доставленных заказов. У каждого есть хотя бы
    -- три объекта отзыва: блюдо, ресторан, заказ. Так хватит места для 5 * value
    -- разных отзывов только после доставки, даже при маленьком value.
    v_min_delivered := (value * 5 + 2) / 3;
    SELECT array_agg(s) INTO v_other_statuses
    FROM unnest(enum_range(NULL::order_status)) AS statuses(s)
    WHERE s <> 'доставлен';

    FOR i IN 1..value * 5 LOOP
        v_client_index := (i - 1) / 5 + 1;
        v_restaurant_index := floor(random() * value)::int + 1;
        v_courier_index := floor(random() * value)::int + 1;
        IF random() < 0.7 OR v_delivered_count + (value * 5 - i + 1) <= v_min_delivered THEN
            v_status := (enum_range(NULL::order_status))[4];
            v_delivered_count := v_delivered_count + 1;
        ELSE
            v_status := v_other_statuses[floor(random() * cardinality(v_other_statuses))::int + 1];
        END IF;
        IF v_courier_statuses[v_courier_index] = 'уволен'
           AND v_status NOT IN ('доставлен', 'отменён') THEN
            v_courier_index := 1;
        END IF;

        -- Месяцы распределяем по кругу. Оставляем минимум микросекунду до v_now
        -- для отзыва строго после доставки. Следующий месяц в интервал не входит.
        v_month := v_first_month + ((i - 1) % 6) * interval '1 month';
        v_month_end := v_month + interval '1 month' - interval '1 microsecond';
        IF v_month_end > v_now - interval '1 microsecond' THEN
            v_month_end := v_now - interval '1 microsecond';
        END IF;
        IF v_month_end <= v_month THEN
            -- В первый момент месяца ещё нет места для исторической доставки.
            v_month := v_month - interval '1 month';
            v_month_end := v_month + interval '1 month' - interval '1 microsecond';
        END IF;
        v_order_time := v_month + random() * (v_month_end - v_month);
        v_delivery_time := CASE WHEN v_status = 'доставлен'
            THEN v_order_time + random() * (v_month_end - v_order_time) END;

        -- Количества по индексу блюда внутри ресторана. Новый заказ начинает
        -- с нулей, включая случай меню из одного блюда.
        v_quantities := ARRAY[]::numeric[];
        FOR j IN 1..v_product_counts[v_restaurant_index] LOOP
            v_quantities[j] := 0;
        END LOOP;
        v_amount := 0;
        -- Набираем позиции, пока итог с комиссией не достигнет 1000 (BR-7.11).
        -- Формула округления совпадает с GENERATED-колонками orders.
        WHILE round(v_amount, 2) + round(round(v_amount, 2) * 0.1, 2) < 1000 LOOP
            v_local_product := floor(random() * v_product_counts[v_restaurant_index])::int + 1;
            v_product_index := v_product_starts[v_restaurant_index] + v_local_product - 1;
            v_quantity := (floor(random() * 24)::int + 1) * 0.125;
            -- Повтор блюда увеличивает количество, а не создаёт дубль пары.
            v_quantities[v_local_product] := v_quantities[v_local_product] + v_quantity;
            v_amount := v_amount + v_prices[v_product_index] * v_quantity;
            -- Каждый проход добавляет >= 50 * 0.125 = 6.25 рубля.
            -- Поэтому цикл завершится даже при постоянном random() = 0.
        END LOOP;

        SELECT string_agg(substring(v_cyrillic, floor(random() * 33)::int + 1, 1),
                          '' ORDER BY letter)
        INTO v_description
        FROM generate_series(1, floor(random() * 61)::int + 20) AS letters(letter);
        INSERT INTO orders (courier_id, client_id, address_id, restaurant_id,
                            order_timestamp, delivery_timestamp, order_amount,
                            status, description)
        VALUES (v_couriers[v_courier_index], v_clients[v_client_index],
                v_addresses[value + (v_client_index - 1) * 4 + ((i - 1) % 5) % 4 + 1],
                v_restaurants[v_restaurant_index], v_order_time, v_delivery_time,
                round(v_amount, 2), v_status, v_description)
        RETURNING order_id INTO v_order_id;
        v_orders[i] := v_order_id;

        FOR j IN 1..v_product_counts[v_restaurant_index] LOOP
            IF v_quantities[j] > 0 THEN
                INSERT INTO order_structure (order_id, product_id, quantity)
                VALUES (v_order_id, v_products[v_product_starts[v_restaurant_index] + j - 1],
                        v_quantities[j]);
            END IF;
        END LOOP;

        -- Согласованное с пользователем отступление от BR-11.7:
        -- успешных платежей ровно 5 * value, ошибки добавляются сверх этого числа.
        -- На заказ 1..3 попытки; у первого минимум две, чтобы пример ошибок
        -- присутствовал и при value = 1. Последняя попытка всегда успешна.
        v_attempt_count := floor(random() * 3)::int + 1;
        IF i = 1 THEN
            v_attempt_count := floor(random() * 2)::int + 2;
        END IF;
        FOR j IN 1..v_attempt_count LOOP
            INSERT INTO payment (order_id, payment_type, transaction_id,
                                 transaction_timestamp, status)
            VALUES (v_order_id,
                    (enum_range(NULL::payment_type))[floor(random() * 3)::int + 1],
                    exts.uuid_generate_v4(),
                    v_order_time + (coalesce(v_delivery_time, v_now) - v_order_time)
                                   * (j::double precision / (v_attempt_count + 1)),
                    (enum_range(NULL::payment_status))[
                        CASE WHEN j = v_attempt_count THEN 1 ELSE 2 END]);
        END LOOP;
        -- Сумма оплаты определяется через orders.total_amount (модель FOOD-101).
        -- Статус обновляет payment_pay_status_refresh: сначала ошибка, затем
        -- оплачен. Отложенная проверка проверит итог в конце транзакции.
    END LOOP;

    -- 8. Отзывы. Перечисляем допустимые пары «заказ — объект», затем выбираем
    -- 5 * value без повторов. Недоставленные заказы не участвуют.
    -- Клиент определяется через заказ, отдельного client_id в review нет.
    FOR v_review IN
        WITH delivered AS (
            SELECT order_id, restaurant_id, delivery_timestamp FROM orders
            WHERE order_id = ANY(v_orders) AND status = 'доставлен'
        ), candidates AS (
            SELECT d.order_id, d.delivery_timestamp, os.product_id AS entity_id,
                   (enum_range(NULL::review_entity_type))[1] AS entity_type
            FROM delivered d JOIN order_structure os USING (order_id)
            UNION ALL
            SELECT order_id, delivery_timestamp, restaurant_id,
                   (enum_range(NULL::review_entity_type))[2] FROM delivered
            UNION ALL
            SELECT order_id, delivery_timestamp, order_id,
                   (enum_range(NULL::review_entity_type))[3] FROM delivered
        )
        SELECT * FROM candidates ORDER BY random() LIMIT value * 5
    LOOP
        SELECT string_agg(substring(v_cyrillic, floor(random() * 33)::int + 1, 1),
                          '' ORDER BY letter)
        INTO v_description
        FROM generate_series(1, floor(random() * 61)::int + 20) AS letters(letter);
        INSERT INTO review (review_timestamp, entity_id, entity_type, order_id,
                            description, photo_url, rating)
        VALUES (v_review.delivery_timestamp + interval '1 microsecond'
                + random() * (v_now - v_review.delivery_timestamp - interval '1 microsecond'),
                v_review.entity_id, v_review.entity_type, v_review.order_id, v_description,
                CASE WHEN random() < 0.5 THEN NULL
                     ELSE 'https://example.org/review/' || md5(random()::text) || '.jpg' END,
                floor(random() * 5)::int + 1);
    END LOOP;

    -- 9. Временный расчёт рейтингов по фактическим отзывам (BR-9.6–9.7).
    -- TODO FOOD-105: после реализации и проверки rating_change удалить эти
    -- два UPDATE. Триггер будет пересчитывать рейтинги автоматически при INSERT
    -- отзывов; напрямую вызывать trigger-функцию из генератора не нужно.
    -- Пока FOOD-105 нет, сохраняем согласованность данных этим блоком.
    -- Объекты без отзывов остаются с NULL; прежние порции не изменяются.
    UPDATE product p
    SET rating = r.rating
    FROM (SELECT entity_id, avg(rating) AS rating FROM review
          WHERE entity_type = 'блюдо' AND entity_id = ANY(v_products)
          GROUP BY entity_id) r
    WHERE p.product_id = r.entity_id;

    UPDATE restaurant p
    SET rating = r.rating
    FROM (SELECT entity_id, avg(rating) AS rating FROM review
          WHERE entity_type = 'ресторан' AND entity_id = ANY(v_restaurants)
          GROUP BY entity_id) r
    WHERE p.restaurant_id = r.entity_id;

    -- 10. История выплат: коэффициент 0.1 в первом месяце, затем из прошлого.
    -- Сначала выплата и coefficient_used, лишь потом изменение коэффициента.
    -- Уволенные сегодня участвовали в прошлых расчётах, но после месяца
    -- увольнения коэффициент больше не меняется (BR-10.6).
    FOR v_month IN SELECT generate_series(v_first_month,
                        date_trunc('month', v_now), interval '1 month') LOOP
        INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
        SELECT extract(year FROM v_month)::smallint,
               extract(month FROM v_month)::smallint, c.courier_id,
               round(c.coefficient * coalesce(sum(o.commission), 0), 2),
               c.coefficient
        FROM courier c
        -- LEFT JOIN сохраняет курьера без доставок; coalesce даёт выплату 0.
        -- Учитываем комиссии, не полные суммы; созданные и отменённые исключены.
        LEFT JOIN orders o ON o.courier_id = c.courier_id
            AND o.status = 'доставлен'
            AND o.delivery_timestamp >= v_month
            AND o.delivery_timestamp < v_month + interval '1 month'
        WHERE c.courier_id = ANY(v_couriers)
        GROUP BY c.courier_id;

        UPDATE courier c
        SET coefficient = CASE WHEN s.deliveries > 500 THEN 0.5
                               WHEN s.deliveries > 250 THEN 0.3
                               WHEN s.deliveries > 150 THEN 0.2
                               ELSE 0.1 END
        FROM (
            SELECT c.courier_id, count(o.order_id) AS deliveries
            FROM courier c
            LEFT JOIN orders o ON o.courier_id = c.courier_id
                AND o.status = 'доставлен'
                AND o.delivery_timestamp >= v_month
                AND o.delivery_timestamp < v_month + interval '1 month'
            WHERE c.courier_id = ANY(v_couriers)
            GROUP BY c.courier_id
        ) s
        WHERE c.courier_id = s.courier_id
          AND (c.dismissal_date IS NULL
               OR c.dismissal_date >= (v_month + interval '1 month')::date);
    END LOOP;
END;
$$;
