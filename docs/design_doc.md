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

