# This DAG does nothing; purely to test that Airflow is working properly
# It can be triggered manually to verify that the Airflow environment is set up correctly.
from airflow import DAG
from airflow.operators.python import PythonOperator

from datetime import datetime

def hello_world():
    """A simple function to print a hello world message."""
    print("Hello, World! Airflow is working properly.")

with DAG(
    'simple_dag',
    start_date=datetime(2024, 1, 1),
    schedule=None,  # Manual trigger only
    catchup=False,
    tags=['setup', 'airflow'],
) as dag:
    
    hello_task = PythonOperator(
        task_id='hello_world',
        python_callable=hello_world,
    )
    
    hello_task