#!/usr/bin/env python3
"""
AWS Mock Data Generator for Fintech Data Platform
Generates and uploads mock data directly to S3 and MSK (Kafka)
"""

import json
import os
import random
import uuid
import argparse
from datetime import datetime, timedelta, date
from dateutil.relativedelta import relativedelta
import boto3
import pandas as pd
import numpy as np
from faker import Faker
from kafka import KafkaProducer
from confluent_kafka import Producer
from botocore.exceptions import ClientError
import socket
import time

# Try importing MSK IAM signer
try:
    from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
    MSK_SIGNER_AVAILABLE = True
except ImportError:
    MSK_SIGNER_AVAILABLE = False
    print("⚠️ aws_msk_iam_sasl_signer not available. IAM authentication will fail.")
    print("   Install with: pip install aws-msk-iam-sasl-signer-python")

# Initialize Faker
fake = Faker()
fake.seed_instance(42)
random.seed(42)
np.random.seed(42)


class MSKTokenProvider:
    """Token provider for IAM authentication with MSK"""
    
    def __init__(self, region: str):
        self.region = region
    
    def token(self):
        """Generate auth token using MSK IAM signer"""
        if MSK_SIGNER_AVAILABLE:
            token = MSKAuthTokenProvider.generate_auth_token(self.region)
            return token
        else:
            raise ImportError("aws_msk_iam_sasl_signer is not installed")


