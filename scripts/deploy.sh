#!/bin/bash
set -e

# Input arguments
ENVIRONMENT=$1
BUILD_IMAGE=$2
DEPLOY_TO_K8S=$3

SOURCE_BRANCH=${GITHUB_REF#refs/heads/}
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
# IMAGE_NAME="us.gcr.io/$PROJECT_ID/my-app:${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD)"
# IMAGE_NAME="us.gcr.io/my-kubernetes-project-438008/my-app:staging-3b1c578"

# Check whether to build the image
if [[ "$BUILD_IMAGE" == "yes" ]]; then
  IMAGE_NAME="us.gcr.io/$PROJECT_ID/my-app:${SOURCE_BRANCH}-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD)"
  # Authenticate Docker with GCP
  echo "Authenticating Docker with GCP..."
  gcloud auth configure-docker
  
  echo "Building Docker image for $ENVIRONMENT environment..."
  docker build -t "$IMAGE_NAME" .
  
  echo "Pushing Docker image to GCP Container Registry..."
  docker push "$IMAGE_NAME"
  
  echo "Docker image successfully pushed: $IMAGE_NAME"

else
  echo "Skipping Docker image build as per user input."

fi

if [[ "$DEPLOY_TO_K8S" == "yes" ]]; then
  if [[ "$BUILD_IMAGE" == "yes" ]]; then

    # Commit and push the updated file
    echo "Setting Git user..."
    git config --global user.name "ci-cd-bot"
    git config --global user.email "ci-cd-bot@mydomain.com"
    # Update deployment.yaml file
    DEPLOYMENT_FILE="k8/${ENVIRONMENT}/deploy.yaml"
    
    echo "Updating deployment.yaml with image tag: $IMAGE_NAME"
    # sed -i "s|^\(\s*image:\s*\).*|\1${IMAGE_TAG}|" $DEPLOYMENT_FILE
    # sed -i "s|image: us.gcr.io/$PROJECT_ID/my-app:.*|image: ${IMAGE_NAME}|" "$DEPLOYMENT_FILE"
    sed -i "s|image: us.gcr.io.*my-app:.*|image: ${IMAGE_NAME}|" "$DEPLOYMENT_FILE"
    # sed -i "s|image: *|image: ${IMAGE_TAG}|" "$DEPLOYMENT_FILE"
    
    echo "Updated deployment.yaml file:"
    cat $DEPLOYMENT_FILE
    
    # Commit and push changes if any
    if git diff --exit-code $DEPLOYMENT_FILE; then
      echo "No changes detected in deployment.yaml, skipping commit."
    else
      git add $DEPLOYMENT_FILE
      # git add -u
      git commit -m "Update/Reuse the image"
      # Push changes and set upstream branch if it doesn't exist
     
      echo "Changes committed to branch ${SOURCE_BRANCH}."
      # echo "Changes committed and pushed to branch"
    fi
    git pull origin ${SOURCE_BRANCH}
    git push origin ${SOURCE_BRANCH}
    echo "Changes committed and pushed to branch ${SOURCE_BRANCH}."
  else
    echo "resuing the same image"
    EXISTING_IMAGE = $(grep -oP 'image:\s*\Kus.gcr.io/[^ ]+' "$DEPLOYMENT_FILE")

    if [[-z "$EXISTING_IMAGE"]]; then
      echo "Error : No image found in patch-containers.yaml !"
      exit 1
    fi

    echo "Checking if the image $EXISTING_IMAGE exists in artifact registry"
    if !gcloud artifacts docker image list --repositories="us.gcr.io/$PROJECT_ID/my-app" \
       --format="get(name)" | grep -q "$EXISTING_IMAGE"; then
      echo "Error image: $EXISTING_IMAGE not found"
      exit 1
    fi
  # Create a simplified Git tag
  # SHORT_SHA=$(date +%Y%m%d)
  TAG_NAME="o11y-${SOURCE_BRANCH}"
  echo "Creating Git Tag: $TAG_NAME"
  
  # Push the tag (with --force only if needed)
  git tag -f $TAG_NAME
  git push origin $TAG_NAME
  echo "Deployment completed successfully!"
fi
