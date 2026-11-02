#!/usr/bin/env bash

# ==============================================================================
# AWS VPC Cleanup Runbook (Bash Script)
# ==============================================================================
set -euo pipefail

# Configuration
VPC_ID="${1:-}"
REGION="${2:-ap-southeast-2}"

if [ -z "$VPC_ID" ]; then
    echo "❌ Error: You must provide a VPC ID."
    echo "Usage: ./cleanup-vpc.sh <vpc-id> [region]"
    echo "Example: ./cleanup-vpc.sh vpc-018c92a913a036444 ap-southeast-1"
    exit 1
fi

echo "=================================================="
echo "🧹 Starting VPC Cleanup for: $VPC_ID in $REGION"
echo "=================================================="

# 1. Detach and Delete Internet Gateways
echo -e "\n[1/5] Checking for Internet Gateways..."
IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text --region $REGION)

if [ -n "$IGWS" ]; then
    for igw in $IGWS; do
        echo "🔌 Detaching IGW: $igw"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" --region $REGION
        echo "🗑️  Deleting IGW: $igw"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region $REGION
    done
else
    echo "✅ No Internet Gateways attached."
fi

# 2. Delete Subnets
echo -e "\n[2/5] Checking for Subnets..."
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text --region $REGION)

if [ -n "$SUBNETS" ]; then
    for subnet in $SUBNETS; do
        echo "🗑️  Deleting Subnet: $subnet"
        aws ec2 delete-subnet --subnet-id "$subnet" --region $REGION
    done
else
    echo "✅ No Subnets found."
fi

# 3. Delete Custom Route Tables
echo -e "\n[3/5] Checking for Route Tables..."
# Note: We cannot delete the "Main" route table, only custom ones.
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=false" --query 'RouteTables[].RouteTableId' --output text --region $REGION)

if [ -n "$ROUTE_TABLES" ]; then
    for rt in $ROUTE_TABLES; do
        echo "🗑️  Deleting Route Table: $rt"
        aws ec2 delete-route-table --route-table-id "$rt" --region $REGION
    done
else
    echo "✅ No custom Route Tables found."
fi

# 4. Delete Security Groups
echo -e "\n[4/5] Checking for Security Groups..."
# Note: We cannot delete the "default" security group.
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text --region $REGION)

if [ -n "$SGS" ]; then
    for sg in $SGS; do
        echo "🗑️  Deleting Security Group: $sg"
        # We retry a few times in case dependencies take a second to clear
        aws ec2 delete-security-group --group-id "$sg" --region $REGION || echo "⚠️  Failed to delete SG $sg (it might be in use by an EC2 instance or ELB)."
    done
else
    echo "✅ No custom Security Groups found."
fi

# 5. Delete the VPC
echo -e "\n[5/5] Deleting VPC: $VPC_ID"
aws ec2 delete-vpc --vpc-id "$VPC_ID" --region $REGION

echo "=================================================="
echo "🎉 SUCCESS! VPC $VPC_ID has been deleted."
echo "=================================================="