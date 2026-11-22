# Протокол для самопроверки

Заполняется по желанию. 

По данному протоколу работа будет проверяться преподавателем.

**Если на каком-то этапе функционал оказывается нерабочим, значит учащийся проигнорировал обязательное тестирование и работа может быть отправлена на доработку без проверки и комментариев или по работе может быть проставлен незачет, если лимит доработок исчерпан.**

## Окружение

| Параметр | Значение                   |
|---|----------------------------|
| PostgreSQL version | `SELECT version();` → 17.2 |
| Дата проверки | 22.11.2026                 |
| Схема | `egorov_food`              |
| Роль-аудитор | `inspector`                |

Все проверки — под `inspector`, если не указано иное.

Заполняй «Факт» и «Вердикт» по каждой проверке. «Вердикт»: `OK` / `FAIL: <что именно>`.

---

## A. Подготовка

### A.1. Восстановление бэкапа

Ожидается: без ошибок.
Факт: без ошибок.
Вердикт: OK

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO egorov_food, exts;
SELECT current_user;
```

Ожидается: `inspector`.
Факт: `inspector`.
Вердикт: OK

---

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `<фамилия>_food`.
Факт: `egorov_food`.
Вердикт: OK

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.
Факт: `uuid-ossp`, схема `exts`.
Вердикт: OK

### B.3. Все 12 исходных таблиц + N после нормализации

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'egorov_food'
ORDER BY table_name;
```

Ожидается: `address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` (12 + N штук).
Факт: `address`, `client`, `client_address`, `courier`, `courier_pay`, `orders` (`order` зарезервировано), `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review`, `how_much_money` (12 таблиц + 1 представление).
Вердикт: OK

### B.4. Все PK — `uuid`

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'egorov_food'
  AND column_name LIKE '%_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.
Факт: пусто.
Вердикт: OK

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'egorov_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.
Факт: 8 типов со значениями из constraints.md.
Вердикт: OK

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'egorov_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: не менее 15 FK, все из erd.md.
Факт: 13 FK.
Вердикт: FAIL —  в схеме 13 внешних ключей при требуемом минимуме 15.

Один FK убран при нормализации `review`, ещё два отдельных FK заказа объединены в один для проверки пары «клиент–адрес»,
чтобы адрес гарантированно относился к клиенту.

### B.7. Пароль — MD5

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.
Факт: 5 hex-строк с `len = 32`.
Вердикт: OK

