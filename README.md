# fintech-data-platform
A complete FinTech data platform designed to cover batch and streaming ETL, self service analytics, sensitive data and audit compliance and more for use cases such as lending, transactions and fraud detection.

## Project Rationale

Modern data platforms aren't built overnight and are not just about transforming data and loading it into a warehouse. Many factors must be taken into consideration: ensuring the data is accurate and modeled in a sustainable way, that the pipelines can be rerun to backfill historical data, the platform can scale to accomodate an order of magnitude of increased growth (i.e. 10x), and much more.

In this project I will be implementing a full fledged end to end data "fintech" (Financial Technology) data platform, supporting stakeholders such as Data Analysts, Data Scientists, Product Engineers and Compliance Analysts.

**NOTE: All business scenarios and data in this project are synthetic and are solely for the purpose of experimenting and learning.**

## Project Scope and Trajectory

Similar to how real world data systems evolve over time, this project will be built gradually with each stage building on the work of the previous stages.

Because this project uses synthetic data, there will need to be tools built out to help generate the data required for this project. There's no data platforms without data!

## High Level Architecture

Once the data generation functionality is built out, the rest of the platform will follow:
1. Extensible configuration based data ingestion layer
2. Staging data layer for raw, immutable data from source systems
3. Intermediate data layer for cleansed, deduplicated data
4. Business facing data layer with highly optimized tables for analysis and model training
5. Self service tooling layer for dashboarding, feature backfills and more
6. Observability stack encompassing metrics tracking, data lineage, oncall alerting, notifications and compliance logging 

A more detailed design doc can be found [here](docs/design_doc.md). A simplified architecture diagram can be seen below (design doc holds the more in depth architecture diagram):

![BankingBuddy Architecture Simplified](./docs/diagrams/bankingbuddy_architecture_simplified.png)

## High Level Platform Features

- Batch and streaming ETL use case support
- Configuration driven data ingestion from a wide variety of data sources and formats (and onboarding new sources)
- Clear data models that can scale to accommodate future analytical use cases
- Self service tools to allow for faster insights and experimentation
- Implements data auditability, sensitive data access controls and clear data usage distinctions
- Metrics tracking and on-call alerting for platform engineers
- Dashboards for executives and business leaders

## Local Setup

```bash
### Install brew and related packages
sh mac_quickstart.sh

## TODO: INSERT COMMAND TO DEPLOY DATA PLATFORM RESOURCES VIA DOCKER COMPOSE FILE
```

### Generating User Data

You can use the script `scripts/generate_mock_data.py` to generate the required data for the fintech data platform:

```bash
### Generate User Data for 10000 Users (default)
### Users, Statements, Payments, Transactions, Loan Applications
pipenv run scripts/generate_mock_data.py

### Generate User Data for 100000 Users
### Users, Statements, Payments, Transactions, Loan Applications
pipenv run scripts/generate_mock_data.py --users 100000

### Generate Streaming Data (default: 1000 events)
pipenv run scripts/generate_mock_data.py --stream

### Generate 100000 Streaming Events
pipenv run scripts/generate_mock_data.py --stream --stream-count 100000
```