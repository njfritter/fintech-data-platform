# Product Requirements Document (PRD) - BankingBuddy Data Platform (BBDP)

> **📌 Note on Authorship:** This document is **adapted from a standard PRD template** for portfolio purposes. It represents the *type* of business context a data engineer should seek out and document, not original product management work. The technical decisions in [`design_doc.md`](./design_doc.md) and corresponding implementation are my own.
>
> **Purpose:** To simulate working with a Product Manager and document business assumptions before building. In a real role, I would collaborate with PMs to create this document.

---

## 1. One-Sentence Summary

BankingBuddy needs a data platform to track key business metrics, detect fraud in real-time, implement sensitive data and audit compliance, and enable self-service analytics as we scale from 500k to 5M users.

---

## 2. Business Problem (The "Why")

**The pain today:**
- Finance team spends 4 hours answering key business questions like calculating delinquency rate (often wrong due to duplicate payments)
- Fraud losses increased 15% last month—no real-time detection
- Marketing cannot attribute spend to LTV; data lives in spreadsheets
- No audit trails for SOX compliance (regulatory reporting starts next quarter)

**What success looks like:**
- Key metrics available in <1 second (query, not 4-hour script)
- Fraud alerts within 500ms
- Self-service dashboards for Marketing, Product, Finance
- Mock audit passes with zero findings

---

## 3. Who This Is For (Stakeholders)

| Persona | What They Need | Success Metric |
|---------|----------------|----------------|
| **Finance** | Trusted metrics, audit trails | Query takes <1 second, matches audit |
| **Data Science** | Feature backfills without engineering help | 90 days of features in <1 hour |
| **Marketing** | Channel LTV attribution, daily | Dashboard opens in <5 seconds |
| **Compliance** | PII access logs, retention policies | Mock audit passes |
| **Product** | Experiment results in 24 hours (not 1 week) | Automated dashboard |
| **CEO** | Answers in 5 minutes, not 4 hours | Self-service |

---

## 4. What We're Building (MVP Scope)

**In scope (3 months):**

| Feature | Description | Priority |
|---------|-------------|----------|
| Batch ingestion | Daily files from partners (CSV, Parquet, 837 EDI) | P0 |
| Streaming ingestion | Transaction events from Kafka | P0 |
| Snapshot fact table | Key business metrics | P0 |
| SCD Type 2 | Track user credit score changes over time | P0 |
| Data quality | Great Expectations validation, <1% failure rate | P1 |
| Observability | Prometheus + Grafana, Slack alerts on SLA breach | P1 |
| Self-service | Metabase dashboards, feature backfill library | P1 |
| Compliance | Audit tables, PII access logs, 7-year retention | P0 |

**Out of scope (Phase 2):**
- Real-time fraud model inference (batch scoring initially)
- Online feature store (batch features sufficient)
- Reverse ETL to operational systems

---

## 5. Success Metrics (How We'll Know It Worked)

| Metric | Baseline (Today) | Target (Month 3) |
|--------|------------------|------------------|
| Time to answer key business metrics | 4 hours | <1 second |
| Fraud detection latency | Days (manual) | <500ms |
| Manual reporting hours/week | 20 | <5 |
| PII access logging coverage | 0% | 100% |
| Pipeline success rate | Unknown | >99.9% |
| Data freshness (batch) | >24 hours | <4 hours |
| Stakeholder trust (survey) | Unknown | >80% say "I trust the data" |

---

## 6. Key Decisions (Why These Choices)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage format | Delta Lake on S3 | Open format, ACID, no lock-in; supports our ML roadmap |
| Streaming engine | Spark Structured Streaming (RTM) | Single stack for batch + streaming; meets <500ms SLA |
| Orchestration | Airflow | Python-native, 2000+ providers, backfill support |

**Full trade-off analysis (Delta Lake vs. Snowflake, Spark vs. Flink):** See `design_doc.md`

---

## 7. Timeline (3 Months)

| Month | Focus | Key Deliverable |
|-------|-------|-----------------|
| 1 | Foundation | Bronze + Silver layers, snapshot fact table |
| 2 | Quality | Data quality tests, observability, alerts |
| 3 | Self-Service + Compliance | Dashboards, feature backfills, audit logs |

**Go/No-Go for launch:** All P0 features complete + mock audit passes.

---

## 8. Risks & Mitigations

| Risk | Probability | Mitigation |
|------|------------|------------|
| Single engineer bottleneck | Medium | Document everything; hire second DE in Month 4 |
| Spark learning curve | Medium | Use dbt for SQL-heavy work first |
| Compliance requirement changes | Low | Build audit logging as default |
| Cloud costs spiral | Medium | Budget alert + Terraform cost estimation + Regular audits of most expensive jobs |

---

## 9. Stakeholder Sign-Off (Hypothetical)

| Role | Name | Status |
|------|------|--------|
| CEO | [Simulated] | ✅ Aligned |
| CFO | [Simulated] | ✅ Aligned |
| CPO | [Simulated] | ✅ Aligned |
| CTO | [Simulated] | ✅ Aligned |

---

## 10. Related Documents

- **Technical deep dive:** [`design_doc.md`](./design_doc.md) (architecture, trade-offs, implementation)
- **Data definitions:** [`data_dictionary.md`](./data_dictionary.md)
- **Production checklist:** [`production_readiness_checklist.md`](./production_readiness_checklist.md)
- **On-call procedures:** [`oncall_runbook.md`](./oncall_runbook.md)

---

## 11. Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05-05 | Data Engineer (adapted from template) | Initial version for portfolio |

---

**Questions or feedback?** Open a GitHub issue or reach out via [LinkedIn](https://linkedin.com/in/njfritter).