Выполнялось после C.2, так как для выполнения запроса таблица уже должна быть наполнена тестовыми данными.

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: без ошибок.
Вердикт: OK

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.
Факт: без ошибок.
Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "orders"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: 10, 10, 10, 10, 50, 50, 50, 50, 50.
Факт: 10, 10, 10, 10, 50, 50, 50, 50, 50.
Вердикт: OK

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: 10 ресторанных адресов, 50 всего → 40 клиентских.
Факт: 10 ресторанных адресов, 50 всего → 40 клиентских.
Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT 'client' AS table_name, count(*) AS rows_with_empty_values
FROM client
WHERE login = '' OR password = '' OR phone_number = ''
UNION ALL
SELECT 'address', count(*)
FROM address
WHERE street = '' OR house_number = ''
UNION ALL
SELECT 'restaurant', count(*)
FROM restaurant
WHERE restaurant_name = '' OR inn = '' OR ogrn = '' OR bank_account = ''
UNION ALL
SELECT 'product_category', count(*)
FROM product_category
WHERE product_category_name = ''
UNION ALL
SELECT 'product', count(*)
FROM product
WHERE product_name = ''
UNION ALL
SELECT 'courier', count(*)
FROM courier
WHERE last_name = '' OR first_name = '' OR phone_number = '';
```

Ожидается: 0.
Факт: Во всех строках 0.
Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT 'client' AS table_name, count(*) AS rows_with_forbidden_nulls
FROM client
WHERE client_id IS NULL OR login IS NULL OR password IS NULL OR phone_number IS NULL
UNION ALL
SELECT 'address', count(*)
FROM address
WHERE address_id IS NULL OR street IS NULL OR house_number IS NULL
UNION ALL
SELECT 'client_address', count(*)
FROM client_address
WHERE client_id IS NULL OR address_id IS NULL
UNION ALL
SELECT 'restaurant', count(*)
FROM restaurant
WHERE restaurant_id IS NULL OR restaurant_name IS NULL OR address_id IS NULL
   OR description IS NULL OR work_start IS NULL OR work_end IS NULL OR inn IS NULL
   OR ogrn IS NULL OR bank_account IS NULL OR status IS NULL
UNION ALL
SELECT 'product_category', count(*)
FROM product_category
WHERE product_category_id IS NULL OR product_category_name IS NULL
UNION ALL
SELECT 'product', count(*)
FROM product
WHERE product_id IS NULL OR product_name IS NULL OR product_category_id IS NULL
   OR price IS NULL OR restaurant_id IS NULL OR status IS NULL OR description IS NULL
UNION ALL
SELECT 'courier', count(*)
FROM courier
WHERE courier_id IS NULL OR last_name IS NULL OR first_name IS NULL
   OR phone_number IS NULL OR status IS NULL OR hire_date IS NULL
   OR coefficient IS NULL
UNION ALL
SELECT 'courier_pay', count(*)
FROM courier_pay
WHERE year IS NULL OR month IS NULL OR courier_id IS NULL OR amount IS NULL
   OR coefficient_used IS NULL
UNION ALL
SELECT 'orders', count(*)
FROM orders
WHERE order_id IS NULL OR client_id IS NULL OR address_id IS NULL
   OR restaurant_id IS NULL OR order_timestamp IS NULL OR order_amount IS NULL
   OR commission IS NULL OR total_amount IS NULL OR status IS NULL
   OR pay_status IS NULL
UNION ALL
SELECT 'order_structure', count(*)
FROM order_structure
WHERE order_id IS NULL OR product_id IS NULL OR quantity IS NULL
UNION ALL
SELECT 'payment', count(*)
FROM payment
WHERE payment_id IS NULL OR order_id IS NULL OR payment_type IS NULL
   OR transaction_id IS NULL OR transaction_timestamp IS NULL OR status IS NULL
UNION ALL
SELECT 'review', count(*)
FROM review
WHERE review_id IS NULL OR review_timestamp IS NULL OR entity_id IS NULL
   OR entity_type IS NULL OR order_id IS NULL OR description IS NULL OR rating IS NULL;
```

Ожидается: 0.
Факт: Во всех строках 0.
Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.
Факт: 6.
Вердикт: OK

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

```sql
SELECT cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM "orders" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year  from o.order_timestamp) = cp.year
             AND extract(month from o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM courier_pay cp
LIMIT 20;
```

Ожидается: `amount = expected_amount` в каждой строке.
Факт: `amount = expected_amount` в каждой строке.
Вердикт: OK

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
```

Ожидается: без ошибок, данные добавляются или заменяются (по решению студента, задокументированному в constraints.md).
Факт: без ошибок, данные добавляются (задокументированно в constraints.md).
Вердикт: OK

---

## D. Проверки бизнес-правил на сгенерированных данных

### D.1. Все FK валидны (нет orphans)

```sql
SELECT 'order_structure → order' AS fk, count(*) AS orphans
FROM order_structure os
         LEFT JOIN "orders" o ON os.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_structure → product', count(*)
FROM order_structure os
         LEFT JOIN product p ON os.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'payment → order', count(*)
FROM payment pmt
         LEFT JOIN "orders" o ON pmt.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'review → order', count(*)
FROM review r
         LEFT JOIN "orders" o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'courier_pay → courier', count(*)
FROM courier_pay cp
         LEFT JOIN courier c ON cp.courier_id = c.courier_id
WHERE c.courier_id IS NULL
UNION ALL
SELECT 'client_address → client', count(*)
FROM client_address ca
         LEFT JOIN client c ON ca.client_id = c.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'client_address → address', count(*)
FROM client_address ca
         LEFT JOIN address a ON ca.address_id = a.address_id
WHERE a.address_id IS NULL;
```

Ожидается: все 0.
Факт: все 0.
Вердикт: OK

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "orders" WHERE total_amount < 1000;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "orders" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "orders"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "orders"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "orders" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "orders" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS cnt
FROM payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) != 1;
```

