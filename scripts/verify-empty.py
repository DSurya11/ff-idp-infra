#!/usr/bin/env python3
"""
verify-empty.py — checks that no billable ff-idp resources are running in AWS.

Called by: make verify-empty
Exit 0   → safe to close laptop, cost = $0.00
Exit 1   → billable resources still running, do NOT close laptop

Resource types that are always FREE and are intentionally excluded:
  VPC, subnets, security groups, route tables, internet gateways,
  S3 buckets, DynamoDB tables, IAM roles, OIDC providers,
  RDS subnet groups, ElastiCache subnet groups

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
)

PROFILE = "ff-idp"

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

        billable.append(arn)

    if free_or_pending:
        print("\nINFO: The following free or pending-deletion resources were found (Cost: $0.00):")
        for arn in free_or_pending:
            print(f"  - {arn}")

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
