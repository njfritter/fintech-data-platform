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

## 5. Data Model Design

The data model design that will be leveraged for this architecture is the "medallion" architecture, a data design pattern used to improve data quality and structure as it moves through a data lakehouse. Here is a table representing the pattern at a high level:

| Layer | Purpose | High Level Summary |
| ----- | ------- | ------------------ |
| Bronze | Raw, untransformed data (with additional metadata added as needed) | Quick "CDC" (Change Data Capture) of upstream data systems to minimize impact, preserves full data history, can act as long term archie for replaying data |
| Silver | Refined data that has been cleaned, deduplicated, validated against business rules, and converted into standard formats and schemas | Acts as single source of truth for analytics, enables efficient ad hoc querying, typically has minimal transformations applied to meet Enterprise needs |
| Gold | Further refined, curated data for specific business needs | Very project specific, typically denormalized into a "star schema", can be retrieved by analysts and ML models quickly |

The Medallion architecture comes with multiple key benefits, including:
- Clarity: Raw data and analysis ready data are distinguished
- Scalable: Patterns hold up as data volume grows
- Data Lineage: Data can be traced from the Bronze to the Gold layer easily
- Incremental processing: Leverages Change Data Capture for efficient updates

Here are some additional resources on the Medallion architecture:
- https://www.databricks.com/blog/what-is-medallion-architecture
- https://weld.app/blog/medallion-layers

### 5.1 "Bronze" Layer (Raw, Immutable Data)

Transactions Table:
```sql
-- Partitioning: Event Date
-- Query Optimization: Z-ordered by user_id
CREATE TABLE bronze.transactions (
    event_id STRING,
    event_timestamp TIMESTAMP,
    event_type STRING,
    user_id STRING,
    amount DECIMAL(10,2),
    source_file STRING,
    ingested_at TIMESTAMP 
)
USING delta
PARTITIONED BY (DATE(event_timestamp))
LOCATION 's3://bronze/transactions';
```

### 5.2 "Silver" Layer (Cleaned, includes SCD Type 2 Attributes)

User Attributes Table:
```sql
CREATE TABLE silver.users_scd2 (
    user_id STRING,
    user_name STRING,
    credit_score INT,
    credit_limit DECIMAL(10,2),
    membership_level STRING,
    is_current BOOLEAN,
    effective_start_date DATE,
    effective_end_date DATE,
    data_loaded_at TIMESTAMP
)
USING delta
LOCATION 's3://silver/users_scd2';
```

### 5.3 "Gold" Layer (Curated Business Fact Tables)

Periodic Snapshot User Status Table:
```sql
-- Partitioning: Status Date
CREATE TABLE gold.fact_user_daily_status (
    user_id STRING,
    status_date DATE,
    is_deliquent BOOLEAN,
    total_outstanding_balance DECIMAL(10,2),
    last_payment_date DATE,
    data_loaded_at TIMESTAMP
)
USING delta
PARTITIONED BY (status_date)
LOCATION 's3://gold/fact_user_daily_status';
```

## 6. Data Contracts + Schema Evolution

### 6.1 Data Source Contracts

Each data source must define a contract before onboarding:

```yaml
domain: lending
dataset_name: loan_decisions
version: 1.2.0
owning_team: product_eng_lending
consumer_teams: [finance, analytics, ds_risk]
freshness_sla_minutes: 240
contains_pii: false
retention_days: 2555 # 7 years for SOX compliance
schema_location: s3://schemas/lending/loan_decisions.asvc
```

### 6.2 Schema Evolution Rules

| Change Type | Allowed | Version Bump |
| ----------- | ------- | ------------ |
| Add Optional Field | Yes | Patch (i.e. 1.2.1 --> 1.2.2) |
| Add Required Field | Yes | Minor (i.e. 1.2.1 --> 1.3.0) |
| Remove Field | No (deprecate then remove) | Major (i.e. 1.2.1 --> 2.0.0) |
| Change Field Type | No (deprecate then remove) |  Major (i.e. 1.2.1 --> 2.0.0) |

## 7. Observability + Oncall

### 7.1 SLO Definitions

| Metric | Target | Warning | Critical |
| ------ | ------ | ------- | -------- |
| Data freshness (batch) | < 4 hours | > 4 hours | > 6 hours |
| Data freshness (streaming) | < 500ms | > 500ms | > 2 seconds |
| Pipeline Success Rate | > 99.9% | < 99.9% | 99% |
| Fraud detection accuracy | > 99% | < 99% | < 95% |

