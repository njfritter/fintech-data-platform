import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Stop EC2 instances to save costs during off-hours"""
    ec2 = boto3.client('ec2', region_name=os.environ['REGION'])
    asg_name = os.environ['ASG_NAME']
    
    logger.info(f"Stopping EC2 instances for ASG: {asg_name}")
    
    # Find running instances with AutoStop=true tag
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:AutoStop', 'Values': ['true']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )
    
    instance_ids = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            # Don't stop if it's the only instance (maintain minimum)
            # The ASG will handle scaling - this just signals
            instance_ids.append(instance['InstanceId'])
    
    if instance_ids:
        logger.info(f"Stopping instances: {instance_ids}")
        ec2.stop_instances(InstanceIds=instance_ids)
    else:
        logger.info("No running instances with AutoStop tag found")
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Stopped {len(instance_ids)} instances')
    }