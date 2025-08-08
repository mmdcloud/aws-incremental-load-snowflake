import sys
import boto3
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql.functions import col, max as spark_max

## Arguments passed from Glue job
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'catalog_database',
    'catalog_table',
    'snowflake_table',
    'snowflake_connection_name',
    'incremental_column'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# --- Step 1: Read source data from Glue Catalog ---
source_df = glueContext.create_dynamic_frame.from_catalog(
    database=args['catalog_database'],
    table_name=args['catalog_table']
).toDF()

# --- Step 2: Get last max value from Snowflake ---
sfOptions = {
    "sfURL"      : "<YOUR_ACCOUNT>.snowflakecomputing.com",
    "sfDatabase" : "<YOUR_DB>",
    "sfSchema"   : "<YOUR_SCHEMA>",
    "sfWarehouse": "<YOUR_WAREHOUSE>",
    "sfRole"     : "<YOUR_ROLE>",
    "sfConnection" : args['snowflake_connection_name']  # Glue connection name
}

# Read target table to find last incremental value
try:
    target_df = spark.read \
        .format("snowflake") \
        .options(**sfOptions) \
        .option("dbtable", args['snowflake_table']) \
        .load()
    last_value = target_df.agg(spark_max(col(args['incremental_column']))).collect()[0][0]
except Exception:
    last_value = None

# --- Step 3: Filter for incremental records ---
if last_value:
    incremental_df = source_df.filter(col(args['incremental_column']) > last_value)
else:
    incremental_df = source_df  # First run, load all data

# --- Step 4: Write incremental data to Snowflake ---
if incremental_df.count() > 0:
    incremental_df.write \
        .format("snowflake") \
        .options(**sfOptions) \
        .option("dbtable", args['snowflake_table']) \
        .mode("append") \
        .save()
else:
    print("No new data to load.")

job.commit()