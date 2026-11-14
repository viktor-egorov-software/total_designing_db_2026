CREATE SCHEMA egorov_food;

SET search_path TO egorov_food;

CREATE TYPE restaurant_status AS ENUM (
    'активен', 'неактивен'
);

CREATE TYPE product_status AS ENUM (
    'доступно', 'нет_в_наличии', 'архив'
);

CREATE TYPE courier_status AS ENUM (
    'свободен', 'занят', 'на_доставке', 'уволен'
);

CREATE TYPE order_status AS ENUM (
    'создан', 'готовится', 'в_доставке', 'доставлен', 'отменён'
);

CREATE TYPE order_pay_status AS ENUM (
    'ожидает', 'оплачен', 'ошибка'
);

CREATE TYPE payment_status AS ENUM (
    'успех', 'ошибка', 'в_обработке'
);

CREATE TYPE payment_type AS ENUM (
    'карта', 'наличные', 'безнал'
);

CREATE TYPE review_entity_type AS ENUM (
    'блюдо', 'ресторан', 'заказ'
);

CREATE TABLE client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(128) NOT NULL UNIQUE,
    password varchar(32) NOT NULL CHECK (password ~ '^[0-9a-fA-F]{32}$'),
    phone_number varchar(32) NOT NULL UNIQUE
);

CREATE TABLE address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(256) NOT NULL,
    house_number varchar(32) NOT NULL,
    apartment_office varchar(32),
    UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office)
);

CREATE TABLE client_address (
    client_id uuid REFERENCES client (client_id),
    address_id uuid REFERENCES address (address_id),
    PRIMARY KEY (client_id, address_id)
);

CREATE TABLE restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(256) NOT NULL,
    address_id uuid NOT NULL UNIQUE REFERENCES address (address_id),
    description text NOT NULL,
    work_start time NOT NULL,
    work_end time NOT NULL CHECK (work_end > work_start),
    company_details text NOT NULL,
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    status restaurant_status NOT NULL
);

CREATE TABLE product_category (
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(256) NOT NULL
);

CREATE TABLE product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(256) NOT NULL,
    product_category_id uuid NOT NULL REFERENCES product_category (product_category_id),
    price numeric(12,2) NOT NULL CHECK (price >= 0),
    restaurant_id uuid NOT NULL REFERENCES restaurant (restaurant_id),
    photo_url text,
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    status product_status NOT NULL,
    description text NOT NULL
);

CREATE TABLE courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio varchar(256) NOT NULL,
    phone_number varchar(32) NOT NULL,
    status courier_status NOT NULL,
    hire_date date NOT NULL,
    dismissal_date date,
    coefficient numeric(2,2) NOT NULL DEFAULT 0.1 CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL)
);

CREATE TABLE courier_pay (
    year smallint,
    month smallint CHECK (month BETWEEN 1 AND 12),
    courier_id uuid REFERENCES courier (courier_id),
    amount numeric(12,2) NOT NULL CHECK (amount >= 0),
    coefficient_used numeric(2,2) NOT NULL CHECK (coefficient_used BETWEEN 0.1 AND 0.5),
    PRIMARY KEY (year, month, courier_id)
);

CREATE TABLE orders (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL REFERENCES courier (courier_id),
    client_id uuid NOT NULL,
    address_id uuid NOT NULL,
    restaurant_id uuid NOT NULL REFERENCES restaurant (restaurant_id),
    order_timestamp timestamp NOT NULL,
    delivery_timestamp timestamp,
    order_amount numeric(12,2) NOT NULL,
    commission numeric(12,2) GENERATED ALWAYS AS (round(order_amount * 0.1, 2)) STORED NOT NULL,
    total_amount numeric(12,2) GENERATED ALWAYS AS (order_amount + round(order_amount * 0.1, 2)) STORED NOT NULL,
    status order_status NOT NULL,
    pay_status order_pay_status NOT NULL,
    description text NOT NULL,
    FOREIGN KEY (client_id, address_id) REFERENCES client_address (client_id, address_id),
    CHECK (total_amount >= 1000),
    CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL),
    CHECK (delivery_timestamp >= order_timestamp)
);

CREATE TABLE order_structure (
    order_id uuid REFERENCES orders (order_id),
    product_id uuid REFERENCES product (product_id),
    quantity numeric(8,3) NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (order_id, product_id)
);
