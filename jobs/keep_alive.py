# keep_alive.py
from pyspark.sql import SparkSession
import time

spark = SparkSession.builder \
    .appName("KeepAlive") \
    .getOrCreate()

# Create a simple streaming job
from pyspark.sql.functions import lit
from pyspark.sql.types import StructType, StructField, StringType

def generate_data():
    import time
    while True:
        yield (str(time.time()),)
        time.sleep(60)

schema = StructType([StructField("timestamp", StringType(), True)])
df = spark.createDataFrame(generate_data(), schema)

df.writeStream \
    .outputMode("append") \
    .format("console") \
    .trigger(processingTime='60 seconds') \
    .start() \
    .awaitTermination()