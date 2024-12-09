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

# Update deployment.yaml file
DEPLOYMENT_FILE="k8/deploy.yaml"

echo "Updating deployment.yaml with image tag: $IMAGE_TAG"
sed -i "s|^\(\s*image:\s*\).*|\1${IMAGE_TAG}|" "$DEPLOYMENT_FILE"
# sed -i "s|image: us.gcr.io/$PROJECT_ID/my-app:.*|image: ${IMAGE_TAG}|" "$DEPLOYMENT_FILE"
# sed -i "s|image: us.gcr.io.*my-app:.*|image: ${IMAGE_TAG}|" "$DEPLOYMENT_FILE"
# sed -i "s|image: *|image: ${IMAGE_TAG}|" "$DEPLOYMENT_FILE"

echo "Updated deployment.yaml file:"
cat $DEPLOYMENT_FILE

# Commit and push the updated file
echo "Setting Git user..."
git config --global user.name "ci-cd-bot"
git config --global user.email "ci-cd-bot@mydomain.com"

# Commit and push changes if any
if git diff --exit-code $DEPLOYMENT_FILE; then
  echo "No changes detected in deployment.yaml, skipping commit."
else
  git add $DEPLOYMENT_FILE
  git commit -m "Update image tag for $ENVIRONMENT environment to ${IMAGE_TAG}"
  git push origin "$BRANCH"
  echo "Changes committed and pushed to branch $BRANCH"
fi
