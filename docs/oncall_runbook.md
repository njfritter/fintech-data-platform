# BBDP On-Call Runbook

> **Note:** This runbook is adapted from industry templates to document standardized incident response for the BBDP data platform.

## Purpose

Standardized incident response and playbooks for the BBDP data platform. Pipeline owners should document any pipeline-specific failure modes here.

## On-call Overview

- **Rotation:** Primary (1 week), Secondary (backup)
- **Escalation rules:** P0 → Page entire team; P1 → Page primary + secondary
- **Contact:** [#data-alerts](https://slack.bankingbuddy.com/archives/data-alerts) | PagerDuty schedule: (link)

---

## Incident Severity Definitions

| Severity | Description | Response Time | Page Action |
|---|---|---:|---|
| **P0** | Production data unavailable >30 min OR financial data incorrect | 15 minutes | SMS + Phone + Slack (entire team) |
| **P1** | SLA breach >2x threshold OR data quality failure in critical table | 30 minutes | PagerDuty + Slack (primary + secondary) |
| **P2** | Data quality issue in non-critical table OR schema drift auto-resolved | 4 hours | Slack only |
| **P3** | Minor schema drift, documentation outdated, non-blocking alert | Next business day | Ticket only |

---

## Runbooks: Common Failure Modes

### 1) Data Freshness Breach

- **Symptom:** Slack alert: `gold.fact_user_daily_status stale >6 hours (SLA: 4h)`
- **Affected:** Any table with an SLO defined

Investigation (first 10 minutes):

1. Check Airflow DAG runs and task status:

```bash
airflow dags list-runs -d customer_onboarding -o table
airflow tasks list customer_onboarding
airflow tasks test customer_onboarding ingest_claims 2024-01-01
```

2. Check source system availability:

```bash
# Kafka
rpk cluster metadata
# S3
aws s3 ls s3://partner-bucket/incoming/ --recursive | tail
# Postgres
psql -c "SELECT pg_is_in_recovery();"
```

3. Check data volume vs historical average:

```sql
SELECT COUNT(*) FROM bronze.payments WHERE date = CURRENT_DATE - 1;
```

Remediation options:

- Backfill Airflow DAG if upstream data is now available:

```bash
airflow dags backfill -s 2024-01-01 -e 2024-01-01 customer_onboarding
```

- Pause/unpause or adjust sensor timeouts in DAG if source is slow.
- Reprocess transformations from raw/bronze:

```bash
dbt run --select gold.fact_user_daily_status --full-refresh
```

Prevention:

- Increase sensor timeouts and add `execution_timeout` on tasks.
- Add source-system health monitors and alerts.

---

### 2) Spark Out-of-Memory (OOM)

- **Symptom:** Airflow task fails; container killed by YARN for exceeding memory limits.

Investigation:

1. Check data volume:

```sql
SELECT COUNT(*) FROM bronze.transactions WHERE date = '2024-05-01';
```

2. Check partition/key skew (example PySpark):

```python
df.groupBy("user_id").count().orderBy(desc("count")).show(10)
```

3. Review Spark UI for shuffle/read sizes, GC time, and FetchFailedException.

Remediation options:

- Salt skewed keys:

```python
from pyspark.sql.functions import col, concat, lit, rand
df_salted = df.withColumn("salted_key", concat(col("user_id"), lit("_"), (rand() * 10).cast("int")))
```

- Increase shuffle partitions:

```python
spark.conf.set("spark.sql.shuffle.partitions", 500)
```

- Enable adaptive query execution:

```python
spark.conf.set("spark.sql.adaptive.enabled", "true")
```

---

### 3) PII Found in Non-PII Table (Compliance Violation)

- **Symptom:** Alert: "PII pattern detected in gold.analytics_ready (ssn column)"
- **Severity:** P1 — immediate compliance risk

Investigation:

```sql
SELECT * FROM gold.analytics_ready
WHERE ssn ~ '\\d{3}-\\d{2}-\\d{4}'
LIMIT 10;

SELECT upstream_source, upstream_column
FROM data_lineage.column_dependencies
WHERE target_table = 'gold.analytics_ready' AND target_column = 'ssn';
```

Remediation options:

- Redact immediately:

```sql
UPDATE gold.analytics_ready
SET ssn_hash = sha2(ssn, 256), ssn = NULL
WHERE ssn IS NOT NULL;
```

- Drop column and reprocess (preferred):

```sql
ALTER TABLE gold.analytics_ready DROP COLUMN ssn;
```

```bash
dbt run --select gold.analytics_ready --full-refresh
```

- If legitimate, add to PII register and create audit ticket.

Post-mortem actions:

- Add a dbt test: expect_column_values_to_not_match_regex('ssn', '\\d{3}-\\d{2}-\\d{4}')
- Update schema.yml to mark column as PII
- Notify compliance officer within 24 hours

---

### 4) Streaming Consumer Lag

- **Symptom:** Grafana consumer lag >50,000 messages; alerts delayed.

Investigation:

```bash
rpk group describe fraud-detection-consumer
grep "Commit" /var/log/spark/streaming.log
```

Check Spark Streaming UI for input rate and processing times.

Remediation options:

- Increase parallelism / partitions:

```python
spark.conf.set("spark.streaming.kafka.maxRatePerPartition", 1000)
```

- Increase micro-batch duration or scale deployments:

```python
spark.conf.set("spark.sql.streaming.truncateDuration", "2 seconds")
```

```bash
kubectl scale deployment spark-streaming-fraud --replicas=4
```

---

### 5) Schema Drift / Data Contract Violation

- **Symptom:** DataContractViolation in Airflow logs: "New field 'riskscore' not in contract"

Investigation:

```bash
python scripts/schema_diff.py --table lending.loan_decisions --version 1.2.0
```

Questions to ask producer team:

- Did they add a field without updating the contract?
- Is this a breaking change (type change or removal)?

Remediation:

- Non-breaking: bump minor version and auto-update contract.
- Breaking: coordinate change window with producer team; avoid temporary bypass unless logged and approved.

---

## Escalation Tree

1. Level 1: On-Call Engineer (Primary)
   - If P0/P1 not resolved in 30 minutes → Page Secondary
2. Level 2: Primary + Secondary
   - If P0 unresolved in 60 minutes → Page Team Lead
3. Level 3: Team Lead
   - If cross-team, page Incident Commander
4. Level 4: Incident Commander
   - Coordinates communication, decides build vs rollback, declares incident resolved, leads post-mortem

---

## Post-Mortem Template (P0/P1 — fill within 48 hours)

- Incident ID: INC-YYYY-MM-DD-###
- Severity: [P0/P1]
- Detection Time:
- Resolution Time:
- Resolved By:

What happened (2–3 sentences)

Root Cause (technical)

Impact
- Tables/consumers affected
- Duration of impact
- Data loss/corruption? [Yes/No/Unclear]

Contributing factors

Remediation actions (table):

| Action | Owner | ETA |
|---|---|---|
| Add alert for [metric] | Engineer A | 1 week |
| Increase retry on task X | Engineer B | 2 days |
| Update runbook | On-Call Lead | 1 week |

Lessons learned
- What went well
- What went poorly
- Actions to prevent recurrence

---

## On-Call Handoff Template

- Creator: Outgoing on-call
- Reviewer: Incoming on-call
- Frequency: Weekly (Monday 10 AM)

Active incidents (example):

- INC-2026-04-30-042: [P2] Schema drift — awaiting upstream fix (ETA May 10)

Recent changes

| Change | Date | Risk | Rollback plan |
|---|---|---|---|
| Upgraded Spark to 4.1 | May 1 | Low | spark-submit --version 4.0 |

Known issues

| Issue | Workaround | Fixed in |
|---|---|---|
| Consumer lag on Sundays | Restart consumer | May 15 |

---

## Useful Commands

```bash
airflow dags list-runs --state failed
kubectl delete pod spark-streaming-fraud-xxx
dbt run --select gold.* --full-refresh
```

## Escalation Contacts

| Role | Name | Slack |
|---|---|---|
| Team Lead | Jane | @jane |
| Data Science | Mark | @mark |

Next rotation: (Name) starting May 9

---

## Related Documents

- [Design document](./design_doc.md)
- [Data dictionary](./data_dictionary.md)
- [Production readiness checklist](./production_readiness_checklist.md)

## Change Log

| Version | Date | Author | Changes |
|---|---:|---|---|
| 1.0 | 2026-05-02 | Data Engineer | Initial version |
| 1.1 | 2026-05-09 | Data Engineer | Re-formatted with headers for reliable rendering |


