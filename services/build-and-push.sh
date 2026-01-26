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

export HF_TOKEN

AWS_CLI_OPTS=""
if [ -n "$AWS_PROFILE" ]; then
  AWS_CLI_OPTS="--profile ${AWS_PROFILE}"
  echo "Using AWS Profile: ${AWS_PROFILE}"
fi

TAG=$(date +%Y%m%d%H%M%S)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
VALUES_FILE="${SCRIPT_DIR}/../k8s/microservices/values.yaml"

echo "=========================================="
echo "Building and pushing images"
echo "Registry: ${ECR_REGISTRY}"
echo "Tag: ${TAG}"
echo "=========================================="

echo "Setting up Docker buildx..."
docker buildx create --use --name multiarch-builder --driver docker-container 2>/dev/null || docker buildx use multiarch-builder || true
docker buildx inspect --bootstrap

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
  echo "Building ${service_name} for linux/amd64..."
  echo "=========================================="
  
  image_name="${ECR_REGISTRY}/${ENVIRONMENT}/${service_name}"
  
  BUILD_ARGS=""
  if [ "$service_name" = "personaplex" ] && [ -n "$HF_TOKEN" ]; then
    BUILD_ARGS="--secret id=hf_token,env=HF_TOKEN"
  fi
  
  docker buildx build \
    --platform linux/amd64 \
    --tag "${image_name}:${TAG}" \
    --push \
    ${BUILD_ARGS} \
    "$service_dir"
  
  echo "✓ ${service_name} built and pushed successfully"
  
  if [ -f "$VALUES_FILE" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "/^  ${service_name}:/,/^  [a-z]/ s/tag: '[^']*'/tag: '${TAG}'/" "$VALUES_FILE"
    else
      sed -i "/^  ${service_name}:/,/^  [a-z]/ s/tag: '[^']*'/tag: '${TAG}'/" "$VALUES_FILE"
    fi
    echo "✓ Updated ${service_name} tag in values.yaml"
  fi
done

echo ""
echo "=========================================="
echo "All images built and pushed successfully!"
echo "Tag: ${TAG}"
echo "=========================================="
echo ""
echo "Updated tags in ${VALUES_FILE}"
