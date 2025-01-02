#!/bin/bash
set -e

# Input arguments
ENVIRONMENT=$1
BUILD_IMAGE=$2

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
IMAGE_NAME="us.gcr.io/$PROJECT_ID/my-app:${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD)"
# IMAGE_NAME="us.gcr.io/my-kubernetes-project-438008/my-app:staging-3b1c578"

# Check whether to build the image
if [[ "$BUILD_IMAGE" == "yes" ]]; then

  # Authenticate Docker with GCP
  echo "Authenticating Docker with GCP..."
  gcloud auth configure-docker
  
  echo "Building Docker image for $ENVIRONMENT environment..."
  docker build -t "$IMAGE_NAME" .
  
  echo "Pushing Docker image to GCP Container Registry..."
  docker push "$IMAGE_NAME"
  
  echo "Docker image successfully pushed: $IMAGE_NAME"
  
  # Update deployment.yaml file
  DEPLOYMENT_FILE="k8/${ENVIRONMENT}/deploy.yaml"
  
  echo "Updating deployment.yaml with image tag: $IMAGE_NAME"
  # sed -i "s|^\(\s*image:\s*\).*|\1${IMAGE_TAG}|" $DEPLOYMENT_FILE
  # sed -i "s|image: us.gcr.io/$PROJECT_ID/my-app:.*|image: ${IMAGE_NAME}|" "$DEPLOYMENT_FILE"
  sed -i "s|image: us.gcr.io.*my-app:.*|image: ${IMAGE_NAME}|" "$DEPLOYMENT_FILE"
  # sed -i "s|image: *|image: ${IMAGE_TAG}|" "$DEPLOYMENT_FILE"
  
  echo "Updated deployment.yaml file:"
  cat $DEPLOYMENT_FILE
else
  echo "Skipping Docker image build as per user input."
  # If skipping, assume a default or existing image tag
  IMAGE_NAME="us.gcr.io/$PROJECT_ID/my-app:${ENVIRONMENT}-latest"
  echo "Using existing Docker image: $IMAGE_NAME"
fi

# Commit and push the updated file
echo "Setting Git user..."
git config --global user.name "ci-cd-bot"
git config --global user.email "ci-cd-bot@mydomain.com"



# Check if the branch exists
BRANCH_NAME="${ENVIRONMENT}-updates"
if git fetch origin "$BRANCH_NAME" && git rev-parse --verify "origin/$BRANCH_NAME" > /dev/null 2>&1; then
  echo "Branch '$BRANCH_NAME' exists. Checking it out..."
  git checkout "$BRANCH_NAME"
  git pull origin "$BRANCH_NAME"
else
  echo "Branch '$BRANCH_NAME' does not exist. Creating it..."
  git checkout -b "$BRANCH_NAME"
fi

# Commit and push changes if any
if git diff --exit-code $DEPLOYMENT_FILE; then
  echo "No changes detected in deployment.yaml, skipping commit."
else
  git add $DEPLOYMENT_FILE
  git add -u
  git commit -m "Update image tag for $ENVIRONMENT environment to ${IMAGE_NAME}"
  # Push changes and set upstream branch if it doesn't exist
  git push --set-upstream origin "$BRANCH_NAME" || git push
  echo "Changes committed and pushed to branch '$BRANCH_NAME'."
  # echo "Changes committed and pushed to branch"
fi

# Create a simplified Git tag
SHORT_SHA=$(date +%Y%m%d)
TAG_NAME="${ENVIRONMENT}-o11y-${SHORT_SHA}"
echo "Creating Git Tag: $TAG_NAME"

# Push the tag (with --force only if needed)
git tag -f $TAG_NAME
git push origin $TAG_NAME --force

echo "Deployment completed successfully!"
