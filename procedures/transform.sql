-- ==========================================
-- Procedure: PI_INGEST.TRANSFORM_PROC
-- Purpose:  Light transformations:
--   1) populate DIM_DATE from FACT_ORDER dates
--   2) normalize phone numbers in DIM_CUSTOMER
--   3) maintain SCD2 flags in DIM_CUSTOMER (set IS_ACTIVE / END_DATE)
--   4) recalc FACT_ORDER.TOTAL_AMOUNT from FACT_ORDER_ITEM
--   5) simple housekeeping (insert raw orders -> audit example)
-- Returns: summary string
-- ==========================================
CREATE OR REPLACE PROCEDURE PI_INGEST.TRANSFORM_PROC()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS
$$
var resultSummary = [];
try {
  // 1) Insert missing dates into DIM_DATE from FACT_ORDER
  var sql1 = `
    INSERT INTO PI_INGEST.DIM_DATE (DATE_KEY, YEAR, MONTH, DAY, DAY_OF_WEEK, IS_BUSINESS_DAY)
    SELECT DISTINCT CAST(ORDER_DATE::DATE AS DATE) AS DATE_KEY,
           YEAR(ORDER_DATE) AS YEAR,
           MONTH(ORDER_DATE) AS MONTH,
           DAY(ORDER_DATE) AS DAY,
           TO_CHAR(ORDER_DATE,'Day') AS DAY_OF_WEEK,
           CASE WHEN TO_CHAR(ORDER_DATE,'D') IN ('1','7') THEN FALSE ELSE TRUE END AS IS_BUSINESS_DAY
    FROM PI_INGEST.FACT_ORDER
    WHERE ORDER_DATE IS NOT NULL
      AND CAST(ORDER_DATE::DATE AS DATE) NOT IN (SELECT DATE_KEY FROM PI_INGEST.DIM_DATE);
  `;
  snowflake.createStatement({sqlText: sql1}).execute();
  resultSummary.push('DIM_DATE populated');

  // 2) Normalize phone numbers in DIM_CUSTOMER (remove non-digits)
  var sql2 = `
    UPDATE PI_INGEST.DIM_CUSTOMER
    SET PHONE = REGEXP_REPLACE(PHONE, '\\\\D', '')
    WHERE PHONE IS NOT NULL AND PHONE <> REGEXP_REPLACE(PHONE, '\\\\D', '');
  `;
  var r2 = snowflake.createStatement({sqlText: sql2}).execute();
  resultSummary.push('Phone normalization applied');

  // 2b) Optional: if phone length == 10, prefix country code 91 (example)
  var sql2b = `
    UPDATE PI_INGEST.DIM_CUSTOMER
    SET PHONE = '91' || PHONE
    WHERE PHONE IS NOT NULL AND LENGTH(PHONE) = 10;
  `;
  snowflake.createStatement({sqlText: sql2b}).execute();
  resultSummary.push('Phone country code normalization applied (len=10 -> prefixed)');

  // 3) SCD2 maintenance for DIM_CUSTOMER:
  //    Keep latest START_DATE as IS_ACTIVE='Y' and others 'N' with END_DATE set to (next newer START_DATE - 1 sec)
  var sql3 = `
    WITH cte AS (
      SELECT
        CUSTOMER_SK,
        CUSTOMER_ID,
        START_DATE,
        ROW_NUMBER() OVER (PARTITION BY CUSTOMER_ID ORDER BY START_DATE DESC) AS RN,
        LEAD(START_DATE) OVER (PARTITION BY CUSTOMER_ID ORDER BY START_DATE DESC) AS NEXT_START
      FROM PI_INGEST.DIM_CUSTOMER
    )
    UPDATE PI_INGEST.DIM_CUSTOMER AS d
    SET
      IS_ACTIVE = CASE WHEN c.RN = 1 THEN 'Y' ELSE 'N' END,
      END_DATE  = CASE WHEN c.RN = 1 THEN NULL ELSE DATEADD(second, -1, c.NEXT_START) END
    FROM cte c
    WHERE d.CUSTOMER_SK = c.CUSTOMER_SK;
  `;
  snowflake.createStatement({sqlText: sql3}).execute();
  resultSummary.push('SCD2 flags updated for DIM_CUSTOMER');

  // 4) Recalculate FACT_ORDER.TOTAL_AMOUNT from FACT_ORDER_ITEM LINE_TOTAL (defensive COALESCE)
  var sql4 = `
    UPDATE PI_INGEST.FACT_ORDER AS fo
    SET TOTAL_AMOUNT = COALESCE((
      SELECT SUM(foi.LINE_TOTAL) FROM PI_INGEST.FACT_ORDER_ITEM foi WHERE foi.ORDER_SK = fo.ORDER_SK
    ), 0)
    WHERE EXISTS (SELECT 1 FROM PI_INGEST.FACT_ORDER_ITEM foi WHERE foi.ORDER_SK = fo.ORDER_SK);
  `;
  snowflake.createStatement({sqlText: sql4}).execute();
  resultSummary.push('FACT_ORDER totals recalculated');

  // 5) Housekeeping: write a lightweight audit row into LOAD_AUDIT_LOG for this run
  var sql5 = `
    INSERT INTO PI_INGEST.LOAD_AUDIT_LOG (JOB_NAME, SOURCE_NAME, RECORDS_READ, RECORDS_INSERTED, RECORDS_UPDATED, RUN_STARTED_AT, RUN_ENDED_AT, STATUS, MESSAGE)
    VALUES ('TRANSFORM_PROC', 'PI_INGEST', 0, 0, 0, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 'SUCCESS', 'Light transformations applied');
  `;
  snowflake.createStatement({sqlText: sql5}).execute();
  resultSummary.push('Audit row inserted');

  return 'OK - ' + resultSummary.join(' | ');
}
catch (err) {
  // insert failure audit
  try {
    var sqlErr = `
      INSERT INTO PI_INGEST.LOAD_AUDIT_LOG (JOB_NAME, SOURCE_NAME, RECORDS_READ, RECORDS_INSERTED, RECORDS_UPDATED, RUN_STARTED_AT, RUN_ENDED_AT, STATUS, MESSAGE)
      VALUES ('TRANSFORM_PROC', 'PI_INGEST', 0, 0, 0, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 'FAILED', :1);
    `;
    var st = snowflake.createStatement({sqlText: sqlErr, binds: [err.message]});
    st.execute();
  } catch (e2) {
    // ignore audit insert failure
  }
  return 'ERROR - ' + err.message;
}
$$;
