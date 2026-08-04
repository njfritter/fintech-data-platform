# This DAG creates the connection if it doesn't exist
from airflow.models import Connection
from airflow.operators.python import PythonOperator
from airflow.sdk import dag
from airflow.hooks.base import BaseHook

from datetime import datetime
import json

def create_emr_connection():
    """Create EMR Serverless connection in Airflow metadata DB"""
    conn_id = 'emr_serverless_default'
    
    # Check if connection already exists
    try:
        existing_conn = BaseHook.get_connection(conn_id)
        print(f"ℹ️ Connection '{conn_id}' already exists. Skipping creation.")
        return
    except Exception:
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
    
    # Save the connection
    session = BaseHook.get_connections(conn_id).session
    session.add(conn)
    session.commit()
    print(f"✅ EMR Serverless connection '{conn_id}' created successfully!")


@dag(start_date=datetime(2024, 1, 1), schedule=None, catchup=False)
def emr_serverless_connection_setup():
    PythonOperator(
        task_id='create_emr_connection',
        python_callable=create_emr_connection,
    )

emr_serverless_connection_setup()