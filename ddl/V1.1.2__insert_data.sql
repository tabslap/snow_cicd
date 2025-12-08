-- Insert sample data into PI_INGEST tables
USE SCHEMA PI_INGEST;

-------------------------------------
-- 1) DIM_DATE (small sample values)
-------------------------------------
INSERT INTO DIM_DATE (DATE_KEY, YEAR, MONTH, DAY, DAY_OF_WEEK, IS_BUSINESS_DAY)
VALUES
  ('2025-01-01', 2025, 1, 1,  'Wednesday', FALSE),
  ('2025-01-02', 2025, 1, 2,  'Thursday',  TRUE),
  ('2025-01-03', 2025, 1, 3,  'Friday',    TRUE),
  ('2025-01-04', 2025, 1, 4,  'Saturday',  FALSE);

-------------------------------------
-- 2) DIM_CUSTOMER (SCD2 sample)
-------------------------------------
INSERT INTO DIM_CUSTOMER
  (CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, CITY, COUNTRY)
VALUES
  (1001, 'Arjun', 'Mehta', 'arjun.mehta@email.com', '9876543210', 'Mumbai', 'India'),
  (1002, 'Sara',  'Khan',  'sara.khan@email.com',  '9988776655', 'Delhi',  'India'),
  (1003, 'John',  'Doe',   'john.doe@email.com',   '9000000001', 'London', 'UK');

-- Example SCD2 change (customer 1001 moved city)
INSERT INTO DIM_CUSTOMER
  (CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, CITY, COUNTRY, IS_ACTIVE, START_DATE)
VALUES
  (1001, 'Arjun', 'Mehta', 'arjun.mehta@email.com', '9876543210',
   'Pune', 'India', 'Y', CURRENT_TIMESTAMP());

-------------------------------------
-- 3) DIM_PRODUCT (SCD2 sample)
-------------------------------------
INSERT INTO DIM_PRODUCT (PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESC, CATEGORY, PRICE)
VALUES
  ('P101', 'Laptop', '14-inch business laptop', 'Electronics', 65000),
  ('P102', 'Headphones', 'Noise-cancelling',     'Electronics', 4000),
  ('P103', 'Office Chair', 'Ergonomic chair',    'Furniture',   12000);

-- SCD2 update to product P101
INSERT INTO DIM_PRODUCT
  (PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESC, CATEGORY, PRICE, IS_ACTIVE)
VALUES
  ('P101', 'Laptop', '14-inch laptop – Updated price', 'Electronics', 62000, 'Y');

-------------------------------------
-- 4) FACT_ORDER (link to customer)
-------------------------------------
INSERT INTO FACT_ORDER (ORDER_ID, CUSTOMER_SK, ORDER_DATE, ORDER_STATUS, TOTAL_AMOUNT, CURRENCY)
SELECT 'O5001', CUSTOMER_SK, CURRENT_TIMESTAMP(), 'Completed', 78000, 'INR'
FROM DIM_CUSTOMER WHERE CUSTOMER_ID = 1001 AND IS_ACTIVE = 'Y';

INSERT INTO FACT_ORDER (ORDER_ID, CUSTOMER_SK, ORDER_DATE, ORDER_STATUS, TOTAL_AMOUNT, CURRENCY)
SELECT 'O5002', CUSTOMER_SK, CURRENT_TIMESTAMP(), 'Pending', 16000, 'INR'
FROM DIM_CUSTOMER WHERE CUSTOMER_ID = 1002 AND IS_ACTIVE = 'Y';

-------------------------------------
-- 5) FACT_ORDER_ITEM (joins product + order)
-------------------------------------
-- Order O5001
INSERT INTO FACT_ORDER_ITEM (ORDER_SK, PRODUCT_SK, QUANTITY, UNIT_PRICE, LINE_TOTAL)
SELECT
  f.ORDER_SK,
  p.PRODUCT_SK,
  1,
  p.PRICE,
  p.PRICE
FROM FACT_ORDER f
JOIN DIM_PRODUCT p ON p.PRODUCT_ID = 'P101' AND p.IS_ACTIVE = 'Y'
WHERE f.ORDER_ID = 'O5001';

-- Order O5002
INSERT INTO FACT_ORDER_ITEM (ORDER_SK, PRODUCT_SK, QUANTITY, UNIT_PRICE, LINE_TOTAL)
SELECT
  f.ORDER_SK,
  p.PRODUCT_SK,
  4,
  p.PRICE,
  4 * p.PRICE
FROM FACT_ORDER f
JOIN DIM_PRODUCT p ON p.PRODUCT_ID = 'P103' AND p.IS_ACTIVE = 'Y'
WHERE f.ORDER_ID = 'O5002';

-------------------------------------
-- 6) FACT_PAYMENT
-------------------------------------
INSERT INTO FACT_PAYMENT (PAYMENT_ID, ORDER_SK, PAYMENT_DATE, PAYMENT_METHOD, AMOUNT, CURRENCY, PAYMENT_STATUS)
SELECT
  'PAY9001', ORDER_SK, CURRENT_TIMESTAMP(), 'Card', 78000, 'INR', 'Success'
FROM FACT_ORDER WHERE ORDER_ID = 'O5001';

INSERT INTO FACT_PAYMENT (PAYMENT_ID, ORDER_SK, PAYMENT_DATE, PAYMENT_METHOD, AMOUNT, CURRENCY, PAYMENT_STATUS)
SELECT
  'PAY9002', ORDER_SK, CURRENT_TIMESTAMP(), 'UPI', 16000, 'INR', 'Pending'
FROM FACT_ORDER WHERE ORDER_ID = 'O5002';

-------------------------------------
-- 7) RAW_ORDERS
-------------------------------------
INSERT INTO RAW_ORDERS (RAW_ORDER_ID, ORDER_JSON)
VALUES
  ('R1', PARSE_JSON('{"order_id": "O5001", "total": 78000}')),
  ('R2', PARSE_JSON('{"order_id": "O5002", "total": 16000}'));

-------------------------------------
-- 8) LOAD_AUDIT_LOG
-------------------------------------
INSERT INTO LOAD_AUDIT_LOG
  (JOB_NAME, SOURCE_NAME, RECORDS_READ, RECORDS_INSERTED, RECORDS_UPDATED, RUN_STARTED_AT, RUN_ENDED_AT, STATUS)
VALUES
  ('CUSTOMER_LOAD', 'CRM', 1000, 998, 2, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 'SUCCESS');
