#!/usr/bin/env bash

# ==============================================================================
# AWS Security Group Setup Runbook (Web, App, DB Tiers)
# ==============================================================================
set -euo pipefail

# Configuration
VPC_ID="${1:-}"
REGION="${2:-ap-southeast-2}"
PROJECT="web-app"

if [ -z "$VPC_ID" ]; then
    echo "❌ Error: You must provide a VPC ID."
    echo "Usage: ./setup.sh <vpc-id> [region]"
    echo "Example: ./setup.sh vpc-018c92a913a036444 ap-southeast-1"
    exit 1
fi

echo "=================================================="
echo "🛡️  Creating Tiered Security Groups in $VPC_ID"
echo "=================================================="

# ------------------------------------------------------------------------------
# 1. Web Tier / Load Balancer Security Group
# ------------------------------------------------------------------------------
echo -e "\n[1/3] Creating Web/ALB Security Group..."
WEB_SG_ID=$(aws ec2 create-security-group \
    --group-name "${PROJECT}-web-sg" \
    --description "Allow HTTP/HTTPS from internet" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text --region "$REGION")

# Allow HTTP and HTTPS from the world
aws ec2 authorize-security-group-ingress \
    --group-id "$WEB_SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0 \
    --region "$REGION" > /dev/null

aws ec2 authorize-security-group-ingress \
    --group-id "$WEB_SG_ID" \
    --protocol tcp --port 443 --cidr 0.0.0.0/0 \
    --region "$REGION" > /dev/null
echo "✅ Web SG Created: $WEB_SG_ID (Port 80/443 from 0.0.0.0/0)"

# ------------------------------------------------------------------------------
# 2. Application Tier Security Group (Multiple Ports)
# ------------------------------------------------------------------------------
echo -e "\n[2/3] Creating Application Security Group..."
APP_SG_ID=$(aws ec2 create-security-group \
    --group-name "${PROJECT}-app-sg" \
    --description "Allow app traffic only from Web SG" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text --region "$REGION")

# --- Define your app ports here ---
APP_PORTS=(3001 3002 8080 9090)

for PORT in "${APP_PORTS[@]}"; do
    echo "🔓 Allowing Port $PORT from Web SG..."
    aws ec2 authorize-security-group-ingress \
        --group-id "$APP_SG_ID" \
        --protocol tcp --port "$PORT" \
        --source-group "$WEB_SG_ID" \
        --region "$REGION" > /dev/null
done
echo "✅ App SG Created: $APP_SG_ID (Ports ${APP_PORTS[*]} from Web SG)"

# ------------------------------------------------------------------------------
# 3. Database Tier Security Group
# ------------------------------------------------------------------------------
echo -e "\n[3/3] Creating Database Security Group..."
DB_SG_ID=$(aws ec2 create-security-group \
    --group-name "${PROJECT}-db-sg" \
    --description "Allow DB traffic only from App SG" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text --region "$REGION")

# Allow MySQL (3306) ONLY from the App SG
aws ec2 authorize-security-group-ingress \
    --group-id "$DB_SG_ID" \
    --protocol tcp --port 3306 \
    --source-group "$APP_SG_ID" \
    --region "$REGION" > /dev/null
echo "✅ DB SG Created: $DB_SG_ID (Port 3306 from App SG)"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo "=================================================="
echo "🎉 Security Groups Setup Complete!"
echo "=================================================="
echo "Web SG:  $WEB_SG_ID (Public HTTP/S)"
echo "App SG:  $APP_SG_ID (Internal Ports: ${APP_PORTS[*]})"
echo "DB SG:   $DB_SG_ID  (Internal DB only)"
echo ""
echo "💡 Next Steps for Bastion/Manual SSH:"
echo "   1. Create a Bastion Host EC2 in your public subnet."
echo "   2. Create an 'Admin SG' manually and attach it to the Bastion."
echo "   3. To access RDS/App servers via Bastion, edit their SGs to allow"
echo "      inbound port 22 ONLY from the Bastion's Security Group ID."