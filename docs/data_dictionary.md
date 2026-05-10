# BBDP Data Dictionary

**Purpose:** Single source of truth for all datasets, columns, and business definitions.  
**Owner:** Data Engineering Team  
**Update Cadence:** Within 1 week of any schema change

---

## Bronze Layer (Raw Immutable)

### `bronze.transactions`

| Column | Type | Description | PII? | Example |
|--------|------|-------------|------|---------|
| `event_id` | STRING | Unique event identifier | No | `evt_01H7X3K2A5` |
| `event_timestamp` | TIMESTAMP | When event occurred (UTC) | No | `2026-05-02 14:23:11` |
| `event_type` | STRING | Transaction type | No | `payment`, `transfer`, `fee` |
| `user_id` | STRING | Unique user identifier (hashed) | Yes (hashed) | `a7b3c9d2` |
| `amount` | DECIMAL(10,2) | Dollar amount | No | `49.99` |
| `source_file` | STRING | Source file path | No | `s3://partner/2026-05-02/payments.csv` |
| `ingested_at` | TIMESTAMP | When pipeline loaded (UTC) | No | `2026-05-02 14:25:00` |

**Business Rules:**
- Never delete rows (immutable by design)
- Exactly-once: duplicate `(event_id, source_file)` prevented
- Retention: 2555 days (7 years, SOX compliant)

**Update Frequency:** Continuous (streaming)

**PII Classification:** `user_id` (hashed)

**Owner:** Data Engineering (`@data-eng`)

---

### `bronze.loan_applications`

| Column | Type | Description | PII? | Example |
|--------|------|-------------|------|---------|
| `application_id` | STRING | Unique application identifier | No | `app_00012345` |
| `application_date` | DATE | Date application submitted | No | `2026-05-01` |
| `user_id` | STRING | Chime user identifier (hashed) | Yes (hashed) | `a7b3c9d2` |
| `loan_amount` | DECIMAL(10,2) | Dollar amount requested | No | `5000.00` |
| `credit_score_at_application` | INT | User's credit score at time of application | No | `720` |
| `decision` | STRING | Loan decision | No | `approved`, `denied`, `approved_conditional` |
| `decision_timestamp` | TIMESTAMP | When decision was made | No | `2026-05-01 13:45:00` |

**Business Rules:**
- One row per application
- Decision final; no updates (new application gets new ID)

**Update Frequency:** Daily batch (next day)

**PII Classification:** `user_id` (hashed)

**Owner:** Lending Product Engineering (`@product-eng-lending`)

---

## Silver Layer (Cleansed, Enriched)

### `silver.users_scd2` (Slowly Changing Dimension Type 2)

| Column | Type | Description | PII? | Example |
|--------|------|-------------|------|---------|
| `user_id` | STRING | Surrogate key (internal) | Yes (hashed) | `a7b3c9d2` |
| `user_name` | STRING | Full name | Yes (raw) | `John Smith` |
| `credit_score` | INT | User's credit score | No | `710` |
| `credit_limit` | DECIMAL(10,2) | Maximum credit limit | No | `10000.00` |
| `membership_level` | STRING | Level of membership user has | No | `premium`, `standard`, `free` |
| `is_current` | BOOLEAN | Is this the active version? | No | `true` |
| `effective_start_date` | DATE | When this version became active | No | `2026-01-15` |
| `effective_end_date` | DATE | When this version ended (NULL = current) | No | `2026-04-20` or NULL |
| `data_loaded_at` | TIMESTAMP | When row materialized | No | `2026-05-02 03:00:00` |

**Business Rules:**
- New row added when `credit_score`, `credit_limit` or `membership_level` changes
- Multiple historical versions per user
- Exactly one row with `is_current = true` per user

**Example Timeline:**
| user_id | credit_score | effective_start | effective_end | is_current |
|---------|--------------|-----------------|---------------|------------|
| usr_001 | 680 | 2024-01-01 | 2024-03-15 | false |
| usr_001 | 710 | 2024-03-16 | 2024-12-31 | false |
| usr_001 | 695 | 2025-01-01 | null | true |

