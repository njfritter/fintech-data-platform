# BBDP Production Readiness Checklist (PRC)

> **📌 Note on Authorship:** This checklist is adapted from industry standard templates for portfolio purposes. It demonstrates my understanding of production readiness checklists, an essential skill for senior data engineers.

**Purpose:** Before any pipeline, model, or data contract is promoted to production, it must pass all checks below. This ensures reliability, compliance, and maintainability across the BBDP platform.

**Owner:** Data Engineering Team  
**Review Cadence:** Quarterly (or after major incident)

---

## 1. Correctness & Data Integrity

| # | Check | Evidence Required | Responsible |
|---|-------|-------------------|-------------|
| 1.1 | Idempotent write logic implemented | Code snippet showing `MERGE` / `INSERT OVERWRITE` / Delta Lake `merge` | Engineer |
| 1.2 | Backfill tested for minimum 90 days | Airflow backfill logs or test report | Engineer |
| 1.3 | Data quality tests defined (dbt + Great Expectations) | `schema.yml` + GE suite with at least: `not_null`, `unique`, `accepted_values` | Engineer |
| 1.4 | Referential integrity verified | dbt test: `relationships` macro | Engineer |
| 1.5 | Checksum/versioning for financial tables | Column `data_checksum` or `source_file_hash` present | Engineer |
| 1.6 | No hardcoded dates or thresholds | Configuration files or environment variables used | Engineer |
| 1.7 | Edge cases handled (empty files, nulls, schema drift) | Unit tests covering empty input, malformed records | Engineer |

---

## 2. Observability & Monitoring

| # | Check | Evidence Required | Responsible |
|---|-------|-------------------|-------------|
| 2.1 | Prometheus metrics implemented | Metrics for: `rows_processed`, `duration_seconds`, `failure_count` | Engineer |
| 2.2 | Grafana dashboard created | Screenshot or link to dashboard | Engineer + Data Analyst |
| 2.3 | Slack alert configured for SLA breaches | Alert channel `#data-alerts`; test message sent | Engineer |
| 2.4 | Data freshness SLO defined and instrumented | Gauge metric `data_freshness_hours` | Engineer + Product Manager |
| 2.5 | PagerDuty integration (for P0/P1) | Test page acknowledged | Engineer + DevOps |
| 2.6 | Logging structured (JSON) and searchable | Sample log entry showing `severity`, `pipeline_name`, `user_id` | Engineer |

---

## 3. Compliance & Security (SOX, PII, HIPAA)

| # | Check | Evidence Required | Responsible |
|---|-------|-------------------|-------------|
| 3.1 | PII columns documented in data dictionary | `docs/data_dictionary.md` with `contains_pii: true` | Engineer + Compliance |
| 3.2 | PII redacted or hashed in logs | Code review: no `print(df['ssn'])`; `logging.info` uses `sha2` | Engineer |
| 3.3 | Audit table logging every run | Table `audit.pipeline_runs` with: `who`, `when`, `rows_affected`, `data_contract_version` | Engineer |
| 3.4 | Retention policy documented and enforced | Table property `delta.deletedFileRetentionDuration = 'interval 2555 days'` | Engineer |
| 3.5 | Access controls reviewed | Minimal necessary permissions; no `SELECT *` on PII tables | Compliance + Engineer |
| 3.6 | Data contract registered (for shared datasets) | Entry in `contract_registry.py` with owner team | Engineer |

---

## 4. Reliability & Operations

| # | Check | Evidence Required | Responsible |
|---|-------|-------------------|-------------|
| 4.1 | Airflow retries configured | `retries=3`, `retry_delay=timedelta(minutes=5)` | Engineer |
| 4.2 | Timeout set on tasks | `execution_timeout=timedelta(hours=2)` | Engineer |
| 4.3 | Resource limits defined | Spark: `maxExecutors=50`, `executorMemory=4g` | Engineer |
| 4.4 | Circuit breaker: pipeline stops if >10% rows fail validation | Great Expectations `fail_fast` or dbt `store_failures` + threshold check | Engineer |
| 4.5 | Runbook entry created for common failure modes | Link to `docs/oncall_runbook.md#pipeline-name` | Engineer + On-Call Lead |
| 4.6 | Schema drift detection enabled | dbt `--store-failures` or Great Expectations `expect_column_to_exist` | Engineer |
| 4.7 | Canary testing for streaming pipelines (if applicable) | Separate consumer on test topic with assertions | Engineer |

---

## 5. Code Quality & Maintainability

| # | Check | Evidence Required | Responsible |
|---|-------|-------------------|-------------|
| 5.1 | Unit tests for transformation logic | `pytest` suite with minimum 80% coverage | Engineer |
| 5.2 | Integration test with small sample dataset | `test_integration.py` runs on CI | Engineer |
| 5.3 | Type hints in all Python functions | `mypy --strict` passes | Engineer |
| 5.4 | Docstring for every public function | Example: `def ingest(...): """Args, Returns, Raises, Example"""` | Engineer |
| 5.5 | PR reviewed by at least one other engineer | GitHub PR approval | Engineer + Tech Lead |
| 5.6 | Pre-commit hooks configured | `black`, `isort`, `flake8`, `mypy` run automatically | Engineer |
| 5.7 | No secrets in code (verified) | `detect-secrets` or `trufflehog` scan clean | Engineer |

---

## 6. Performance & Cost

| # | Check | Evidence Required | Responsible |
|---|-------|-------------------|-------------|
| 6.1 | Query plans reviewed for shuffle/skew | Spark UI screenshot showing balanced partitions | Engineer |
| 6.2 | Partitioning strategy documented | Comment in code: `PARTITIONED BY (event_date)` | Engineer |
| 6.3 | Benchmarked at 3x expected volume | Spark job timing for 3 months of data | Engineer |
| 6.4 | Cost estimate documented | Snowflake credits / Spark compute hours per month | Engineer + FinOps |
| 6.5 | Auto-scaling configured (if applicable) | `spark.dynamicAllocation.enabled=true` | Engineer |
| 6.6 | Z-ordering / clustering for frequent filters | `OPTIMIZE table ZORDER BY (user_id, event_date)` | Engineer |

---

## 7. Documentation & Knowledge Transfer

| # | Check | Evidence Required | Responsible |
|---|-------|-------------------|-------------|
| 7.1 | Data dictionary updated | `docs/data_dictionary.md` includes: description, owner, PII flag, update frequency | Engineer |
| 7.2 | dbt documentation generated and accessible | `dbt docs serve` → internal wiki link | Engineer |
| 7.3 | Stakeholder communication sent (for new datasets) | Slack message to `#analytics` or `#data-science` | Engineer + Product Manager |
| 7.4 | On-call handoff document completed | `docs/oncall_runbook.md#pipeline-name` includes: owner, SLAs, common failures, escalation | Engineer + On-Call Lead |

---

## Sign-Off

| Role | Name | Date | Approval |
|------|------|------|----------|
| Engineer | [TBD] | | |
| Tech Lead | [TBD] | | |
| On-Call Lead | [TBD] | | |

**Next Review:** 90 days after deployment