### 7.2 Dashboards

- Grafana: Pipeline execution time, processed rows, SLA success rate
- Great Expectations: Row level quality by table
- OpenLineage: Column level lineage for compliance audits

### 7.3 Oncall Runbook

See `docs/oncall_runbook.md` for:
- Incident severity definitions
- Common failures and remediations
- Escalation paths
- Post mortem template

## 8. Build vs Buy Decisions

| Component | Build | Buy | Decision | Reasoning |
| --------- | ----- | --- | -------- | --------- |
| Orchestrator | Custom scheduler | Airflow | Buy | Mature, thousands of providers |
| Data Quality | Custom validators | Great Expectations | Buy | Extensible, open source |
| Lineage | Custom Solution | OpenLineage | Buy | Already integrated with Airflow, open standard |
| BI dashboard | Custom Solution | Metabase (OSS) | Buy | Low barrier to onboarding for stakeholders |
| Feature Store | Feast (OSS) | None | Defer | Not needed for Phase 1 |

## 9. Risks and Mitigations Summary

| Risk | Probability | Impact | Mitigation |
| ---- | ----------- | ------ | ---------- |
| Spark "Real Time Mode" Not Meeting SLA | Medium | High | Fall back to micro-batch, keep Flink option available |
| Vendor lock-in to Delta Lake | Low | Medium | Open format; Iceberg compatibility |
| Team learning curve for Spark | Medium | Medium | Internal trainings + hiring; leverage dbt for SQL dominant work |
| Data quality failures during backfills | High | Medium | Validate gates before overwrites; idempotent writes |
| SOX Audit Fails | Low | Critical | Audit logs on all data access; quarterly compliance reviews (and more as needed) | 

## 10. Future Roadmap (6-12 Months)

| Quarter | Initiative | Success Metric |
|---------|------------|----------------|
| Q3 2026 | Online feature serving for real-time fraud | <10ms feature lookup |
| Q4 2026 | Data mesh / domain-oriented ownership | Each domain owns its silver/gold |
| Q1 2027 | Reverse ETL to operational systems | <5 min from insight to action |
| Q2 2027 | Federated query across multiple regions | <1 sec to cross-region join |

## 11. References & Appendix

### 11.1 Related Documents

- **Product Requirements Document:** [`docs/prd.md`](./prd.md)
- **Data definitions:** [`data_dictionary.md`](./data_dictionary.md)
- **Production checklist:** [`production_readiness_checklist.md`](./production_readiness_checklist.md)
- **On-call procedures:** [`on_call_runbook.md`](./on_call_runbook.md)
**TODO: Add below documents**
- **Schema Registry/Contracts:** `contracts/schema_registry.py`

### 11.2 External References

- [Delta Lake Documentation](https://docs.delta.io/latest/index.html)
- [Spark Structured Streaming](https://spark.apache.org/docs/latest/streaming/index.html)
- [Data Warehouse vs Data Lake vs Data Lakehouse](https://www.montecarlodata.com/blog-data-warehouse-vs-data-lake-vs-data-lakehouse-definitions-similarities-and-differences/)

### 11.3 Glossary

| Term | Definition |
|------|------------|
| **Bronze layer** | Raw, immutable data as ingested from sources |
| **Silver layer** | Cleansed, deduplicated, conformed data |
| **Gold layer** | Business-facing aggregates and feature tables |
| **RTM** | Real-Time Mode (Spark 4.1+) |
| **SCD Type 2** | Slowly Changing Dimension - tracks history via row versioning |
| **SLO** | Service Level Objective - internal target |
| **SOX** | Sarbanes-Oxley Act - financial recordkeeping compliance |

## 12. Approval & Sign-Off

Here we will simulate the review + approvals of key stakeholders:

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Data Engineering Lead | [TBD] | 2026-05-09 | Pending |
| Data Science Lead | [TBD] | 2026-05-09 | Pending |
| Compliance Officer | [TBD] | 2026-05-09 | Pending |
| Engineering Manager | [TBD] | 2026-05-09 | Pending |

**Document Version History**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05-04 | Data Engineering Team | Created Initial Draft |
| 1.1 | 2026-05-09 | Data Engineering Team | Design Document Ready for Review |