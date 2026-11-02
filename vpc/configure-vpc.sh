#!/usr/bin/env bash

# ==============================================================================
# AWS VPC Setup Runbook (Bash Script)
# ==============================================================================
set -euo pipefail

# Configuration
REGION="ap-southeast-2"
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"

# change this as you setup
PROJECT_NAME="my-trial-vpc"

echo "=================================================="
echo "🚀 Building VPC: $PROJECT_NAME in $REGION"
echo "=================================================="

# 1. Create the VPC
echo "📦 Creating VPC (CIDR: $VPC_CIDR)..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc}]" \
    --query 'Vpc.VpcId' \
    --output text \
    --region $REGION)
echo "✅ VPC Created: $VPC_ID"

# 2. Create Public Subnet
echo "🌐 Creating Public Subnet ($PUBLIC_SUBNET_CIDR)..."
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PUBLIC_SUBNET_CIDR \
    --availability-zone ${REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-subnet}]" \
    --query 'Subnet.SubnetId' \
    --output text \
    --region $REGION)
echo "✅ Public Subnet Created: $PUBLIC_SUBNET_ID"

# 3. Create Private Subnet
echo "🔒 Creating Private Subnet ($PRIVATE_SUBNET_CIDR)..."
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PRIVATE_SUBNET_CIDR \
    --availability-zone ${REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-subnet}]" \
    --query 'Subnet.SubnetId' \
    --output text \
    --region $REGION)
echo "✅ Private Subnet Created: $PRIVATE_SUBNET_ID"

# 4. Create & Attach Internet Gateway
echo "🔌 Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text \
    --region $REGION)

aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID \
    --region $REGION
echo "✅ IGW Attached: $IGW_ID"

# 5. Configure Route Table for Public Subnet
echo "🗺️  Creating Public Route Table..."
PUBLIC_RT_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt}]" \
    --query 'RouteTable.RouteTableId' \
    --output text \
    --region $REGION)

# Add route to the internet
aws ec2 create-route \
    --route-table-id $PUBLIC_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID \
    --region $REGION > /dev/null

# Associate the public subnet with this route table
aws ec2 associate-route-table \
    --route-table-id $PUBLIC_RT_ID \
    --subnet-id $PUBLIC_SUBNET_ID \
    --region $REGION > /dev/null
echo "✅ Public Routing Configured (IGW attached to Public Subnet)"

# 6. Configure Route Table for Private Subnet (Isolated)
echo "🚧 Creating Private Route Table (Isolated)..."
PRIVATE_RT_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-rt}]" \
    --query 'RouteTable.RouteTableId' \
    --output text \
    --region $REGION)

# Associate the private subnet
aws ec2 associate-route-table \
    --route-table-id $PRIVATE_RT_ID \
    --subnet-id $PRIVATE_SUBNET_ID \
    --region $REGION > /dev/null
echo "✅ Private Routing Configured (Isolated, no internet access)"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo "=================================================="
echo "🎉 VPC Setup Complete!"
echo "=================================================="
echo "VPC ID:            $VPC_ID"
echo "Public Subnet:     $PUBLIC_SUBNET_ID"
echo "Private Subnet:    $PRIVATE_SUBNET_ID"
echo "IGW:               $IGW_ID"
echo "Public Route Table: $PUBLIC_RT_ID"
echo ""
echo "⚠️  REMEMBER TO CLEAN UP LATER TO SAVE CREDITS:"
echo "Run: aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION"