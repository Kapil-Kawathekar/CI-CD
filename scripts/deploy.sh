#!/bin/bash
set -e

# Input arguments
ENVIRONMENT=$1

# Load the GCP project ID
if [[ "$ENVIRONMENT" == "staging" ]]; then
  PROJECT_ID="${STAGING_PROJECT_ID}"
elif [[ "$ENVIRONMENT" == "prod" ]]; then
  PROJECT_ID="${PROD_PROJECT_ID}"
else
  echo "Invalid environment: $ENVIRONMENT"
  exit 1
fi

# Define the image name
IMAGE_NAME="us.gcr.io/$PROJECT_ID/my-app:${ENVIRONMENT}-$(git rev-parse --short HEAD)"
# Authenticate Docker with GCP
echo "Authenticating Docker with GCP..."
gcloud auth configure-docker

echo "Building Docker image for $ENVIRONMENT environment..."
docker build -t "$IMAGE_NAME" .

echo "Pushing Docker image to GCP Container Registry..."
docker push "$IMAGE_NAME"

echo "Docker image successfully pushed: $IMAGE_NAME"
