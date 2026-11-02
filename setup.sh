#!/usr/bin/env bash

# ==============================================================================
# AWS CLI Setup Runbook (Bash Script)
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status

echo "=================================================="
echo "🚀 Starting AWS CLI Setup Runbook"
echo "=================================================="

# ------------------------------------------------------------------------------
# Step 1: Check and Install AWS CLI v2
# ------------------------------------------------------------------------------
echo -e "\n[1/3] Checking AWS CLI installation..."

if command -v aws &> /dev/null; then
    echo "✅ AWS CLI is already installed: $(aws --version)"
else
    echo "⚠️  AWS CLI not found. Installing..."
    
    # Detect OS
    OS_TYPE="$(uname -s)"
    
    if [[ "$OS_TYPE" == "Linux" ]]; then
        echo "📦 Installing for Linux..."
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        sudo ./aws/install
        rm -rf awscliv2.zip aws
    elif [[ "$OS_TYPE" == "Darwin" ]]; then
        echo "📦 Installing for macOS..."
        # Check if Homebrew is installed
        if command -v brew &> /dev/null; then
            brew install awscli
        else
            echo "❌ Homebrew not found. Please install Homebrew or manually download the macOS pkg from AWS."
            exit 1
        fi
    else
        echo "❌ Unsupported OS for automatic script installation: $OS_TYPE"
        echo "Please install AWS CLI manually: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    echo "✅ Installation complete: $(aws --version)"
fi

# ------------------------------------------------------------------------------
# Step 2: Prompt for Credentials
# ------------------------------------------------------------------------------
echo -e "\n[2/3] Credential Configuration"
echo "⚠️  REMINDER: You must generate an Access Key in the AWS Console first!"
echo "   (IAM -> Users -> Security Credentials -> Create Access Key)"
echo ""

# Check if a default profile already exists
if [ -f ~/.aws/credentials ]; then
    echo "⚠️  Existing AWS credentials found at ~/.aws/credentials."
    read -p "Do you want to overwrite the default profile? (y/n): " overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "Skipping configuration. Exiting."
        exit 0
    fi
fi

# Read inputs securely
read -p "Enter your AWS Access Key ID: " aws_access_key
read -s -p "Enter your AWS Secret Access Key: " aws_secret_key
echo ""
read -p "Enter your default region [default: ap-southeast-1]: " aws_region
aws_region=${aws_region:-ap-southeast-1} # Default to Singapore if empty
read -p "Enter output format [default: json]: " aws_output
aws_output=${aws_output:-json}

# ------------------------------------------------------------------------------
# Step 3: Configure the CLI
# ------------------------------------------------------------------------------
echo -e "\n[3/3] Configuring AWS CLI..."

aws configure set aws_access_key_id "$aws_access_key"
aws configure set aws_secret_access_key "$aws_secret_key"
aws configure set region "$aws_region"
aws configure set output "$aws_output"

echo "✅ Configuration saved to ~/.aws/credentials and ~/.aws/config"

# ------------------------------------------------------------------------------
# Step 4: Verify Connection
# ------------------------------------------------------------------------------
echo -e "\n🔍 Verifying connection to AWS..."

if aws sts get-caller-identity &> /dev/null; then
    echo "=================================================="
    echo "🎉 SUCCESS! You are connected to AWS."
    echo "=================================================="
    aws sts get-caller-identity | python3 -m json.tool 2>/dev/null || aws sts get-caller-identity
else
    echo "❌ ERROR: Could not connect to AWS."
    echo "Please check your Access Key, Secret Key, and that the IAM user has 'sts:GetCallerIdentity' permissions."
    exit 1
fi

echo -e "\n👉 Next Step: You can now try deploying your CloudFormation template:"
echo "   aws cloudformation deploy --template-file your-vpc.yaml --stack-name my-vpc-stack"