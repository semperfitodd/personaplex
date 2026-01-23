#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.env"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at ${CONFIG_FILE}"
  echo "Please create ${CONFIG_FILE} with the following variables:"
  echo "  AWS_ACCOUNT_ID=your-account-id"
  echo "  AWS_REGION=us-east-2"
  echo "  AWS_PROFILE=your-profile (optional)"
  echo "  ENVIRONMENT=personaplex-dev"
  exit 1
fi

source "$CONFIG_FILE"

if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ] || [ -z "$ENVIRONMENT" ]; then
  echo "Error: Missing required variables in ${CONFIG_FILE}"
  echo "Required: AWS_ACCOUNT_ID, AWS_REGION, ENVIRONMENT"
  exit 1
fi

AWS_CLI_OPTS=""
if [ -n "$AWS_PROFILE" ]; then
  AWS_CLI_OPTS="--profile ${AWS_PROFILE}"
  echo "Using AWS Profile: ${AWS_PROFILE}"
fi

TAG=$(date +%Y%m%d%H%M%S)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "=========================================="
echo "Building and pushing images"
echo "Registry: ${ECR_REGISTRY}"
echo "Tag: ${TAG}"
echo "=========================================="

echo "Logging in to ECR..."

ECR_PASSWORD=$(aws ecr get-login-password --region "${AWS_REGION}" ${AWS_CLI_OPTS})
if [ $? -ne 0 ]; then
  echo "Error: Failed to get ECR password"
  exit 1
fi

echo "${ECR_PASSWORD}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}" 2>&1 | grep -v "error saving credentials" | grep -v "WARNING" || true

LOGIN_STATUS=${PIPESTATUS[1]}
if [ $LOGIN_STATUS -eq 0 ]; then
  echo "✓ Successfully logged in to ECR"
else
  echo "⚠ Login completed but credentials may not be saved (this is OK for building/pushing)"
fi

for service_dir in "${SCRIPT_DIR}"/*/ ; do
  if [ ! -d "$service_dir" ]; then
    continue
  fi

  service_name=$(basename "$service_dir")
  
  if [ "$service_name" = "." ] || [ "$service_name" = ".." ]; then
    continue
  fi

  dockerfile="${service_dir}Dockerfile"
  
  if [ ! -f "$dockerfile" ]; then
    echo "Skipping ${service_name} (no Dockerfile found)"
    continue
  fi

  echo ""
  echo "=========================================="
  echo "Building ${service_name}..."
  echo "=========================================="
  
  image_name="${ECR_REGISTRY}/${ENVIRONMENT}/${service_name}"
  
  docker build -t "${image_name}:${TAG}" -t "${image_name}:latest" "$service_dir"
  
  echo ""
  echo "Pushing ${service_name}:${TAG}..."
  docker push "${image_name}:${TAG}"
  
  echo "Pushing ${service_name}:latest..."
  docker push "${image_name}:latest"
  
  echo "✓ ${service_name} pushed successfully"
done

echo ""
echo "=========================================="
echo "All images built and pushed successfully!"
echo "Tag: ${TAG}"
echo "=========================================="
