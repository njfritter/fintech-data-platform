"""
BankingBuddy Data Platform Architecture Diagram
Generated using the `diagrams` Python library.

To run:
    pipenv run python architecture.py

Output: bankingbuddy_architecture.png
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.custom import Custom
from diagrams.onprem.analytics import Spark
from diagrams.onprem.workflow import Airflow
from diagrams.onprem.queue import Kafka
from diagrams.onprem.database import PostgreSQL
from diagrams.onprem.inmemory import Redis
from diagrams.aws.storage import S3
from diagrams.aws.analytics import Redshift, EMR
from diagrams.aws.integration import SQS
from diagrams.programming.language import Python
from diagrams.generic.compute import Rack
from diagrams.generic.database import SQL
from diagrams.generic.storage import Storage
from diagrams.generic.os import Ubuntu
from diagrams.onprem.monitoring import Prometheus, Grafana
from diagrams.onprem.analytics import Dbt
from diagrams.aws.ml import Sagemaker

# Color scheme consistent with the design doc
diagram_attrs = {
    #"fontsize": "14",
    #"bgcolor": "white",
    #"pad": "0.5",
}

with Diagram(
    "BankingBuddy Data Platform Architecture",
    filename="bankingbuddy_architecture",
    outformat="png",
    show=False,  # Set to True to open automatically
    direction="TB",  # Top to Bottom
    **diagram_attrs
):
    # --------------------------------------------------------------------------
    # Source Systems Layer (Top)
    # --------------------------------------------------------------------------
    with Cluster("Source Systems"):
        kafka_source = Kafka("Kafka\n(Transaction Events)")
        postgres_source = PostgreSQL("PostgreSQL\n(Users, Loans)")
        s3_files = S3("Flat Files\n(CSV, Parquet, 837 EDI)")
        api_source = Custom("Partner API\n(Decisions)", "./icons/api.png")
    
    # --------------------------------------------------------------------------
    # Ingestion Layer
    # --------------------------------------------------------------------------
    with Cluster("Ingestion Layer"):
        with Cluster("Orchestration"):
            airflow = Airflow("Airflow\n(DAG Scheduling & Backfills)")
        
        with Cluster("Streaming Ingestion"):
            spark_streaming = Spark("Spark Structured Streaming\n(Real-Time Mode, <500ms)")
        
        with Cluster("Batch Ingestion"):
            spark_batch = Spark("Spark Batch\n(Idempotent, Config-Driven)")
    
    # --------------------------------------------------------------------------
    # Storage Layer (Lakehouse)
    # --------------------------------------------------------------------------
    with Cluster("Storage Layer (Delta Lake on S3)"):
        with Cluster("Bronze Layer (Raw Immutable)"):
            bronze = Storage("Raw Events\nTransactions\nClaims")
        
        with Cluster("Silver Layer (Cleansed)"):
            silver = Storage("User SCD2\nVerified Transactions")
        
        with Cluster("Gold Layer (Business)"):
            gold = Storage("Daily Status\nAggregates\nFeature Tables")
    
    # --------------------------------------------------------------------------
    # Transformation Layer
    # --------------------------------------------------------------------------
    with Cluster("Transformation Layer"):
        dbt = Dbt("dbt\n(Models, Tests, Docs)")
        ge = Custom("Great Expectations\n(Data Quality)", "./icons/great_expectations.png")
    
    # --------------------------------------------------------------------------
    # Serving & Self-Service Layer
    # --------------------------------------------------------------------------
    with Cluster("Serving & Self-Service"):
        metabase = Custom("Metabase\n(BI Dashboards)", "./icons/metabase.png")
        streamlit = Python("Streamlit\n(Stakeholder UI)")
        feature_lib = Python("Feature Backfill Library\n(Data Science Self-Service)")
    
    # --------------------------------------------------------------------------
    # Observability Stack (Side)
    # --------------------------------------------------------------------------
    with Cluster("Observability"):
        prometheus = Prometheus("Prometheus\n(Metrics)")
        grafana = Grafana("Grafana\n(Dashboards)")
        pagerduty = Custom("PagerDuty\n(On-Call Alerts)", "./icons/pagerduty.png")
        lineage = Custom("OpenLineage\n(Data Lineage)", "./icons/openlineage.png")
    
    # --------------------------------------------------------------------------
    # Data Consumers (Bottom)
    # --------------------------------------------------------------------------
    with Cluster("Data Consumers"):
        analytics = Custom("Analytics\n(Product, Marketing)", "./icons/analytics.png")
        data_science = Sagemaker("Data Science\n(ML Models)")
        finance = Custom("Finance\n(Reporting, Audit)", "./icons/finance.png")
        fraud = Custom("Fraud Team\n(Real-Time Alerts)", "./icons/fraud.png")
    
    # --------------------------------------------------------------------------
    # Data Flow Connections
    # --------------------------------------------------------------------------
    # Sources to Ingestion
    kafka_source >> Edge(color="blue", label="stream") >> spark_streaming
    postgres_source >> Edge(color="green", label="batch (daily)") >> spark_batch
    s3_files >> Edge(color="orange", label="file trigger") >> spark_batch
    api_source >> Edge(color="purple", label="webhook") >> airflow
    
    # Airflow orchestrates spark jobs
    airflow >> Edge(color="black", style="dashed", label="triggers") >> spark_batch
    airflow >> Edge(color="black", style="dashed", label="triggers") >> spark_streaming
    
    # Ingestion to Storage (Bronze)
    spark_batch >> Edge(color="green", label="idempotent write") >> bronze
    spark_streaming >> Edge(color="blue", label="exactly-once") >> bronze
    
    # Bronze to Silver (dbt transforms)
    bronze >> Edge(color="gray", label="read") >> dbt
    dbt >> Edge(color="orange", label="write (cleansed)") >> silver
    
    # Silver to Gold (dbt aggregates)
    silver >> Edge(color="gray", label="read") >> dbt
    dbt >> Edge(color="red", label="aggregate") >> gold
    
    # Data Quality checks
    bronze >> Edge(color="yellow", style="dashed", label="validate") >> ge
    silver >> Edge(color="yellow", style="dashed", label="validate") >> ge
    ge >> Edge(color="red", style="dotted", label="fail on error") >> airflow
    
    # Serving Layer reads from Gold
    gold >> Edge(color="purple", label="query") >> metabase
    gold >> Edge(color="purple", label="query") >> streamlit
    gold >> Edge(color="purple", label="feature read") >> feature_lib
    
    # Consumers use serving layer
    metabase >> Edge(color="brown", label="dashboard") >> analytics
    metabase >> Edge(color="brown", label="dashboard") >> finance
    feature_lib >> Edge(color="teal", label="backfill") >> data_science
    spark_streaming >> Edge(color="red", label="fraud alert", style="bold") >> fraud
    
    # Observability collects from everything
    airflow >> Edge(color="gray", style="dotted", label="metrics") >> prometheus
    spark_batch >> Edge(color="gray", style="dotted", label="metrics") >> prometheus
    spark_streaming >> Edge(color="gray", style="dotted", label="metrics") >> prometheus
    dbt >> Edge(color="gray", style="dotted", label="metrics") >> prometheus
    
    prometheus >> Edge(color="gray", label="scrape") >> grafana
    grafana >> Edge(color="red", style="bold", label="alert") >> pagerduty
    
    # Lineage tracking
    dbt >> Edge(color="gray", style="dotted", label="emit") >> lineage
    spark_batch >> Edge(color="gray", style="dotted", label="emit") >> lineage


# Alternative: Simplified version for documentation
with Diagram(
    "BankingBuddy Architecture (Simplified)",
    filename="bankingbuddy_architecture_simplified",
    outformat="png",
    show=False,
    direction="LR",  # Left to Right for simplified view
    **diagram_attrs
):
    sources = [
        Kafka("Kafka"),
        PostgreSQL("PostgreSQL"),
        S3("Flat Files")
    ]
    
    ingestion = Spark("Spark\nIngestion")
    
    with Cluster("Delta Lakehouse"):
        bronze = Storage("Bronze")
        silver = Storage("Silver")
        gold = Storage("Gold")
    
    serving = Python("Self-Service\n(APIs, Dashboards)")
    consumers = [
        Custom("Analytics", "./icons/analytics.png"),
        Custom("DS/ML", "./icons/ds.png")
    ]
    
    sources >> Edge(label="raw") >> ingestion
    ingestion >> Edge(label="write") >> bronze
    bronze >> Edge(label="read") >> Dbt("dbt") >> silver
    silver >> Edge(label="read") >> Dbt("dbt") >> gold
    gold >> Edge(label="serve") >> serving
    serving >> Edge(label="consume") >> consumers