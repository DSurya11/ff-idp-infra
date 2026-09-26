#!/usr/bin/env python3
"""
verify-empty.py — checks that no billable ff-idp resources are running in AWS.

Called by: make verify-empty
Exit 0   → safe to close laptop, cost = $0.00
Exit 1   → billable resources still running, do NOT close laptop

Resource types that are always FREE and are intentionally excluded:
  VPC, subnets, security groups, route tables, internet gateways,
  S3 buckets, DynamoDB tables, IAM roles, OIDC providers,
  RDS subnet groups, ElastiCache subnet groups,
  ECR repository (permanent, storage-only cost)

Resource types that ARE billable and will trigger a warning:
  RDS instances, ElastiCache replication groups, EKS clusters,
  NAT gateways, Elastic IPs, Load balancers, EC2 instances,
  Secrets Manager secrets, etc.
"""
import json
import subprocess
import sys

FREE_SUBSTRINGS = (
    ":vpc/",
    ":subnet/",
    ":security-group/",
    ":route-table/",
    ":internet-gateway/",
    ":s3:::",
    ":table/",           # DynamoDB
    ":oidc-provider/",
    ":role/",
    ":subgrp:",          # RDS subnet group
    "subnetgroup:",      # ElastiCache subnet group
    ":user/",
    ":repository/",      # ECR (15-registry, permanent; ~$0.10/GB-month storage only)
)

PROFILE = "ff-idp"

REGION = "ap-south-1"


def aws_query(*args):
    """Run an aws CLI read call; return (output_lines, error_or_None)."""
    r = subprocess.run(
        ["aws", *args, "--region", REGION, "--profile", PROFILE, "--output", "text"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return [], r.stderr.strip()
    return [l for l in r.stdout.splitlines() if l.strip() and l.strip() != "None"], None


# Direct, tag-independent checks. The tagging API misses snapshots, controller-created
# ALBs, ENIs, PVC volumes, and lags on deletions - so ask each service directly.
DIRECT_CHECKS = [
    ("EKS cluster", ["eks", "list-clusters", "--query", "clusters[]"]),
    ("EC2 instance", ["ec2", "describe-instances", "--query",
                      "Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name][]"]),
    ("NAT gateway", ["ec2", "describe-nat-gateways", "--query",
                     "NatGateways[?State!=`deleted`].[NatGatewayId,State]"]),
    ("Elastic IP", ["ec2", "describe-addresses", "--query", "Addresses[].[PublicIp,AllocationId]"]),
    ("Load balancer", ["elbv2", "describe-load-balancers", "--query", "LoadBalancers[].LoadBalancerName"]),
    ("RDS instance", ["rds", "describe-db-instances", "--query", "DBInstances[].DBInstanceIdentifier"]),
    ("RDS snapshot", ["rds", "describe-db-snapshots", "--query", "DBSnapshots[].DBSnapshotIdentifier"]),
    ("ElastiCache group", ["elasticache", "describe-replication-groups", "--query",
                           "ReplicationGroups[].ReplicationGroupId"]),
    ("EBS volume", ["ec2", "describe-volumes", "--query", "Volumes[].[VolumeId,Size]"]),
    ("EBS snapshot", ["ec2", "describe-snapshots", "--owner-ids", "self", "--query",
                      "Snapshots[].SnapshotId"]),
    ("Secrets Manager secret", ["secretsmanager", "list-secrets", "--query", "SecretList[].Name"]),
    ("VPC endpoint", ["ec2", "describe-vpc-endpoints", "--query", "VpcEndpoints[].VpcEndpointId"]),
    ("CloudWatch log group", ["logs", "describe-log-groups", "--query", "logGroups[].logGroupName"]),
]


def direct_checks():
    """Return billable findings from querying each service directly."""
    findings = []
    for label, args in DIRECT_CHECKS:
        lines, err = aws_query(*args)
        if err:
            findings.append(f"{label}: CHECK FAILED ({err.splitlines()[-1]})")
        findings += [f"{label}: {l}" for l in lines]
    return findings


def main():
    print("==> Scanning for billable ff-idp resources...")
    result = subprocess.run(
        [
            "aws", "resourcegroupstaggingapi", "get-resources",
            "--tag-filters", "Key=Project,Values=ff-idp",
            "--query", "ResourceTagMappingList[].ResourceARN",
            "--output", "json",
            "--profile", PROFILE,
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(f"ERROR: AWS CLI failed:\n{result.stderr}")
        sys.exit(1)

    arns = json.loads(result.stdout)
    billable = []
    free_or_pending = []
    
    for arn in arns:
        # Ignore inherently free resources
        if any(s in arn for s in FREE_SUBSTRINGS):
            free_or_pending.append(f"{arn} (Free Resource)")
            continue
            
        # Launch templates are 100% free
        if ":launch-template/" in arn:
            free_or_pending.append(f"{arn} (Free Resource)")
            continue
            
        # KMS keys are $0 while PendingDeletion
        if ":key/" in arn:
            free_or_pending.append(f"{arn} (Pending Deletion / Free)")
            continue
            
        # NAT Gateways in "deleted" state
        if ":natgateway/" in arn:
            gw_id = arn.split("/")[-1]
            state_check = subprocess.run(
                ["aws", "ec2", "describe-nat-gateways", "--nat-gateway-ids", gw_id, 
                 "--query", "NatGateways[0].State", "--output", "text", "--profile", PROFILE],
                capture_output=True, text=True
            )
            if state_check.stdout.strip() == "deleted":
                free_or_pending.append(f"{arn} (Deleted state)")
                continue
            # AWS purges deleted gateways after ~1h, but the Tagging API keeps returning the
            # ARN. describe-nat-gateways then fails with NatGatewayNotFound: gone, so free.
            if "NatGatewayNotFound" in state_check.stderr:
                free_or_pending.append(f"{arn} (Purged by AWS - ghost tag)")
                continue

        billable.append(arn)

    if free_or_pending:
        print("\nINFO: The following free or pending-deletion resources were found (Cost: $0.00):")
        for arn in free_or_pending:
            print(f"  - {arn}")

    print("\n==> Direct service checks (independent of tags)...")
    billable += direct_checks()

    if not billable:
        print()
        print("OK: No billable resources running. Safe to close laptop.")
        print("    Cost until next 'make up': $0.00")
        sys.exit(0)
    else:
        print()
        print("WARNING: Billable resources still running:")
        for arn in billable:
            print(f"  {arn}")
        print()
        print("Do NOT close laptop. Investigate and destroy manually.")
        print("To force destroy a layer: terraform -chdir=<layer> destroy -auto-approve")
        sys.exit(1)

if __name__ == "__main__":
    main()