Ожидается: пусто.
Факт: пусто.
Вердикт: OK

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "orders" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.
Факт: PostgreSQL вернул ошибку `42703` — столбец `p.amount` не существует.
Вердикт: FAIL — запрос D.9 неприменим к структуре таблиц. Сумма попытки оплаты берётся из `orders.total_amount` по ссылке `payment.order_id`.

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто.
Вердикт: OK

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто.
Вердикт: OK

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

```sql
-- product.rating = AVG(review.rating) по отзывам на блюдо
SELECT p.product_id, p.rating,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE p.rating IS NOT NULL
LIMIT 20;
```

Ожидается: `rating = expected`.
Факт: `rating = expected`.
Вердикт: OK

---

## E. Функции и процедуры

### E.1. `add_product` — успешный вызов

```sql
SELECT count(*) AS before FROM product;

DO $$
DECLARE
    v_restaurant_id uuid;
    v_category_id uuid;
BEGIN
    SELECT restaurant_id INTO v_restaurant_id FROM restaurant LIMIT 1;
    SELECT product_category_id INTO v_category_id FROM product_category LIMIT 1;

    CALL add_product(
        p_product_name => 'Тестовое блюдо',
        p_product_category_id => v_category_id,
        p_price => 250,
        p_restaurant_id => v_restaurant_id,
        p_photo_url => NULL,
        p_status => 'доступно',
        p_description => 'Описание'
    );
END;
$$;

SELECT count(*) AS after FROM product;
```

Ожидается: `after = before + 1`.
Факт: 551 = 550 + 1 (с исправленным запросом).
Вердикт: OK

По BR-9.6 рейтинг блюда равен средней оценке по отзывам на него. У нового блюда
отзывов ещё нет, поэтому его рейтинг равен `NULL` (BR-9.7). Процедура
`add_product` не принимает параметр `p_rating`. При добавлении, изменении или
удалении отзыва триггер `rating_change` пересчитывает рейтинг.

### E.2. `add_product` — падает на несуществующий ресторан

```sql
DO $$
DECLARE
    v_category_id uuid;
BEGIN
    SELECT product_category_id INTO v_category_id FROM product_category LIMIT 1;

    CALL add_product(
        p_product_name => 'Тестовое блюдо',
        p_product_category_id => v_category_id,
        p_price => 250,
        p_restaurant_id => '00000000-0000-0000-0000-000000000000',
        p_photo_url => NULL,
        p_status => 'доступно',
        p_description => 'Описание'
    );
END;
$$;
```

Ожидается: ошибка с внятным сообщением.
Факт: SQL Error [P0001]: ОШИБКА: Ресторан с ID 00000000-0000-0000-0000-000000000000 не существует.
Вердикт: OK

### E.3. `rating_change` — пересчитывает рейтинг

```sql
-- Выбрать блюдо с рейтингом и заказ, в котором на него ещё нет отзыва
SELECT os.order_id, os.product_id, p.rating
FROM order_structure os
JOIN product p ON p.product_id = os.product_id
WHERE p.rating IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM review r
      WHERE r.order_id = os.order_id AND r.entity_id = os.product_id AND r.entity_type = 'блюдо'
  )
LIMIT 1;

-- Вставить отзыв на это блюдо
INSERT INTO review (review_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
VALUES (
    exts.uuid_generate_v4(),
    localtimestamp,
    <product_id>,
    'блюдо',
    <order_id>,
    'Тестовый отзыв',
    5
)
RETURNING review_id;

SELECT rating FROM product WHERE product_id = <product_id>;
```

Ожидается: `rating` пересчитан.
Факт: было 4, стало 4,5 (с исправленным запросом).
Вердикт: OK

Из `INSERT` убран `client_id`: автор отзыва определяется через `review.order_id`.
Блюдо и заказ выбираются вместе из `order_structure`, чтобы блюдо входило в заказ (BR-9.2).
Для этой пары ещё можно оставить отзыв (BR-9.5). `RETURNING review_id` выдаёт ID для удаления отзыва в E.4.

### E.4. `rating_change` — удаление отзыва

