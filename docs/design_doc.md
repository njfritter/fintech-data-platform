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
