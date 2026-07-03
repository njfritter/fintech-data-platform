"""
Fintech Data Platform — AWS Architecture Diagram
Generated using the `diagrams` Python library.
Represents the cloud-native, scalable deployment on AWS.

To run:
    pipenv run python docs/diagrams/aws/aws_architecture.py

Output: aws_architecture.png + aws_architecture_simplified.png
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.analytics import EMR, ManagedStreamingForKafka
from diagrams.aws.database import Aurora, RDS
from diagrams.aws.storage import S3
from diagrams.aws.integration import Eventbridge
from diagrams.aws.network import (
    PrivateSubnet, PublicSubnet, InternetGateway, NATGateway, VPC,
)
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import IAM, KMS
from diagrams.programming.language import Python
from diagrams.onprem.workflow import Airflow
from diagrams.onprem.monitoring import Grafana
from diagrams.onprem.queue import Kafka
from diagrams.custom import Custom

ICON_DIR = "../icons"

graph_attr = {
    "splines": "ortho",
    "nodesep": "0.6",
    "ranksep": "0.8",
    "fontsize": "11",
    "bgcolor": "white",
    "pad": "0.5",
}

node_attr = {
    "fontsize": "10",
    "height": "0.5",
    "width": "1.0",
}

with Diagram(
    "Fintech Data Platform — AWS Architecture",
    filename="aws_architecture",
    outformat="png",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    node_attr=node_attr,
):

    # ==========================================================================
    # SOURCE SYSTEMS (Simulated)
    # ==========================================================================
    with Cluster("Source Systems (Simulated)"):
        with Cluster("Transaction Sources"):
            kafka_source = Kafka("Kafka\n(Transaction Events)")
            s3_files = S3("S3\n(Flat Files, 837 EDI)")
            api_source = Custom("Partner API\n(Decisions)", f"{ICON_DIR}/api.png")
        with Cluster("Application Database (Simulated)"):
            postgres_source = RDS("PostgreSQL\n(Simulated Source)")

    # ==========================================================================
    # INGESTION LAYER
    # ==========================================================================
    with Cluster("Ingestion Layer", graph_attr={"bgcolor": "#E8F0FE"}):
        with Cluster("Streaming Ingestion"):
            msk = ManagedStreamingForKafka("Amazon MSK\n(Managed Kafka)")
            emr_streaming = EMR("EMR Serverless\n(Spark Streaming)")
        with Cluster("Batch Ingestion"):
            emr_batch = EMR("EMR Serverless\n(Spark Batch)")
            airflow = Airflow("Airflow\n(Orchestration)")

    # ==========================================================================
    # STORAGE LAYER (Data Lake)
    # ==========================================================================
    with Cluster("Storage Layer (Data Lake)", graph_attr={"bgcolor": "#E6F7E6"}):
        with Cluster("Bronze (Raw Immutable)"):
            bronze = S3("S3 Bucket\nRaw Events\nTransactions\nClaims")
        with Cluster("Silver (Cleansed)"):
            silver = S3("S3 Bucket\nUser SCD2\nVerified Transactions")
        with Cluster("Gold (Business)"):
            gold = S3("S3 Bucket\nDaily Status\nAggregates\nFeature Tables")

    # ==========================================================================
    # METADATA & STATE STORES
    # ==========================================================================
    with Cluster("Metadata & State", graph_attr={"bgcolor": "#FFF3E0"}):
        aurora = Aurora("Aurora Serverless v2\n(Airflow Metadata)")
        kms = KMS("AWS KMS\n(Encryption)")

    # ==========================================================================
    # ORCHESTRATION & TRANSFORMATION
    # ==========================================================================
    with Cluster("Orchestration & Transformation", graph_attr={"bgcolor": "#F3E8FF"}):
        with Cluster("Workflow Engine"):
            airflow_engine = Airflow("Airflow\n(Orchestration)")
        with Cluster("Transformation & Data Quality"):
            ge = Custom("Great Expectations\n(Data Quality)", f"{ICON_DIR}/great_expectations.png")

    # ==========================================================================
    # SERVING & SELF-SERVICE
    # ==========================================================================
    with Cluster("Serving & Self-Service", graph_attr={"bgcolor": "#E0F2FE"}):
        with Cluster("BI & Dashboards"):
            metabase = Custom("Metabase\n(BI Dashboards)", f"{ICON_DIR}/metabase.png")
            grafana = Grafana("Grafana\n(Monitoring Dashboard)")
        with Cluster("Self-Service Tooling"):
            feature_lib = Python("Feature Backfill Library\n(Data Science)")

    # ==========================================================================
    # AWS INFRASTRUCTURE FOUNDATION
    # ==========================================================================
    with Cluster("AWS Infrastructure Foundation"):
        with Cluster("Networking"):
            vpc = VPC("VPC")
            public_subnet = PublicSubnet("Public Subnets")
            private_subnet = PrivateSubnet("Private Subnets")
            igw = InternetGateway("Internet Gateway")
            nat = NATGateway("NAT Gateway")
        with Cluster("Security"):
            iam = IAM("IAM Roles\n& Policies")
            kms_infra = KMS("AWS KMS\n(Encryption)")
        with Cluster("Monitoring & Operations"):
            cloudwatch = Cloudwatch("CloudWatch\n(Logs, Metrics, Alarms)")
            eventbridge = Eventbridge("EventBridge\n(Scheduled Start/Stop)")

    # ==========================================================================
    # DATA FLOW CONNECTIONS (Simplified)
    # ==========================================================================

    # Sources -> Ingestion
    kafka_source >> Edge(color="#1a73e8", label="real-time") >> msk
    msk >> Edge(color="#1a73e8", label="consume") >> emr_streaming

    s3_files >> Edge(color="#0f9d58", label="file trigger") >> emr_batch
    api_source >> Edge(color="#f4b400", label="webhook") >> airflow_engine

    # Airflow orchestrates Spark jobs
    airflow_engine >> Edge(color="#6c757d", style="dashed", label="triggers") >> emr_batch
    airflow_engine >> Edge(color="#6c757d", style="dashed", label="triggers") >> emr_streaming

    # Ingestion -> Bronze Storage
    emr_batch >> Edge(color="#0f9d58", label="idempotent write") >> bronze
    emr_streaming >> Edge(color="#1a73e8", label="exactly-once") >> bronze

    # Bronze -> Silver (Transformation)
    bronze >> Edge(color="#ea4335", label="read") >> emr_batch
    emr_batch >> Edge(color="#f4b400", label="transform") >> silver

    # Silver -> Gold (Aggregation)
    silver >> Edge(color="#ea4335", label="read") >> emr_batch
    emr_batch >> Edge(color="#f4b400", label="aggregate") >> gold

    # Data Quality Checks
    bronze >> Edge(color="#ea4335", style="dotted", label="validate") >> ge
    silver >> Edge(color="#ea4335", style="dotted", label="validate") >> ge
    ge >> Edge(color="#ea4335", style="dotted", label="fail on error") >> airflow_engine

    # Metadata Store
    aurora >> Edge(color="#6c757d", style="dotted", label="store metadata") >> airflow_engine
    airflow_engine >> Edge(color="#6c757d", style="dotted", label="read/write") >> aurora

    # Serving Layer
    gold >> Edge(color="#9334e6", label="serve") >> metabase
    gold >> Edge(color="#9334e6", label="serve") >> feature_lib

    # Observability
    cloudwatch >> Edge(color="#6c757d", style="dotted", label="logs & metrics") >> grafana
    eventbridge >> Edge(color="#ea4335", style="dashed", label="schedule") >> airflow_engine

    # Security & Encryption
    kms >> Edge(color="#6c757d", style="dotted", label="encrypt") >> aurora
    kms >> Edge(color="#6c757d", style="dotted", label="encrypt") >> bronze
    iam >> Edge(color="#6c757d", style="dotted", label="policy") >> emr_batch
    iam >> Edge(color="#6c757d", style="dotted", label="policy") >> emr_streaming


# ==============================================================================
# SIMPLIFIED VERSION (For README / Presentations)
# ==============================================================================

with Diagram(
    "Fintech Data Platform — AWS Architecture (Simplified)",
    filename="aws_architecture_simplified",
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

    sources = [
        ManagedStreamingForKafka("MSK\n(Streaming)"),
        S3("S3\n(Batch Files)"),
        Custom("API\n(Webhook)", f"{ICON_DIR}/api.png"),
    ]

    ingestion = EMR("EMR Serverless\n(Spark)")
    airflow = Airflow("Airflow\n(Orchestration)")

    with Cluster("Data Lake (S3)"):
        bronze = S3("Bronze\n(Raw)")
        silver = S3("Silver\n(Cleansed)")
        gold = S3("Gold\n(Business)")

    metadata = Aurora("Aurora Serverless\n(Metadata)")
    serving = Python("Self-Service\n(APIs, Dashboards)")

    # Flow
    sources >> Edge(label="ingest") >> ingestion
    ingestion >> Edge(label="write") >> bronze
    bronze >> Edge(label="read") >> ingestion
    ingestion >> Edge(label="transform") >> silver
    silver >> Edge(label="read") >> ingestion
    ingestion >> Edge(label="aggregate") >> gold
    gold >> Edge(label="serve") >> serving

    airflow >> Edge(style="dashed", label="orchestrates") >> ingestion
    airflow >> Edge(style="dotted", label="stores") >> metadata


print("AWS architecture diagrams generated successfully!")
print("   - aws_architecture.png (detailed)")
print("   - aws_architecture_simplified.png (simplified)")
