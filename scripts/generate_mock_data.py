#!/usr/bin/env python3
"""
FinTech Mock Data Generator for Fintech Data Platform Project

Generates fintech-only data:
- Users (with credit scores, income, employment)
- Monthly credit card statements
- Payments (including delinquent behavior)
- Transaction events (for streaming)
- Loan applications

Usage:
    python scripts/generate_mock_data.py --output ./data --users 10000
    python scripts/generate_mock_data.py --stream --stream-count 1000
"""

import argparse
import json
import random
import uuid
import os
from datetime import datetime, timedelta, date
from dateutil.relativedelta import relativedelta
from typing import Dict, List, Optional, Tuple
import pandas as pd
import numpy as np

try:
    from faker import Faker
    FAKER_AVAILABLE = True
except ImportError:
    FAKER_AVAILABLE = False
    print("⚠️ Faker not installed. Run: pip install faker")
    print("   Generating limited mock data without Faker...")

# Initialize Faker if available
fake = Faker() if FAKER_AVAILABLE else None
if fake:
    fake.seed_instance(42)

# Set random seeds for reproducibility
random.seed(42)
np.random.seed(42)


class FinTechDataGenerator:
    """Generate realistic fintech data across multiple tables"""
    
    def __init__(self):
        # Pre-defined lookup values (fintech only)
        self.transaction_types = ['deposit', 'withdrawal', 'transfer', 'payment', 'fee', 'interest', 'refund']
        self.transaction_statuses = ['completed', 'pending', 'failed', 'reversed']
        self.loan_purposes = ['personal', 'debt_consolidation', 'home_improvement', 'medical', 'education', 'business', 'auto']
        self.loan_statuses = ['issued', 'current', 'delinquent_30', 'delinquent_60', 'delinquent_90', 'paid', 'charged_off']
        self.merchant_categories = ['grocery', 'restaurant', 'entertainment', 'travel', 'retail', 'gas', 'utilities']
        self.payment_methods = ['ach', 'credit_card', 'debit_card', 'bank_transfer', 'wire']
        self.employment_statuses = ['employed', 'self_employed', 'unemployed', 'retired', 'student']
        
    def _random_date(self, start_date: date, end_date: date) -> date:
        """Generate random date between start and end"""
        time_between = end_date - start_date
        days_between = time_between.days
        random_days = random.randrange(days_between)
        return start_date + timedelta(days=random_days)
    
    def _random_name(self) -> str:
        """Generate random name (fallback if Faker not available)"""
        first_names = ['James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer', 'Michael', 'Linda', 'William', 'Elizabeth']
        last_names = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez']
        return f"{random.choice(first_names)} {random.choice(last_names)}"
    
    def _random_email(self, name: str) -> str:
        """Generate email from name"""
        name_clean = name.lower().replace(' ', '.')
        domains = ['email.com', 'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com']
        return f"{name_clean}@{random.choice(domains)}"
    
    def generate_users(self, num_users: int = 10000) -> pd.DataFrame:
        """Generate user profiles with SCD-ready attributes"""
        users = []
        base_date = date(2020, 1, 1)
        end_date = date(2024, 12, 31)
        
        for i in range(num_users):
            created_at = self._random_date(base_date, end_date)
            raw_score = np.random.normal(680, 50)
            credit_score = int(max(300, min(850, raw_score)))
            
            if FAKER_AVAILABLE:
                name = fake.name()
                email = fake.email()
                address = fake.address().replace('\n', ', ')
                phone = fake.phone_number()
            else:
                name = self._random_name()
                email = self._random_email(name)
                address = "123 Main St, Anytown, USA"
                phone = f"{random.randint(100, 999)}-{random.randint(100, 999)}-{random.randint(1000, 9999)}"
            
            users.append({
                'user_id': f"usr_{i+1:08d}",
                'name': name,
                'email': email,
                'phone': phone,
                'address': address,
                'credit_score': credit_score,
                'credit_limit': int(credit_score * 12.5 * random.uniform(0.7, 1.3)),
                'annual_income': random.choice([30000, 50000, 75000, 100000, 150000, 200000]),
                'employment_status': random.choice(self.employment_statuses),
                'created_at': created_at,
                'updated_at': created_at,
                'is_active': random.random() > 0.08,  # 8% churn
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
                
                # Random statement amount between $0 and credit limit
                # Higher credit score users tend to carry higher balances
                balance_factor = (user['credit_score'] - 300) / 550  # 0 to 1
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
            
            # Delinquent users (~12% of the population)
            is_delinquent_user = random.random() < 0.12
            if is_delinquent_user:
                p_pay = 0.35
            
            if random.random() < p_pay:
                is_late = random.random() < 0.12  # 12% of payments are late
                payment_date = stmt['statement_date'] + timedelta(days=random.randint(5, 45))
                
                if not is_late:
                    payment_date = min(payment_date, stmt['due_date'])
                
                # Full payment vs partial
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
        """Generate daily transaction events (for streaming)"""
        transactions = []
        end_date = date(2024, 12, 31)
        start_date = end_date - timedelta(days=days)
        
        event_types = ['transaction.created', 'transaction.settled', 'transaction.failed', 
                       'fraud_alert.triggered', 'payment.processed', 'dispute.opened',
                       'card_issued', 'card_activated', 'limit_increased']
        
        num_transactions = 50000
        for _ in range(num_transactions):
            event_date = self._random_date(start_date, end_date)
            user = users_df.iloc[random.randint(0, len(users_df) - 1)]
            
            # Fraud is more likely for certain patterns
            is_fraud_predicted = False
            if random.random() < 0.02:  # 2% base fraud rate
                is_fraud_predicted = True
            
            transactions.append({
                'event_id': str(uuid.uuid4()),
                'event_type': random.choice(event_types),
                'user_id': user['user_id'],
                'user_credit_score': user['credit_score'],
                'transaction_amount': round(random.uniform(5, 5000), 2),
                'merchant_category': random.choice(self.merchant_categories),
                'timestamp': datetime.combine(event_date, datetime.min.time()),
                'is_foreign_transaction': random.random() < 0.06,
                'is_fraud_predicted': is_fraud_predicted,
                'device_id': f"dev_{uuid.uuid4().hex[:8]}",
            })
        
        return pd.DataFrame(transactions)
    
    def generate_loan_applications(self, users_df: pd.DataFrame, num_applications: int = 25000) -> pd.DataFrame:
        """Generate loan application events (for lending analytics)"""
        applications = []
        start_date = date(2021, 1, 1)
        end_date = date(2024, 12, 31)
        
        for i in range(num_applications):
            user = users_df.iloc[random.randint(0, len(users_df) - 1)]
            application_date = self._random_date(start_date, end_date)
            loan_amount = random.randint(1000, 50000)
            
            # Realistic decision logic based on credit score and income
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
    
    def save_all_data(self, output_dir: str = "./data"):
        """Generate and save all datasets"""
        print("🚀 Generating mock fintech data...")
        
        # Create directories
        os.makedirs(f"{output_dir}/bronze", exist_ok=True)
        os.makedirs(f"{output_dir}/silver", exist_ok=True)
        os.makedirs(f"{output_dir}/gold", exist_ok=True)
        os.makedirs(f"{output_dir}/streaming", exist_ok=True)
        
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
        
        # Save as Parquet (efficient, schema-preserving)
        users_df.to_parquet(f"{output_dir}/bronze/users.parquet", index=False)
        statements_df.to_parquet(f"{output_dir}/bronze/statements.parquet", index=False)
        payments_df.to_parquet(f"{output_dir}/bronze/payments.parquet", index=False)
        transactions_df.to_parquet(f"{output_dir}/bronze/transactions.parquet", index=False)
        loan_apps_df.to_parquet(f"{output_dir}/bronze/loan_applications.parquet", index=False)
        
        # Also save as CSV for easy inspection
        users_df.to_csv(f"{output_dir}/bronze/users.csv", index=False)
        statements_df.to_csv(f"{output_dir}/bronze/statements.csv", index=False)
        
        print(f"\n✅ Data generation complete!")
        print(f"   Output directory: {output_dir}")
        print(f"\n📊 Summary:")
        print(f"   - Users: {len(users_df):,}")
        print(f"   - Statements: {len(statements_df):,}")
        print(f"   - Payments: {len(payments_df):,}")
        print(f"   - Transactions: {len(transactions_df):,}")
        print(f"   - Loan Applications: {len(loan_apps_df):,}")
        
        # Sample output for verification
        print(f"\n📋 Sample user:")
        print(users_df.head(1).to_string())
        
        return {
            'users': users_df,
            'statements': statements_df,
            'payments': payments_df,
            'transactions': transactions_df,
            'loan_applications': loan_apps_df
        }


def generate_streaming_events(output_dir: str = "./data", num_events: int = 1000):
    """Generate streaming events as JSON lines for Kafka"""
    os.makedirs(f"{output_dir}/streaming", exist_ok=True)
    
    events = []
    event_types = ['payment.processed', 'transaction.created', 'fraud.alert', 'user.login', 
                   'loan.application.submitted', 'card.transaction', 'credit.limit.changed']
    
    for i in range(num_events):
        event = {
            'event_id': str(uuid.uuid4()),
            'event_type': random.choice(event_types),
            'user_id': f"usr_{random.randint(1, 10000):08d}",
            'timestamp': datetime.now().isoformat(),
            'payload': {
                'amount': round(random.uniform(1, 5000), 2),
                'status': random.choice(['success', 'failed', 'pending']),
                'source': random.choice(['mobile_app', 'web', 'api', 'ios', 'android']),
                'session_id': f"sess_{uuid.uuid4().hex[:8]}"
            },
            'sequence': i
        }
        events.append(json.dumps(event))
    
    with open(f"{output_dir}/streaming/events.jsonl", 'w') as f:
        f.write('\n'.join(events))
    
    print(f"✅ Generated {num_events:,} streaming events → {output_dir}/streaming/events.jsonl")
    
    # Show sample
    print(f"\n📋 Sample streaming event:")
    print(f"{events[0][:200]}...")


def verify_data(output_dir: str = "./data"):
    """Quick verification that data was generated correctly"""
    print("\n🔍 Verifying generated data...")
    
    files_to_check = [
        "bronze/users.parquet",
        "bronze/statements.parquet", 
        "bronze/payments.parquet",
        "bronze/transactions.parquet",
        "bronze/loan_applications.parquet"
    ]
    
    for file_path in files_to_check:
        full_path = f"{output_dir}/{file_path}"
        if os.path.exists(full_path):
            size = os.path.getsize(full_path) / 1024  # KB
            print(f"   ✅ {file_path} ({size:.1f} KB)")
        else:
            print(f"   ❌ {file_path} not found")
    
    print("\n✅ Verification complete!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate mock fintech data for FinCore project")
    parser.add_argument("--output", default="./data", help="Output directory (default: ./data)")
    parser.add_argument("--users", type=int, default=10000, help="Number of users to generate (default: 10000)")
    parser.add_argument("--stream", action="store_true", help="Generate streaming events only")
    parser.add_argument("--stream-count", type=int, default=1000, help="Number of streaming events (default: 1000)")
    parser.add_argument("--verify", action="store_true", help="Verify existing data")
    
    args = parser.parse_args()
    
    if args.verify:
        verify_data(args.output)
    elif args.stream:
        generate_streaming_events(args.output, args.stream_count)
    else:
        generator = FinTechDataGenerator()
        generator.save_all_data(args.output)
        verify_data(args.output)