class AWSFinTechDataGenerator:
    """Generate and upload mock fintech data to AWS services"""
    
    def __init__(self, s3_bucket: str, kafka_bootstrap: str = None, aws_region: str = "us-east-1"):
        self.s3_bucket = s3_bucket
        self.aws_region = aws_region
        self.s3_client = boto3.client('s3', region_name=aws_region)
        
        # Initialize Kafka producer with IAM authentication if bootstrap servers provided
        self.kafka_producer = None
        if kafka_bootstrap:
            try:
                token_provider = MSKTokenProvider(aws_region)
                
                # Create the producer configuration
                producer_conf = {
                    'bootstrap.servers': kafka_bootstrap,
                    'security.protocol': 'SASL_SSL',
                    'sasl.mechanisms': 'OAUTHBEARER',
                    'sasl.oauthbearer.token': token_provider.token(),
                    'client.id': socket.gethostname(),
                    # Timeouts
                    'request.timeout.ms': 60000,
                    'metadata.max.age.ms': 60000,
                    'api.version.request.timeout.ms': 60000,
                    # Additional settings for reliability
                    'message.send.max.retries': 5,
                    'retry.backoff.ms': 1000,
                    'socket.keepalive.enable': True,
                    'enable.idempotence': True,
                }
                
                self.kafka_producer = Producer(producer_conf)

                print(f"✅ Kafka producer initialized with IAM authentication")
            except Exception as e:
                print(f"⚠️ Failed to initialize Kafka producer: {e}")
                self.kafka_producer = None
        
        # Pre-defined lookup values
        self.transaction_types = ['deposit', 'withdrawal', 'transfer', 'payment', 'fee', 'interest']
        self.transaction_statuses = ['completed', 'pending', 'failed', 'reversed']
        self.loan_purposes = ['personal', 'debt_consolidation', 'home_improvement', 'medical', 'education', 'business']
        self.loan_statuses = ['issued', 'current', 'delinquent_30', 'delinquent_60', 'delinquent_90', 'paid', 'charged_off']
        self.merchant_categories = ['grocery', 'restaurant', 'entertainment', 'travel', 'retail', 'gas', 'utilities']
        self.payment_methods = ['ach', 'credit_card', 'debit_card', 'bank_transfer']
        self.employment_statuses = ['employed', 'self_employed', 'unemployed', 'retired', 'student']
    
    def _random_date(self, start_date: date, end_date: date) -> date:
        """Generate random date between start and end"""
        time_between = end_date - start_date
        days_between = time_between.days
        random_days = random.randrange(days_between)
        return start_date + timedelta(days=random_days)
    
    def _upload_parquet_to_s3(self, df: pd.DataFrame, s3_key: str):
        """Upload a DataFrame as Parquet to S3"""
        # Write to temporary Parquet file
        temp_file = f"/tmp/{s3_key.split('/')[-1]}.parquet"
        df.to_parquet(temp_file, index=False)
        
        # Upload to S3
        try:
            self.s3_client.upload_file(temp_file, self.s3_bucket, s3_key)
            print(f"   ✅ Uploaded {len(df):,} rows to s3://{self.s3_bucket}/{s3_key}")
        except ClientError as e:
            print(f"   ❌ Failed to upload {s3_key}: {e}")
        finally:
            os.remove(temp_file)
    
    def generate_users(self, num_users: int = 10000) -> pd.DataFrame:
        """Generate user profiles with SCD-ready attributes"""
        users = []
        base_date = date(2020, 1, 1)
        end_date = date(2024, 12, 31)
        
        for i in range(num_users):
            created_at = self._random_date(base_date, end_date)
            raw_score = np.random.normal(680, 50)
            credit_score = int(max(300, min(850, raw_score)))
            
            users.append({
                'user_id': f"usr_{i+1:08d}",
                'name': fake.name(),
                'email': fake.email(),
                'phone': fake.phone_number(),
                'address': fake.address().replace('\n', ', '),
                'credit_score': credit_score,
                'credit_limit': int(credit_score * 12.5 * random.uniform(0.7, 1.3)),
                'annual_income': random.choice([30000, 50000, 75000, 100000, 150000, 200000]),
                'employment_status': random.choice(self.employment_statuses),
                'created_at': created_at,
                'updated_at': created_at,
                'is_active': random.random() > 0.08,
            })
        
        return pd.DataFrame(users)
    
    def generate_statements(self, users_df: pd.DataFrame, months_per_user: int = 24) -> pd.DataFrame:
        """Generate monthly credit card statements"""
        statements = []
        end_date = date(2024, 12, 31)
        
        for _, user in users_df.iterrows():
            user_id = user['user_id']
            created_at = user['created_at']
            
            # First statement is 30 days after creation
            first_statement = created_at + timedelta(days=30)
            
            # Generate statements monthly
            current_date = first_statement
            while current_date <= end_date:
                # Users who churned stop getting statements
                if not user['is_active'] and current_date > user['updated_at'] + timedelta(days=90):
                    break
                
                # Random statement amount
                balance_factor = (user['credit_score'] - 300) / 550
                balance = round(random.uniform(0, user['credit_limit']) * (0.3 + 0.5 * balance_factor), 2)
                min_payment = round(balance * random.uniform(0.02, 0.05), 2)
                
                statements.append({
                    'statement_id': f"stmt_{uuid.uuid4().hex[:12]}",
                    'user_id': user_id,
                    'statement_date': current_date,
                    'due_date': current_date + timedelta(days=21),
                    'balance': balance,
                    'minimum_payment': min_payment,
                    'total_charges': round(random.uniform(0, balance), 2),
                    'total_payments': round(random.uniform(0, balance * 0.5), 2),
                })
                
                # Move to next month safely using dateutil
                current_date = current_date + relativedelta(months=1)
        
        return pd.DataFrame(statements)
    
    def generate_payments(self, statements_df: pd.DataFrame) -> pd.DataFrame:
        """Generate payments against statements with delinquent behavior"""
        payments = []
        
        for _, stmt in statements_df.iterrows():
            # Probability of payment decreases with balance
            if stmt['balance'] > 5000:
                p_pay = 0.65
            elif stmt['balance'] > 1000:
                p_pay = 0.80
            else:
                p_pay = 0.92
            
            # Delinquent users (~12%)
            is_delinquent_user = random.random() < 0.12
            if is_delinquent_user:
                p_pay = 0.35
            
            if random.random() < p_pay:
                is_late = random.random() < 0.12
                payment_date = stmt['statement_date'] + timedelta(days=random.randint(5, 45))
                
                if not is_late:
                    payment_date = min(payment_date, stmt['due_date'])
                
                pays_full = random.random() < 0.65
                payment_amount = stmt['balance'] if pays_full else round(stmt['balance'] * random.uniform(0.3, 0.95), 2)
                
                payments.append({
                    'payment_id': f"pmt_{uuid.uuid4().hex[:12]}",
                    'statement_id': stmt['statement_id'],
                    'user_id': stmt['user_id'],
                    'payment_date': payment_date,
                    'payment_amount': payment_amount,
                    'payment_method': random.choice(self.payment_methods),
                    'is_late': is_late,
                    'is_full_payment': pays_full,
                })
        
        return pd.DataFrame(payments)
    
    def generate_transactions(self, users_df: pd.DataFrame, days: int = 365) -> pd.DataFrame:
        """Generate daily transaction events"""
        transactions = []
        end_date = date(2024, 12, 31)
        start_date = end_date - timedelta(days=days)
        
        event_types = ['transaction.created', 'transaction.settled', 'transaction.failed', 
                       'fraud_alert.triggered', 'payment.processed', 'dispute.opened']
        
        for _ in range(50000):
            event_date = self._random_date(start_date, end_date)
            user = users_df.iloc[random.randint(0, len(users_df) - 1)]
            
            transactions.append({
                'event_id': str(uuid.uuid4()),
                'event_type': random.choice(event_types),
                'user_id': user['user_id'],
                'user_credit_score': user['credit_score'],
                'transaction_amount': round(random.uniform(5, 5000), 2),
                'merchant_category': random.choice(self.merchant_categories),
                'timestamp': datetime.combine(event_date, datetime.min.time()),
                'is_foreign_transaction': random.random() < 0.06,
                'is_fraud_predicted': random.random() < 0.02,
                'device_id': f"dev_{uuid.uuid4().hex[:8]}",
            })
        
        return pd.DataFrame(transactions)
    
    def generate_loan_applications(self, users_df: pd.DataFrame, num_applications: int = 25000) -> pd.DataFrame:
        """Generate loan applications"""
        applications = []
        start_date = date(2021, 1, 1)
        end_date = date(2024, 12, 31)
        
        for i in range(num_applications):
            user = users_df.iloc[random.randint(0, len(users_df) - 1)]
            application_date = self._random_date(start_date, end_date)
            loan_amount = random.randint(1000, 50000)
            debt_to_income = loan_amount / max(user['annual_income'], 1)
            
            if user['credit_score'] > 720 and debt_to_income < 0.3:
                decision = 'approved'
                interest_rate = round(random.uniform(0.0499, 0.1199), 4)
            elif user['credit_score'] > 660 and debt_to_income < 0.4:
                decision = 'approved_conditional'
                interest_rate = round(random.uniform(0.0999, 0.1999), 4)
            elif user['credit_score'] > 600 and debt_to_income < 0.5:
                decision = 'pending_review'
                interest_rate = None
            else:
                decision = random.choices(['denied_credit', 'denied_income', 'denied_other'], weights=[0.6, 0.3, 0.1])[0]
                interest_rate = None
            
            applications.append({
                'application_id': f"app_{i+1:08d}",
                'user_id': user['user_id'],
                'application_date': application_date,
                'loan_amount': loan_amount,
                'loan_purpose': random.choice(self.loan_purposes),
                'credit_score_at_application': user['credit_score'],
                'decision': decision,
                'interest_rate_approved': interest_rate,
                'decision_timestamp': datetime.combine(application_date, datetime.min.time()) + timedelta(hours=random.randint(1, 72)),
            })
        
        return pd.DataFrame(applications)
    
    def upload_to_s3(self, output_dir: str = "bronze"):
        """Generate and upload all datasets to S3"""
        print("🚀 Generating mock fintech data for AWS deployment...")
        
        # Generate datasets
        users_df = self.generate_users(num_users=10000)
        print(f"   ✅ Generated {len(users_df):,} users")
        
        statements_df = self.generate_statements(users_df, months_per_user=24)
        print(f"   ✅ Generated {len(statements_df):,} statements")
        
        payments_df = self.generate_payments(statements_df)
        print(f"   ✅ Generated {len(payments_df):,} payments")
        
        transactions_df = self.generate_transactions(users_df, days=365)
        print(f"   ✅ Generated {len(transactions_df):,} transactions")
        
        loan_apps_df = self.generate_loan_applications(users_df, num_applications=25000)
        print(f"   ✅ Generated {len(loan_apps_df):,} loan applications")
        
        # Upload to S3
        print(f"\n📤 Uploading to s3://{self.s3_bucket}/{output_dir}")
        self._upload_parquet_to_s3(users_df, f"{output_dir}/users.parquet")
        self._upload_parquet_to_s3(statements_df, f"{output_dir}/statements.parquet")
        self._upload_parquet_to_s3(payments_df, f"{output_dir}/payments.parquet")
        self._upload_parquet_to_s3(transactions_df, f"{output_dir}/transactions.parquet")
        self._upload_parquet_to_s3(loan_apps_df, f"{output_dir}/loan_applications.parquet")
        
        print("\n✅ All data uploaded to S3!")
    
    def stream_to_kafka(self, num_events: int = 1000, topic: str = "fintech.events", interval_seconds: float = 0.1):
        """Stream events directly to MSK (Kafka)"""
        if not self.kafka_producer:
            print("❌ Kafka producer not initialized. Provide bootstrap servers.")
            return
        
        print(f"🚀 Streaming {num_events:,} events to MSK topic: {topic}")
        
        event_types = ['payment.processed', 'transaction.created', 'fraud.alert', 
                       'user.login', 'loan.application.submitted', 'card.transaction']
        
        def delivery_callback(err, msg):
            if err:
                print(f"   ❌ Delivery failed: {err}")
            # else: # Uncomment for verbose success logging
            #     print(f"   ✅ Delivered to {msg.topic()} at offset {msg.offset()}")

        for i in range(num_events):
            event = {
                'event_id': str(uuid.uuid4()),
                'event_type': random.choice(event_types),
                'user_id': f"usr_{random.randint(1, 10000):08d}",
                'timestamp': datetime.now().isoformat(),
                'payload': {
                    'amount': round(random.uniform(1, 5000), 2),
                    'status': random.choice(['success', 'failed', 'pending']),
                    'source': random.choice(['mobile_app', 'web', 'api']),
                    'session_id': f"sess_{uuid.uuid4().hex[:8]}"
                },
                'sequence': i
            }

            # Convert to JSON string
            event_str = json.dumps(event)
            
            try:
                # Produce the message
                self.kafka_producer.produce(
                    topic=topic,
                    key=str(i).encode('utf-8'),
                    value=event_str.encode('utf-8'),
                    callback=delivery_callback
                )
                if i % 100 == 0:
                    self.kafka_producer.flush()
                    print(f"   Sent {i} events...")

                # Optional: Add a small delay to simulate real streaming
                if interval_seconds:
                    time.sleep(interval_seconds)

            except Exception as e:
                print(f"   ⚠️ Failed to send event {i}: {e}")
        
        # Final flush to ensure all messages are sent
        self.kafka_producer.flush()
        print(f"✅ Sent {num_events:,} events to {topic}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate and upload mock fintech data to AWS")
    parser.add_argument("--s3-bucket", required=True, help="S3 bucket for data lake")
    parser.add_argument("--s3-prefix", default="bronze/", help="S3 prefix (default: bronze/)")
    parser.add_argument("--kafka-bootstrap", help="MSK bootstrap brokers (comma-separated)")
    parser.add_argument("--kafka-topic", default="fintech.events", help="Kafka topic (default: fintech.events)")
    parser.add_argument("--stream-count", type=int, default=1000, help="Number of streaming events")
    parser.add_argument("--aws-region", default="us-east-1", help="AWS region")
    
    args = parser.parse_args()
    
    generator = AWSFinTechDataGenerator(
        s3_bucket=args.s3_bucket,
        kafka_bootstrap=args.kafka_bootstrap,
        aws_region=args.aws_region
    )
    
    # Upload batch data to S3
    generator.upload_to_s3(args.s3_prefix)
    
    # Stream events to MSK (if bootstrap provided)
    if args.kafka_bootstrap and generator.kafka_producer:
        generator.stream_to_kafka(
            num_events=args.stream_count,
            topic=args.kafka_topic
        )
    elif args.kafka_bootstrap and not generator.kafka_producer:
        print("⚠️ Kafka producer initialization failed. Skipping streaming.")
    else:
        print("ℹ️ No Kafka bootstrap provided. Skipping streaming.")