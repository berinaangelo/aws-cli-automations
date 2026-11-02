#!/usr/bin/env bash

# ==============================================================================
# AWS WAF Setup Runbook (Full Ruleset with CloudFront Verification)
# ==============================================================================
set -euo pipefail

# Configuration
REGION="${1:-ap-southeast-1}"
ACL_NAME="angelo-web-acl"
RULES_FILE="waf-rules.json"

echo "=================================================="
echo "🛡️  AWS WAF Setup for ALB in $REGION"
echo "=================================================="

# ------------------------------------------------------------------------------
# Step 1: Create the JSON Rules File
# ------------------------------------------------------------------------------
echo "📝 Creating WAF rules file ($RULES_FILE)..."
cat << 'EOF' > "$RULES_FILE"
[
  {
    "Name": "Check-CloudFront-Origin",
    "Priority": 0,
    "Statement": {
      "NotStatement": {
        "Statement": {
          "ByteMatchStatement": {
            "FieldToMatch": { "SingleHeader": { "Name": "x-origin-verify" } },
            "PositionalConstraint": "EXACTLY",
            "SearchString": "my-super-secret-string-12345",
            "TextTransformations": [{ "Priority": 0, "Type": "LOWERCASE" }]
          }
        }
      }
    },
    "Action": { "Count": {} },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "CheckNonCloudFront"
    }
  },
  {
    "Name": "AWS-AWSManagedRulesAmazonIpReputationList",
    "Priority": 1,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesAmazonIpReputationList"
      }
    },
    "OverrideAction": { "Count": {} },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "AmazonIpReputationList"
    }
  },
  {
    "Name": "AWS-AWSManagedRulesCommonRuleSet",
    "Priority": 2,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesCommonRuleSet"
      }
    },
    "OverrideAction": { "None": {} },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "CommonRuleSet"
    }
  },
  {
    "Name": "AWS-AWSManagedRulesSQLiRuleSet",
    "Priority": 3,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesSQLiRuleSet"
      }
    },
    "OverrideAction": { "None": {} },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "SQLiRuleSet"
    }
  },
  {
    "Name": "AWS-AWSManagedRulesKnownBadInputsRuleSet",
    "Priority": 4,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesKnownBadInputsRuleSet"
      }
    },
    "OverrideAction": { "None": {} },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "KnownBadInputs"
    }
  },
  {
    "Name": "AWS-AWSManagedRulesATPRuleSet",
    "Priority": 5,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesATPRuleSet",
        "ManagedRuleGroupConfigs": [
          {
            "AWSManagedRulesATPRuleSet": {
              "LoginPath": "/api/login",
              "RequestInspection": {
                "PayloadType": "JSON",
                "UsernameField": { "Identifier": "/username" },
                "PasswordField": { "Identifier": "/password" }
              }
            }
          }
        ]
      }
    },
    "OverrideAction": { "Count": {} },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "ATPRuleSet"
    }
  },
  {
    "Name": "AWS-AWSManagedRulesAntiDDoSRuleSet",
    "Priority": 6,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesAntiDDoSRuleSet",
        "ManagedRuleGroupConfigs": [
          {
            "AWSManagedRulesAntiDDoSRuleSet": {
              "SensitivityToBlock": "LOW",
              "ClientSideActionConfig": {
                "UsageOfAction": "ENABLED",
                "Sensitivity": "LOW",
                "ExemptUriRegularExpressions": [
                  {
                    "RegexString": "\\/api(\\/|$)|\\.(acc|avi|css|gif|jpe?g|js|mp[34]|ogg|otf|pdf|png|tiff?|ttf|webm|webp|woff2?)$"
                  }
                ]
              }
            }
          }
        ]
      }
    },
    "OverrideAction": { "Count": {} },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "AntiDDoSRuleSet"
    }
  },
  {
    "Name": "RateLimit-Login",
    "Priority": 7,
    "Statement": {
      "RateBasedStatement": {
        "Limit": 500,
        "AggregateKeyType": "IP",
        "ScopeDownStatement": {
          "ByteMatchStatement": {
            "FieldToMatch": { "UriPath": {} },
            "PositionalConstraint": "STARTS_WITH",
            "SearchString": "/login",
            "TextTransformations": [{ "Priority": 0, "Type": "LOWERCASE" }]
          }
        }
      }
    },
    "Action": { "Block": {} },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "RateLimitLogin"
    }
  }
]
EOF
echo "✅ Rules file created."

# ------------------------------------------------------------------------------
# Step 2: Create the Web ACL
# ------------------------------------------------------------------------------
echo -e "\n[1/2] Creating Web ACL ($ACL_NAME)..."

# Check if it already exists to avoid errors
if aws wafv2 list-web-acls --scope REGIONAL --region "$REGION" --query "WebACLs[?Name=='$ACL_NAME'].Id" --output text | grep -q .; then
    echo "⚠️  Web ACL '$ACL_NAME' already exists. Skipping creation."
    ACL_ARN=$(aws wafv2 list-web-acls --scope REGIONAL --region "$REGION" --query "WebACLs[?Name=='$ACL_NAME'].ARN" --output text)
else
    ACL_ARN=$(aws wafv2 create-web-acl \
        --name "$ACL_NAME" \
        --scope REGIONAL \
        --default-action Allow={} \
        --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=angelo-web-acl \
        --rules file://"$RULES_FILE" \
        --query 'Summary.ARN' \
        --output text \
        --region "$REGION")
    echo "✅ Web ACL Created: $ACL_ARN"
fi

# ------------------------------------------------------------------------------
# Step 3: Associate with ALB
# ------------------------------------------------------------------------------
echo -e "\n[2/2] Associating Web ACL with ALB..."
read -p "Enter your ALB ARN (or leave blank to skip): " ALB_ARN

if [ -z "$ALB_ARN" ]; then
    echo "⏭️  Skipping association. You can associate it manually later."
else
    # Check if it's already associated
    if aws wafv2 list-resources-for-web-acl --web-acl-arn "$ACL_ARN" --region "$REGION" --query "ResourceArns" --output text | grep -q "$ALB_ARN"; then
        echo "⚠️  ALB is already associated with this Web ACL."
    else
        aws wafv2 associate-web-acl \
            --web-acl-arn "$ACL_ARN" \
            --resource-arn "$ALB_ARN" \
            --region "$REGION"
        echo "✅ Successfully associated Web ACL with ALB."
    fi
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo "=================================================="
echo "🎉 WAF Setup Complete!"
echo "=================================================="
echo "Web ACL ARN: $ACL_ARN"
echo "Rules applied (priorities 0-7):"
echo "  - CloudFront Origin Verification (Count)"
echo "  - Amazon IP Reputation List (Count)"
echo "  - AWS Managed Common Rule Set (Block)"
echo "  - AWS Managed SQLi Rule Set (Block)"
echo "  - AWS Managed Known Bad Inputs (Block)"
echo "  - AWS Managed ATP Rule Set (Count)"
echo "  - AWS Managed Anti-DDoS Rule Set (Count)"
echo "  - Rate Limit on /login (500 req / 5 min per IP)"
echo ""
echo "⚠️  REMINDER: WAF has a base cost, and ATP/Anti-DDoS are paid rule groups."
echo "   Monitor your billing and switch Count rules to Block/None only after testing."
echo ""
echo "🧹 Cleanup commands (when you are done):"
echo "   aws wafv2 disassociate-web-acl --resource-arn <ALB_ARN> --region $REGION"
echo "   aws wafv2 delete-web-acl --name $ACL_NAME --scope REGIONAL --id <ACL_ID> --lock-token <LOCK_TOKEN> --region $REGION"