# This DAG creates the connection if it doesn't exist
from airflow import DAG, settings
from airflow.models import Connection
from airflow.operators.python import PythonOperator
from datetime import datetime

def create_emr_connection():
    """Create EMR Serverless connection in Airflow metadata DB"""
    session = settings.Session()
    
    # Check if connection already exists
    existing = session.query(Connection).filter(
        Connection.conn_id == 'emr_serverless_default'
    ).first()
    
    if not existing:
        conn = Connection(
            conn_id='emr_serverless_default',
            conn_type='aws',
            extra={
                'region_name': 'us-east-1',
                'role_arn': 'arn:aws:iam::891377165210:role/emr-serverless-job-role'
            }
        )
        session.add(conn)
        session.commit()
        print("✅ EMR Serverless connection created")
    else:
        print("ℹ️ EMR Serverless connection already exists")
    session.close()

with DAG(
    'emr_serverless_connection_setup',
    schedule_interval=None,  # Manual trigger only
    start_date=datetime(2024, 1, 1),
    catchup=False,
) as dag:
    create_conn = PythonOperator(
        task_id='create_emr_connection',
        python_callable=create_emr_connection,
    )