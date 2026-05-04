#!/bin/bash
set -euo pipefail

# Podedge S3 Hosting Setup
# Creates an S3 bucket, CloudFront distribution with OAC, and a least-privilege IAM user.
# Requires: AWS CLI v2 (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

bold=$(tput bold)
reset=$(tput sgr0)
green=$(tput setaf 2)
yellow=$(tput setaf 3)

echo "${bold}Podedge S3 Hosting Setup${reset}"
echo "This script creates everything you need to host your podcast on AWS."
echo ""

# --- Gather inputs ---

read -rp "Bucket name (lowercase, globally unique, e.g. my-podcast-media): " BUCKET
read -rp "AWS region (e.g. us-east-1): " REGION
IAM_USER="podedge-${BUCKET}"

echo ""
echo "This will create:"
echo "  • S3 bucket:            ${bold}${BUCKET}${reset} (private, in ${REGION})"
echo "  • CloudFront distribution with OAC"
echo "  • IAM user:             ${bold}${IAM_USER}${reset} (least-privilege)"
echo ""
read -rp "Continue? (y/N) " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# --- Step 1: Create S3 bucket (private) ---

echo ""
echo "${bold}Step 1/5: Creating S3 bucket...${reset}"
if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
fi
echo "${green}✓${reset} Bucket ${BUCKET} created (Block Public Access ON by default)"

# --- Step 2: Create CloudFront OAC ---

echo ""
echo "${bold}Step 2/5: Creating CloudFront Origin Access Control...${reset}"
OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config \
        "Name=podedge-oac-${BUCKET},Description=Podedge OAC for ${BUCKET},SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
    --query 'OriginAccessControl.Id' --output text)
echo "${green}✓${reset} OAC created: ${OAC_ID}"

# --- Step 3: Create CloudFront distribution ---

echo ""
echo "${bold}Step 3/5: Creating CloudFront distribution...${reset}"
DIST_CONFIG=$(cat <<EOF
{
    "CallerReference": "podedge-${BUCKET}-$(date +%s)",
    "Comment": "Podedge podcast hosting for ${BUCKET}",
    "Enabled": true,
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-${BUCKET}",
                "DomainName": "${BUCKET}.s3.${REGION}.amazonaws.com",
                "S3OriginConfig": { "OriginAccessIdentity": "" },
                "OriginAccessControlId": "${OAC_ID}"
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-${BUCKET}",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] },
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "Compress": true
    }
}
EOF
)
DIST_RESULT=$(aws cloudfront create-distribution --distribution-config "$DIST_CONFIG" \
    --query '{Id: Distribution.Id, Domain: Distribution.DomainName}' --output json)
DIST_ID=$(echo "$DIST_RESULT" | grep -o '"Id": "[^"]*"' | cut -d'"' -f4)
DIST_DOMAIN=$(echo "$DIST_RESULT" | grep -o '"Domain": "[^"]*"' | cut -d'"' -f4)
echo "${green}✓${reset} Distribution created: ${DIST_ID}"
echo "  Domain: https://${DIST_DOMAIN}"

# --- Step 4: Set bucket policy for CloudFront OAC ---

echo ""
echo "${bold}Step 4/5: Setting bucket policy (CloudFront OAC only)...${reset}"
BUCKET_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": { "Service": "cloudfront.amazonaws.com" },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}"
                }
            }
        }
    ]
}
EOF
)
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$BUCKET_POLICY"
echo "${green}✓${reset} Bucket policy set (only distribution ${DIST_ID} can read)"

# --- Step 5: Create IAM user with least-privilege policy ---

echo ""
echo "${bold}Step 5/5: Creating IAM user...${reset}"
aws iam create-user --user-name "$IAM_USER" > /dev/null

IAM_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PodedgePublish",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}",
                "arn:aws:s3:::${BUCKET}/*"
            ]
        }
    ]
}
EOF
)
aws iam put-user-policy --user-name "$IAM_USER" --policy-name PodedgePublishPolicy --policy-document "$IAM_POLICY"

KEY_RESULT=$(aws iam create-access-key --user-name "$IAM_USER" \
    --query 'AccessKey.{AccessKeyId: AccessKeyId, SecretAccessKey: SecretAccessKey}' --output json)
ACCESS_KEY_ID=$(echo "$KEY_RESULT" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
SECRET_KEY=$(echo "$KEY_RESULT" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
echo "${green}✓${reset} IAM user ${IAM_USER} created with least-privilege policy"

# --- Summary ---

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "${bold}${green}Setup complete!${reset} Enter these values in Podedge (Settings → Hosts → Add Host):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Bucket:            ${bold}${BUCKET}${reset}"
echo "  Region:            ${bold}${REGION}${reset}"
echo "  Public Base URL:   ${bold}https://${DIST_DOMAIN}${reset}"
echo "  Access Key ID:     ${bold}${ACCESS_KEY_ID}${reset}"
echo "  Secret Access Key: ${bold}${SECRET_KEY}${reset}"
echo ""
echo "${yellow}⚠  Save the Secret Access Key now — it cannot be retrieved again.${reset}"
echo ""
echo "CloudFront may take 5–10 minutes to fully deploy."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
