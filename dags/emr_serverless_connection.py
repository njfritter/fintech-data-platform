# This DAG creates the connection if it doesn't exist
from airflow import DAG
from airflow.exceptions import AirflowNotFoundException
from airflow.models import Connection
from airflow.operators.python import PythonOperator
from airflow.hooks.base import BaseHook

from datetime import datetime
import json

def create_emr_connection():
    """Create EMR Serverless connection in Airflow metadata DB"""
    conn_id = 'emr_serverless_default'
    
    try:
        # Try to get the connection - this will raise AirflowNotFoundException if it doesn't exist
        existing_conn = BaseHook.get_connection(conn_id)
        print(f"ℹ️ Connection '{conn_id}' already exists. Skipping creation.")
        return
    except AirflowNotFoundException:
        print(f"🔄 Connection '{conn_id}' not found. Creating it now...")
    
    # Create the connection
    conn = Connection(
        conn_id=conn_id,
        conn_type='aws',
        extra=json.dumps({
            'region_name': 'us-east-1',
            'role_arn': 'arn:aws:iam::891377165210:role/emr-serverless-job-role'
        })
    )
    
    # Add and commit the connection
    try:
        session = BaseHook.get_hook().get_session()
        session.add(conn)
        session.commit()
        print(f"✅ EMR Serverless connection '{conn_id}' created successfully!")
    except Exception as e:
        print(f"❌ Failed to create connection: {e}")
        session.rollback()
        raise


with DAG(
    'emr_serverless_connection_setup',
    start_date=datetime(2024, 1, 1),
    schedule=None,  # Manual trigger only
    catchup=False,
    tags=['setup', 'emr'],
) as dag:
    
    create_conn = PythonOperator(
        task_id='create_emr_connection',
        python_callable=create_emr_connection,
    )
    
    create_conn