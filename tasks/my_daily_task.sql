-- Replace MY_WAREHOUSE with your warehouse name.
-- Example schedule: hourly at minute 0 (UTC). Change cron as desired.
CREATE OR REPLACE TASK PI_INGEST.TASK_RUN_TRANSFORM
  WAREHOUSE = MY_WAREHOUSE
  SCHEDULE = 'USING CRON 0 * * * * UTC'
  COMMENT = 'Hourly light-transform task invoking PI_INGEST.TRANSFORM_PROC'
AS
  CALL PI_INGEST.TRANSFORM_PROC();


ALTER TASK PI_INGEST.TASK_RUN_TRANSFORM RESUME;