# This DAG creates the connection if it doesn't exist
from airflow import DAG, settings
from airflow.models import Connection
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

from datetime import datetime
import json

# Define the absolute path to the Airflow CLI
AIRFLOW_CMD = "/home/ubuntu/.venv/bin/airflow"

# Connection details
CONN_ID = "emr_serverless_default"
CONN_TYPE = "aws"
CONN_EXTRA = json.dumps({
    "region_name": "us-east-1",
    "role_arn": "arn:aws:iam::891377165210:role/emr-serverless-job-role"
})

def create_emr_connection():
    """Create EMR Serverless connection in Airflow metadata DB"""
    conn_id = 'emr_serverless_default'
    
    # Check if connection already exists using settings.Session (which is stable)
    session = settings.Session()
    try:
        existing_conn = session.query(Connection).filter(
            Connection.conn_id == conn_id
        ).first()
        
        if existing_conn:
            print(f"ℹ️ Connection '{conn_id}' already exists. Skipping creation.")
            return
    except Exception as e:
        print(f"⚠️ Error checking for existing connection: {e}")
        # Continue to attempt creation
    finally:
        session.close()
    
    # Create the connection
    print(f"🔄 Connection '{conn_id}' not found. Creating it now...")
    new_conn = Connection(
        conn_id=conn_id,
        conn_type='aws',
        extra=json.dumps({
            'region_name': 'us-east-1',
            'role_arn': 'arn:aws:iam::891377165210:role/emr-serverless-job-role'
        })
    )
    
    # Add and commit the connection using a new session
    try:
        session = settings.Session()
        session.add(new_conn)
        session.commit()
        print(f"✅ EMR Serverless connection '{conn_id}' created successfully!")
    except Exception as e:
        print(f"❌ Failed to create connection: {e}")
        session.rollback()
        raise
    finally:
        session.close()


with DAG(
    'emr_serverless_connection_setup',
    start_date=datetime(2024, 1, 1),
    schedule=None,  # Manual trigger only
    catchup=False,
    tags=['setup', 'emr'],
) as dag:
    
    create_emr_connection = BashOperator(
        task_id='create_emr_connection',
        bash_command=f"""
            set -e  # Exit immediately if any command fails
            
            # Check if connection already exists
            if {AIRFLOW_CMD} connections get '{CONN_ID}' &> /dev/null; then
                echo "ℹ️ Connection '{CONN_ID}' already exists. Skipping creation."
                exit 0
            fi
            
            echo "🔄 Connection '{CONN_ID}' not found. Creating it now..."
            # The main command that creates the connection
            if {AIRFLOW_CMD} connections add '{CONN_ID}' \
                --conn-type '{CONN_TYPE}' \
                --conn-extra '{CONN_EXTRA}'; then
                echo "✅ EMR Serverless connection '{CONN_ID}' created successfully!"
            else
                echo "❌ Failed to create connection '{CONN_ID}'."
                exit 1
            fi
        """,
    )
    
    create_conn