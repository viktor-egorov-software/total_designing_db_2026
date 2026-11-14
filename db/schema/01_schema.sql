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
    login varchar NOT NULL UNIQUE,
    password varchar(32) NOT NULL CHECK (password ~ '^[0-9a-fA-F]{32}$'),
    phone_number varchar NOT NULL UNIQUE
);

CREATE TABLE address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar NOT NULL,
    house_number varchar NOT NULL,
    apartment_office varchar,
    UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office)
);

CREATE TABLE client_address (
    client_id uuid REFERENCES client (client_id),
    address_id uuid REFERENCES address (address_id),
    PRIMARY KEY (client_id, address_id)
);

CREATE TABLE restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar NOT NULL,
    address_id uuid NOT NULL UNIQUE REFERENCES address (address_id),
    description text NOT NULL,
    work_start time NOT NULL,
    work_end time NOT NULL CHECK (work_end > work_start),
    company_details text NOT NULL,
    rating numeric CHECK (rating BETWEEN 0 AND 5),
    status restaurant_status NOT NULL
);
