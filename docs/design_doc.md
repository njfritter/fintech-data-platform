## 1. Executive Summary

The BankingBuddy Data Platform (BBDP) is a production-grade data platform for consumer fintech analytics, with support for the following:
- Batch and Streaming ETL pipelines for lending, transactions and fraud detection
- Self service data access for Analytics, Data Science and Machine Learning teams
- Sensitive Data and Audit Compliance (i.e. SOX, PII)
- Ability to scale by orders of magnitude (i.e. 20x)

This document captures 

## 2. Problem Statement + Requirements

###  2.1 Business Context + Needs

BankingBuddy needs a unified data platform that can support insights across a wide range of teams including fraud detection, lending and member analytics:
- Enable self service analytics and replace the manual, error prone processes analysts use today. 
- Enable analysts to investigate data streams in real time to move towards a more proactive approach to understanding their growing data volumes and to make faster decisions
- Enable Data Scientists to experiment and iterate quickly using cleaned and refined ML features
- Enable faster audit reporting and sensitive data access controls

For more business context see the associated [Product Requirements Document](./prd.md).


### 2.4 Key Requirements

| Requirement | Priority | Metric |
| ----------  | -------  | ------ |
| Idempotent Pipelines | Critical | Zero business events duplicated |
| Audit Compliance | Critical | Access logging + controls for all sensitive data |
| Data Freshness (batch) | High | < 4 hours from source to analysis ready |
| Data Freshness (streaming) | High | <500ms for fraud alerts |
| Scaling Requirements | High | Usage based (i.e. linear) cost scaling |
| Self Service for DS | High | Feature backfills < 1 hour |
| Observability + Oncall Support | High | < 15 minutes for incident detection |

### 2.5 Stakeholders + Personas

| Persona | Needs | Success Metrics |
| ------- | ----- | --------------- |
| Data Analyst | Ability to query cleaned, well documented tables | < 30 minutes to answer ad hoc business questions |
| Data Scientist | Rapid experimentation, feature access w/o re-engineering | < 4 hours to backfill new features |
| Product Engineer | Self Service Onboarding of New Data Sources | < 1 day to onboard new data sources |
| Compliance Analyst | Audit trails, sensitive data controls | Audit ready within 4 hours |
| On-Call Engineers | Ability to detect/resolve issues | Resolve issues within 2 hours |

## 3. Architecture Overview

### 3.1 High Level Architecture Diagram

TODO: INSERT DIAGRAM

### 3.2 Technology Stack Overview

| Layer | Technology | Reasoning |
| ----- | ---------- | --------- |
| Storage | Delta Lake on S3 (MinIO on local) | Open format, ACID compliant, supports time travel, no vendor lock in, lightweight local development (MinIO) |
| Batch Processing | PySpark | Unified with Stream Processing, mature |
| Streaming Processing | Spark Structuring Streaming ("Real Time Mode") | Unified with Batch Processing, acceptable for above business use cases |
| Orchestrator | Airflow | Mature, Python-native |
| Transformations | dbt (core) | SQL native, testing, documentation |
| Data Quality | Great Expectations | Extensible, provides row level validation |
| Observability | Prometheus / Grafana | Open Source, Industry standard |
| Self Service BI | Metabase / Streamlit | Easy onboarding for stakeholders |
| Source OLTP | PostgreSQL | Will simulate source data |
| Streaming Broker | Kafka (Redpanda for local) | Industry standard, lightweight local development |

## 4. Core Design Decisions + Tradeoffs

### 4.1 Decision 1: Lakehouse (Delta Lake) vs Cloud Warehouse (Snowflake)

**Context:** We need to be able to store and query financial data, ingest a variety of data sources (i.e. semi-structured) and support ML feature engineering. We considered Delta Lake and Snowflake as options.

| Criteria | Delta Lake | Snowflake |
| -------- | ---------- | --------- |
| Storage cost ($/GB-month) | ~$0.023 (S3) | ~$0.04 (proprietary storage w/ compression) |
| Unstructured/Semi-structured data ingestion | Native support (i.e. JSON, images) | Limited support |
| Stream Processing | Excellent (Spark Structured Streaming) | Less mature (Snowpipe Streaming) |
| Open Format | Native support (Parquet/transation logs) | Not supported (proprietary) |
| SQL interface | Decent (Trino, Spark SQL) | Excellent (industry standard) |
| ML Integration | Excellent (PySpark/MLflow) | Growing but less mature (Snowpark) |
| Team knowledge | Less (Spark concepts); higher learning curve | More (SQL); lower learning curve |

**Decision**: Delta Lake

