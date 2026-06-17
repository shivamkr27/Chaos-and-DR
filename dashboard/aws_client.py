import boto3
from config import PROJECT, AWS_REGION_PRIMARY, AWS_REGION_DR


def _ec2(region):
    return boto3.client("ec2", region_name=region)

def _rds(region):
    return boto3.client("rds", region_name=region)

def _r53():
    return boto3.client("route53")


def get_ec2_status(region):
    """Return 'running' | 'stopped' | 'unknown' for the K3s node in a region."""
    try:
        alias = "primary" if region == AWS_REGION_PRIMARY else "dr"
        resp = _ec2(region).describe_instances(
            Filters=[
                {"Name": "tag:Project", "Values": [PROJECT]},
                {"Name": "tag:Region",  "Values": [alias]},
            ]
        )
        reservations = resp.get("Reservations", [])
        if not reservations:
            return "unknown"
        return reservations[0]["Instances"][0]["State"]["Name"]
    except Exception as e:
        return f"error: {e}"


def stop_ec2(region):
    """Stop the K3s EC2 node — used by region-failure chaos button."""
    alias = "primary" if region == AWS_REGION_PRIMARY else "dr"
    resp = _ec2(region).describe_instances(
        Filters=[
            {"Name": "tag:Project", "Values": [PROJECT]},
            {"Name": "tag:Region",  "Values": [alias]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    reservations = resp.get("Reservations", [])
    if not reservations:
        raise ValueError(f"No running instance found in {region}")
    instance_id = reservations[0]["Instances"][0]["InstanceId"]
    _ec2(region).stop_instances(InstanceIds=[instance_id])
    return instance_id


def start_ec2(region):
    """Restart the K3s EC2 node — used by recovery button."""
    alias = "primary" if region == AWS_REGION_PRIMARY else "dr"
    resp = _ec2(region).describe_instances(
        Filters=[
            {"Name": "tag:Project", "Values": [PROJECT]},
            {"Name": "tag:Region",  "Values": [alias]},
            {"Name": "instance-state-name", "Values": ["stopped"]},
        ]
    )
    reservations = resp.get("Reservations", [])
    if not reservations:
        raise ValueError(f"No stopped instance found in {region}")
    instance_id = reservations[0]["Instances"][0]["InstanceId"]
    _ec2(region).start_instances(InstanceIds=[instance_id])
    return instance_id


def get_rds_status(region):
    """Return DB instance status + replication lag info."""
    try:
        alias = "primary" if region == AWS_REGION_PRIMARY else "dr"
        suffix = "postgres" if alias == "primary" else "postgres-replica"
        db_id = f"{PROJECT}-{alias}-{suffix}"
        resp = _rds(region).describe_db_instances(DBInstanceIdentifier=db_id)
        db = resp["DBInstances"][0]
        return {
            "status":   db["DBInstanceStatus"],
            "endpoint": db.get("Endpoint", {}).get("Address", "N/A"),
            "is_replica": bool(db.get("ReadReplicaSourceDBInstanceIdentifier")),
        }
    except Exception as e:
        return {"status": f"error: {e}", "endpoint": "N/A", "is_replica": False}


def get_route53_health(health_check_id):
    """Return latest health check status from Route 53."""
    try:
        resp = _r53().get_health_check_status(HealthCheckId=health_check_id)
        obs = resp.get("HealthCheckObservations", [])
        if not obs:
            return "unknown"
        # If ANY checker reports healthy, we consider it healthy
        statuses = [o["StatusReport"]["Status"] for o in obs]
        return "healthy" if any("Success" in s for s in statuses) else "unhealthy"
    except Exception:
        return "unknown"
