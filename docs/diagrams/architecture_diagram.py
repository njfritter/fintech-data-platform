"""
BankingBuddy Data Platform Architecture Diagram

To run:
    pipenv run python architecture.py

Output: bankingbuddy_architecture.png + bankingbuddy_architecture_simplified.png
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.custom import Custom
from diagrams.onprem.analytics import Spark
from diagrams.onprem.workflow import Airflow
from diagrams.onprem.queue import Kafka
from diagrams.onprem.database import PostgreSQL
from diagrams.aws.storage import S3
from diagrams.programming.language import Python
from diagrams.onprem.monitoring import Prometheus, Grafana
from diagrams.onprem.analytics import Dbt

# ------------------------------------------------------------------------------
# Helper function to create custom node with label styling
# (since direct attrs may not work in Python 3.14)
# ------------------------------------------------------------------------------

def create_node(node_class, label, **kwargs):
    """Wrapper to create nodes with consistent styling"""
    return node_class(label, **kwargs)


# ------------------------------------------------------------------------------
# Main Architecture Diagram (Top to Bottom flow)
# ------------------------------------------------------------------------------

with Diagram(
    "BankingBuddy Data Platform Architecture",
    filename="bankingbuddy_architecture",
    outformat="png",
    show=False,
    direction="TB",
    graph_attr={
        "splines": "ortho",      # Use orthogonal lines (right angles)
        "nodesep": "0.5",        # Horizontal separation
        "ranksep": "0.8",        # Vertical separation
        "fontsize": "12",
        "bgcolor": "white",
        "pad": "0.5",
    },
    node_attr={
        "fontsize": "10",
        "height": "0.6",
        "width": "1.2",
    },
    edge_attr={
        "fontsize": "8",
    }
):
    
    # --------------------------------------------------------------------------
    # Source Systems Layer (Top)
    # --------------------------------------------------------------------------
    with Cluster("Source Systems", graph_attr={"bgcolor": "#F0F4F8"}):
        kafka_source = Kafka("Kafka\nTransaction Events")
        postgres_source = PostgreSQL("PostgreSQL\nUsers & Loans")
        s3_files = S3("S3 / MinIO\nFlat Files (CSV, Parquet)")
    
    # --------------------------------------------------------------------------
    # Ingestion Layer
    # --------------------------------------------------------------------------
    with Cluster("Ingestion Layer", graph_attr={"bgcolor": "#E8F0FE"}):
        airflow = Airflow("Airflow\nOrchestration")
        
        with Cluster("Processing Engines"):
            spark_batch = Spark("Spark Batch\nIdempotent Ingestion")
            spark_streaming = Spark("Spark Streaming\nReal-Time (<500ms)")
    
    # --------------------------------------------------------------------------
    # Storage Layer (Lakehouse)
    # --------------------------------------------------------------------------
    with Cluster("Storage Layer (Delta Lake)", graph_attr={"bgcolor": "#E6F7E6"}):
        with Cluster("Bronze (Raw Immutable)"):
            bronze = S3("Raw Events")
        
        with Cluster("Silver (Cleansed)"):
            silver = S3("User SCD2\nVerified Transactions")
        
        with Cluster("Gold (Business)"):
            gold = S3("Daily Status\nFeature Tables")
    
    # --------------------------------------------------------------------------
    # Transformation Layer
    # --------------------------------------------------------------------------
    with Cluster("Transformation & Quality", graph_attr={"bgcolor": "#FFF3E0"}):
        dbt = Dbt("dbt\nModels & Tests")
        ge = Custom("Great Expectations\nData Quality", "./icons/ge.png")
    
    # --------------------------------------------------------------------------
    # Serving Layer
    # --------------------------------------------------------------------------
    with Cluster("Serving & Self-Service", graph_attr={"bgcolor": "#F3E8FF"}):
        metabase = Custom("Metabase\nBI Dashboards", "./icons/metabase.png")
        streamlit = Python("Streamlit\nStakeholder UI")
        feature_lib = Python("Feature Backfill\nDS Self-Service")
    
    # --------------------------------------------------------------------------
    # Observability (Side cluster)
    # --------------------------------------------------------------------------
    with Cluster("Observability", graph_attr={"bgcolor": "#FEE2E2"}):
        prometheus = Prometheus("Prometheus")
        grafana = Grafana("Grafana")
    
    # --------------------------------------------------------------------------
    # Consumers
    # --------------------------------------------------------------------------
    with Cluster("Data Consumers", graph_attr={"bgcolor": "#E0F2FE"}):
        analytics = Custom("Analytics\nProduct & Marketing", "./icons/analytics.png")
        data_science = Custom("Data Science\nML Models", "./icons/ds.png")
        finance = Custom("Finance\nReporting & Audit", "./icons/finance.png")
    
    # --------------------------------------------------------------------------
    # Data Flow Connections (Simplified for clarity)
    # --------------------------------------------------------------------------
    
    # Sources → Ingestion
    kafka_source >> Edge(color="#1a73e8", label="stream") >> spark_streaming
    postgres_source >> Edge(color="#0f9d58", label="batch daily") >> spark_batch
    s3_files >> Edge(color="#f4b400", label="file trigger") >> spark_batch
    
    # Airflow orchestrates
    airflow >> Edge(color="#6c757d", style="dashed", label="triggers") >> spark_batch
    airflow >> Edge(color="#6c757d", style="dashed", label="triggers") >> spark_streaming
    
    # Ingestion → Bronze
    spark_batch >> Edge(color="#0f9d58", label="write") >> bronze
    spark_streaming >> Edge(color="#1a73e8", label="write") >> bronze
    
    # Bronze → Silver (through dbt)
    bronze >> Edge(color="#ea4335", label="read") >> dbt
    dbt >> Edge(color="#f4b400", label="transform") >> silver
    
    # Silver → Gold
    silver >> Edge(color="#ea4335", label="read") >> dbt
    dbt >> Edge(color="#f4b400", label="aggregate") >> gold
    
    # Quality checks
    bronze >> Edge(color="#ea4335", style="dotted", label="validate") >> ge
    silver >> Edge(color="#ea4335", style="dotted", label="validate") >> ge
    
    # Gold → Serving
    gold >> Edge(color="#9334e6", label="query") >> metabase
    gold >> Edge(color="#9334e6", label="query") >> streamlit
    gold >> Edge(color="#9334e6", label="read") >> feature_lib
    
    # Serving → Consumers
    metabase >> Edge(color="#1a73e8") >> analytics
    metabase >> Edge(color="#1a73e8") >> finance
    feature_lib >> Edge(color="#1a73e8") >> data_science
    
    # Observability
    airflow >> Edge(color="#6c757d", style="dotted") >> prometheus
    spark_batch >> Edge(color="#6c757d", style="dotted") >> prometheus
    prometheus >> Edge(color="#ea4335") >> grafana


# ------------------------------------------------------------------------------
# Simplified Diagram (Left to Right) - Better for READMEs
# ------------------------------------------------------------------------------

with Diagram(
    "BankingBuddy Architecture (Simplified)",
    filename="bankingbuddy_architecture_simplified",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr={
        "splines": "ortho",
        "nodesep": "0.6",
        "ranksep": "0.8",
        "fontsize": "11",
        "bgcolor": "white",
    },
    node_attr={
        "fontsize": "10",
        "height": "0.5",
        "width": "1.0",
    },
):
    
    # Left to right flow
    sources = [
        Kafka("Kafka\nStreaming"),
        PostgreSQL("PostgreSQL\nBatch"),
        S3("S3\nFiles")
    ]
    
    ingestion = Spark("Spark\nIngestion Engine")
    
    with Cluster("Delta Lakehouse (S3)", graph_attr={"bgcolor": "#E6F7E6"}):
        bronze = S3("Bronze\nRaw")
        silver = S3("Silver\nCleansed")
        gold = S3("Gold\nBusiness")
    
    transformation = Dbt("dbt\nTransformation")
    serving = Python("Self-Service\nAPIs & Dashboards")
    
    consumers = [
        Custom("Analytics", "./icons/analytics.png"),
        Custom("Data Science", "./icons/ds.png"),
        Custom("Finance", "./icons/finance.png")
    ]
    
    # Define the flow
    sources >> Edge(label="ingest") >> ingestion
    
    ingestion >> Edge(label="write (idempotent)") >> bronze
    bronze >> Edge(label="read") >> transformation
    transformation >> Edge(label="cleanse") >> silver
    silver >> Edge(label="read") >> transformation
    transformation >> Edge(label="aggregate") >> gold
    
    gold >> Edge(label="serve") >> serving
    serving >> Edge(label="consume") >> consumers


# ------------------------------------------------------------------------------
# Print success message
# ------------------------------------------------------------------------------

print("✅ Diagrams generated successfully!")
print("   - bankingbuddy_architecture.png (detailed)")
print("   - bankingbuddy_architecture_simplified.png (simple)")
print("\nTo view: open both .png files in your image viewer")