**Reasoning:**
1. Managing Costs at Scale: with BankingBuddy's expected growth of 10x, storage costs will dominate here. S3's pricing model beats out Snowflake's here.
2. Multi-structure Data Ingestion Support: Various files with different formats need to be ingested (EDI, JSON, flat files). Delta Lake on S3 handles arbitrary formats natively; Snowflake can only support semi-structured JSON/XML via its "VARIANT" datatype.
3. Streaming integration: Spark Structured Streaming can write to Delta lake using exactly once semantics. Snowflake's Snowpipe offering is less mature.
4. ML/AI Support: While Snowflake's Snowpark offering is growing, PySpark and MLflow offers a more mature option that also integrates nicely with the upstream batch and streaming ingestion layers.
5. Open format support: Delta lake's open format means various tools like Spark, Trino and more can be leveraged.

**Risks and Mitigation**: If there were no ML or Streaming needs and the team was primary SQL Analysts then Snowflake would be the better option. We mitigate this by providing a Trino SQL interface and Metabase for BI, bypassing the need for analysts to learn Spark.

### 4.2 Decision 2: Streaming Engine (Spark vs Flink)

**Context:** We need to be able to perform real time transformations on financial data to support a wide variety of use cases. For the main use case of fraud detection, we need to detect fraud patterns (i.e. >5 declined credit card transactions in an hour) with <500 ms latency. We considered Spark Structured Streaming (["Real Time Mode" released in 2026](https://downloads.apache.org/spark/docs/3.4.4/structured-streaming-programming-guide.html)) and Flink as options.

| Criteria | Spark Structured Streaming | Flink |
| -------- | -------------------------- | ----- |
| Latency  | <100ms (best case scenario) | 1-10ms |
| Throughput | Excellent | Good |
| State Management | Improved in RTM | Excellent (RocksDB w/ incremental checkpoints) |
| Complex Event Processing (CEP) | Limited | Native CEP library |
| Event Time + Watermarks | Good (improving) | Native support |
| SQL Support | Excellent (Spark SQL) | Good (Flink SQL, less mature) |
| Unified Batch/Streaming Implementation | Yes, same APIs | No, separate APIs |
| Team Knowledge | More with above Delta lake implementation | Less; higher learning curve |
| Delta Lake Integration | Supported (exactly once) | Additional connectors needed |

**Decision**: Spark Structured Streaming with Real Time Mode (RTM)

**Reasoning**:
1. Unified Architecture: Using the same API for batch and streaming ingestion reduces operational complexity.
2. Delta Lake Integration: Spark's native Delta Lake connector supports exactly once semantics out of the box; Flink requires custom sinks and configuration.
3. Latency Requirements Met: Spark "Real Time Mode" achieves millisecond latency through various new features such as concurrent processing stages and longer epochs. Independent benchmarks show <100ms latency results for windowed aggregations, which meet the <500ms latency requirement.
4. Team Expertise: The team is already using Spark for the above Delta Lake implementation; adding Flink would require additional training or hiring.

**Risks and Mitigation:**
If the business needed guaranteed <10ms latency or complex event patterns (like searching for matching sequences across multiple event types), Flink would be the correct choice. This decision will be revisited if latency requirements change. Since our architecture leverages Kafka for decoupling, so migrating the fraud detection jobs to Flink while keeping the batch ETL on Spark would be feasible.

### 4.3 Decision 3: Orchestrator (Airflow vs Prefect vs Dagster)

**Context:** We need an orchestrator to schedule, backfill and monitor pipelines with varying numbers of dependencies.

**Decision:** Airflow

**Reasoning:**
1. Maturity: Thousands of supported providers, including the above technology stacks (Snowflake, Spark, dbt, Great Expectations)
2. Python native DAGs: Supports dynamic DAG generation for customer onboarding via configs
3. Backfill capacitilies: Supports backfills, catchups and reruns natively

**Risks and Mitigation**: Dagster has better lineage and testing. We mitigate this by leveraging the automated OpenLineage integration (standard in Airflow 2.7+) for SQL/Spark.

### 4.4 Decision 4: Data Quality Stack (Great Expectations vs dbt tests vs custom)

**Context:** We need row-level, cross-table, and schema validation tests that provide clear messages for the on-call engineer.

**Decision:** Great Expectations for validation layer, dbt tests for schema validation.

**Reasoning:**
1. Great Expectations is strong at row level validation (i.e. no negative loan amounts) and provides human friendly error reports
2. dbt tests are strong regarding enforcement of referential integrity and uniqueness constraints
3. Clean separation of responsibilities: dbt tests handle transformation layer, Greater Expectations validates data before writing to analyst ready data layer.

### 4.5 Decision 5: Self Service Tooling Strategy

**Context:** Data Scientists need to be able to backfill features without platform engineering support.

**Decision:** Build a custom lightweight Python feature registry + implement Airflow backfill DAGs

**Reasoning:**
1. Avoids implementing platforms too complex for initial needs (i.e. Feast)
2. Leverages existing Airflow infrastructure
3. Supports audit logging (meets SOX requirement)

**Risks and Mitigation:**
- Lacks online serving, so not a full feature store
- Will revisit this decision if real time serving becomes a priority