**Update Frequency:** Daily batch (reflects previous day's changes)

**PII Classification:** `user_name` contains PII (raw); `user_id` hashed

**Access Control:** Role `analytics` can query, but `user_name` redacted via row-level security (requires additional permissions that must be approved by a VP)

**Owner:** Data Engineering (`@data-eng`)

---

## Gold Layer (Business Facts)

### `gold.fact_user_daily_status` (Periodic Snapshot)

| Column | Type | Description | PII? | Example |
|--------|------|-------------|------|---------|
| `user_id` | STRING | User identifier (hashed) | Yes (hashed) | `a7b3c9d2` |
| `status_date` | DATE | Snapshot date | No | `2026-05-01` |
| `is_delinquent` | BOOLEAN | User has any unpaid statement as of this date | No | `true` |
| `total_outstanding_balance` | DECIMAL(10,2) | Sum of unpaid statement balances | No | `2500.00` |
| `last_payment_date` | DATE | Date of user's last payment activity (NULL = never paid) | No | `45` |
| `data_loaded_at` | TIMESTAMP | When row materialized | No | `2026-05-02 03:00:00` |

**Business Rules:**
- One row per user per day (sparse: only days after user's first statement)
- `is_delinquent = true` if any unpaid statement exists as of `status_date`
- Delinquent status persists until full payment received

**Typical Analyst Queries:**
```sql
-- Number of delinquent users in past 30 days
SELECT COUNT(DISTINCT user_id) 
FROM gold.fact_user_daily_status
WHERE status_date >= DATE_SUB(CURRENT_DATE, 'DAY', 30)
AND is_delinquent = true;

-- Users created (first appearance) on a given day
SELECT COUNT(DISTINCT fact.user_id)
FROM gold.fact_user_daily_status fact
WHERE status_date = '2026-05-01'
  -- Filter for users that first appeared in table 
  AND status_date = (SELECT MIN(status_date) FROM gold.fact_user_daily_status f2 WHERE f2.user_id = fact.user_id);
```

**Update Frequency:** Daily batch (after all statements processed)

**PII Classification:** user_id (hashed)

**Owner:** Analytics (@analytics-team)

### `gold.fraud_alerts` (Streaming)
| Column | Type |	Description |	PII? | Example |
| ------ | ---- | ----------- | ---- | ------  |
| `alert_id` | STRING | Unique alert identifier |	No | `frd_01H7X3K2A5` |
| `alert_type` | STRING | Fraud pattern detected | No | `velocity_failed_loans` |
| `alert_timestamp` | TIMESTAMP | When alert triggered (UTC) | No | `2026-05-02 14:23:11` |
| `user_id` | STRING | User identifier (hashed) | Yes (hashed) | `a7b3c9d2` |
| `failure_count` | INT | Number of failed attempts in window | No | `7` |
| `window_start` | TIMESTAMP | Tumbling window start | No | `2026-05-02 14:15:00` |
| `window_end` | TIMESTAMP | Tumbling window end | No | `2026-05-02 14:20:00` |
| `investigation_status` | STRING | Status of investigation | No | `open`, `investigating`, `false_positive`, `confirmed_fraud` |

**Business Rules:**
- Alert if > 5 failed loan applications in 5-minute rolling window
- Exactly-once delivery from Kafka
- Retention: 90 days (fraud investigations)

**Update Frequency:** Real-time (latency <500ms)

**PII Classification:** user_id (hashed)

**Owner:** Fraud Engineering (@fraud-team)

## Derived / Feature Store Tables

`ml_features.user_risk_scores`
| Column | Type |	Description |	PII? | Example |
| ------ | ---- | ----------- | ---- | ------  |
| `user_id` | STRING | User identifier (hashed) | Yes (hashed) | `a7b3c9d2` |
| `risk_score` | DECIMAL(5,4) | ML model output (0-1, higher = more risk) | No | `0.87` |
| `model_version` | STRING | Which model generated this score | No | `risk_v3.2` |
| `score_date` | DATE | Date score was computed | No | `2026-05-01` |
| `feature_snapshot_timestamp` | TIMESTAMP | Point-in-time features snapshot | No | `2026-05-01 00:00:00` |

**Business Rules:**
- Computed daily for active users
- Training data uses point-in-time joins to avoid leakage
- Model version tracked for reproducibility

**Update Frequency:** Daily batch

**PII Classification:** user_id (hashed)

**Owner:** Data Science (@ds-risk)

## Audit & Operations Tables

`audit.pipeline_runs`
| Column | Type | Description |
| ------ | ---- | ----------- |
| `run_id` | STRING | Unique run identifier |
| `pipeline_name` | STRING | Airflow DAG ID or Spark job name |
| `start_time` | TIMESTAMP | Run start (UTC) |
| `end_time` | TIMESTAMP | Run end (UTC) |
| `status` | STRING | `success`, `failed`, `retrying` |
| `rows_read` | BIGINT | Number of input rows |
| `rows_written` | BIGINT | Number of output rows |
| `data_contract_version` | STRING | Version of contract at time of run |
| `triggered_by` | STRING | `scheduler`, `backfill`, `manual` |
| `error_message` | STRING | If failed, error summary |
| `git_commit` | STRING | Code version at runtime |

**Retention:** 365 days (operational audit)

**Update Frequency:** Daily batch

**Owner:** Compliance (@compliance)

`audit.phi_access_log`
| Column | Type | Description |
| ------ | ---- | ----------- |
| `access_id` | STRING | Unique access identifier |
| `user_email` | STRING | Who accessed (use sparingly) |
| `table_name` | STRING | Which table |
| `query` | STRING | The specific query used |
| `access_timestamp` | TIMESTAMP | When access occurred |
| `purpose` | STRING | Business reason logged |
| `compliance_approved` | BOOLEAN | Was this access pre-approved? |

**Retention:** 7 years (SOX requirement for PII access)

**Update Frequency:** Daily batch

**PII Classification:** `user_email`; requires separate elevated access (VP approval)

**Owner:** Compliance (@compliance)

## Data Quality Expectations
Each table has associated dbt tests (see `tests/` directory). Key expectations:

| Table | Expectation | Severity |
| ----- | ----------- | -------- |
| bronze.* | `not_null(event_id)` | Blocking |
| silver.users_scd2 | `unique(user_id, effective_start_date)` | Blocking |
| silver.users_scd2 | `accepted_values(is_current, [true, false])` | Blocking |
| gold.fact_user_daily_status | `total_outstanding_balance >= 0` | Warning |
| gold.fraud_alerts | `alert_timestamp >= window_start` | Warning |
| ml_features.* | `risk_score between 0 and 1` | Blocking |

## Glossary
| Term | Definition |
| ---- | ---------- |
| Bronze | Raw, immutable data as ingested from sources |
| Silver | Cleansed, deduplicated, conformed data |
| Gold | Business-facing aggregates and feature tables |
| SCD Type 2 | Slowly Changing Dimension - tracks history via row versioning |
| Periodic Snapshot | Fact table capturing state at regular intervals (daily) |
| Point-in-time join | Feature computation using only data available before prediction time |
| PII | Personally Identifiable Information |

## Change Log

| Date | Table | Change | Author |
| ---- | ----- | ------ | ------ |
| PLACEHOLDER | PLACEHOLDER | PLACEHOLDER | PLACEHOLDER|