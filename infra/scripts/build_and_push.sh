#!/usr/bin/env bash
#
# Build the transform-data Lambda image and push it to ECR.
#
# Invoked by Terraform (infra/lambda.tf) with these environment variables:
#   AWS_REGION, ACCOUNT_ID, REPOSITORY_URL, IMAGE_TAG, BUILD_CONTEXT, PLATFORM
#
# Can also be run by hand:
#   AWS_REGION=us-east-2 ACCOUNT_ID=... REPOSITORY_URL=... IMAGE_TAG=dev \
#   BUILD_CONTEXT=../app PLATFORM=linux/arm64 ./build_and_push.sh

set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${ACCOUNT_ID:?ACCOUNT_ID is required}"
: "${REPOSITORY_URL:?REPOSITORY_URL is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${BUILD_CONTEXT:?BUILD_CONTEXT is required}"
: "${PLATFORM:?PLATFORM is required}"

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPOSITORY_NAME="${REPOSITORY_URL##*/}"
IMAGE="${REPOSITORY_URL}:${IMAGE_TAG}"

for cmd in docker aws; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: '$cmd' is not installed or not on PATH" >&2
    exit 1
  fi
done

# The repository is immutable, so pushing an existing tag would fail. The tag
# is a hash of the source, so an existing tag means this image is already there.
if aws ecr describe-images \
      --region "$AWS_REGION" \
      --repository-name "$REPOSITORY_NAME" \
      --image-ids "imageTag=${IMAGE_TAG}" \
      >/dev/null 2>&1; then
  echo "==> ${IMAGE} already exists in ECR, skipping build"
  exit 0
fi

echo "==> Logging in to ${REGISTRY}"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Building ${IMAGE} for ${PLATFORM}"
docker buildx build \
  --platform "$PLATFORM" \
  --provenance=false \
  --tag "$IMAGE" \
  --file "${BUILD_CONTEXT}/Dockerfile" \
  --push \
  "$BUILD_CONTEXT"

echo "==> Pushed ${IMAGE}"