```sql
-- Удалить отзыв из E.3
DELETE FROM review WHERE review_id = <review_id>;

SELECT rating FROM product WHERE product_id = <product_id>;
```

Ожидается: если других отзывов нет — `rating IS NULL`; иначе — пересчитан.
Факт: было 4,5, стало 4.
Вердикт: OK

### E.5. `get_statistic()`

```sql
SELECT * FROM get_statistic();
```

Ожидается:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (не NULL при наличии доставленных заказов).

Факт:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (NULL, если у ресторана нет доставленных заказов).

Вердикт: OK

### E.6. `courier_salary()`

```sql
-- До
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;

CALL courier_salary();

-- После
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;
SELECT year, month, courier_id, amount, coefficient_used
FROM courier_pay
ORDER BY year DESC, month DESC, courier_id
LIMIT 20;
```

Ожидается:
- `courier.coefficient` пересчитан для работающих (по BR-10.2).
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Факт:
- `courier.coefficient` пересчитан для работающих (по BR-10.2) — остался 0,1 из-за числа заказов.
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Вердикт: OK

### E.7. `courier_salary()` — повторный вызов

```sql
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);

CALL courier_salary();
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);
```

Ожидается: количество не изменилось (idempotency / обновление).
Факт: количество не изменилось — было 110, стало 110
Вердикт: OK

---

## F. Представление `how_much_money`

### F.1. Колонки

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = '<фамилия>_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).
Факт: ___

### F.2. Месяцы покрыты

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: месяцы от первого доставленного заказа до последнего (не пропущено ни одного).
Факт: ___

### F.3. Месяцы без заказов присутствуют (BR-11.9)

```sql
SELECT year_month FROM how_much_money
WHERE sum_no_commission = 0 OR sum_no_commission IS NULL;
```

Ожидается: если в какие-то месяцы заказов не было — они есть в результате.
Факт: ___

### F.4. Корректность сумм

```sql
SELECT year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission_diff,
       courier_pay,
       net_profit
FROM how_much_money
ORDER BY year_month
LIMIT 10;
```

Ожидается:
- `commission = sum_with_commission - sum_no_commission`.
- `commission_diff = commission - prev_commission` (NULL для первого месяца).
- `net_profit = commission - courier_pay`.

Факт: ___

---

## G. Права `inspector`

### G.1. Права на схему

```sql
SELECT
    nspname AS schema_name,
    has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
    has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = '<фамилия>_food';
```

Ожидается: `<фамилия>_food`, `true`, `true` (полный доступ).
Факт: ___

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = '<фамилия>_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).
Факт: ___

### G.3. `information_schema` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM information_schema.tables
WHERE table_schema = '<фамилия>_food';
RESET ROLE;
```

Ожидается: 12 + N (количество таблиц).
Факт: ___

### G.4. `pg_catalog` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = '<фамилия>_food';
RESET ROLE;
```

Ожидается: 12 + N.
Факт: ___

### G.5. Все процедуры/функции работают под `inspector`

```sql
SET ROLE inspector;
SET search_path TO <фамилия>_food, exts;

CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;

RESET ROLE;
```

Ожидается: без `permission denied`.
Факт: ___

---

## H. Оптимизация `get_statistic` (BR-11.8)

### H.1. `EXPLAIN ANALYZE` — паттерн «избыточные подзапросы»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS cnt,
       (SELECT coalesce(sum(commission), 0) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS commission_sum
FROM courier c;
```

Ожидается: два SubPlan, каждый — скан `"order"`. Время растёт линейно от числа курьеров.
Факт: время ___ мс, план ___

### H.2. `EXPLAIN ANALYZE` — паттерн «один JOIN»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS cnt,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM courier c
LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один `Hash Right Join` / `Hash Left Join`, один скан `"order"`. Время меньше, чем в H.1.
Факт: время ___ мс, план ___

### H.3. Применить к `get_statistic`

```sql
EXPLAIN ANALYZE SELECT * FROM get_statistic();
```

Ожидается: без `LATERAL`, без множественных подзапросов к одной таблице, без оконных функций там, где хватает агрегата.
Факт: ___

---

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.
Факт: ___

### I.2. Повторный `erase_test_data` не падает

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: ___

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.
Факт: ___

