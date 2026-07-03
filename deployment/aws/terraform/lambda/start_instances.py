import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Start EC2 instances when the ASG needs to scale up"""
    ec2 = boto3.client('ec2', region_name=os.environ['REGION'])
    asg_name = os.environ['ASG_NAME']
    
    logger.info(f"Starting EC2 instances for ASG: {asg_name}")
    
    # Update ASG desired capacity to the configured value
    # This is handled by the ASG's scaling policies - this function
    # is triggered on schedule to ensure capacity is available
    
    # For a simpler approach: find instances with 'AutoStop=true' tag and start them
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:AutoStop', 'Values': ['true']},
            {'Name': 'instance-state-name', 'Values': ['stopped']}
        ]
    )
    
    instance_ids = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_ids.append(instance['InstanceId'])
    
    if instance_ids:
        logger.info(f"Starting instances: {instance_ids}")
        ec2.start_instances(InstanceIds=instance_ids)
    else:
        logger.info("No stopped instances with AutoStop tag found")
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Started {len(instance_ids)} instances')
    }