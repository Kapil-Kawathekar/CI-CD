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

# Define the repository path in Artifact Registry (not Container Registry)
REPOSITORY="us-docker.pkg.dev/$PROJECT_ID/my-app"

# Check whether to build the image
if [[ "$BUILD_IMAGE" == "yes" ]]; then
  IMAGE_NAME="${REPOSITORY}:${SOURCE_BRANCH}-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD)"

  echo "Authenticating Docker with Artifact Registry..."
  gcloud auth configure-docker us-docker.pkg.dev

  echo "Building Docker image for $ENVIRONMENT environment..."
  docker build -t "$IMAGE_NAME" .

  echo "Pushing Docker image to Artifact Registry..."
  docker push "$IMAGE_NAME"

  echo "Docker image successfully pushed: $IMAGE_NAME"
else
  echo "Skipping Docker image build as per user input."
fi

if [[ "$DEPLOY_TO_K8S" == "yes" ]]; then
  DEPLOYMENT_FILE="k8/${ENVIRONMENT}/deploy.yaml"

  if [[ "$BUILD_IMAGE" == "yes" ]]; then
    echo "Setting Git user..."
    git config --global user.name "ci-cd-bot"
    git config --global user.email "ci-cd-bot@mydomain.com"

    echo "Updating deployment.yaml with image tag: $IMAGE_NAME"
    sed -i "s|image: us-docker.pkg.dev.*my-app:.*|image: ${IMAGE_NAME}|" "$DEPLOYMENT_FILE"

    echo "Updated deployment.yaml file:"
    cat $DEPLOYMENT_FILE

    if git diff --exit-code $DEPLOYMENT_FILE; then
      echo "No changes detected in deployment.yaml, skipping commit."
    else
      git add $DEPLOYMENT_FILE
      git commit -m "Update/Reuse the image"
    fi
    git pull origin ${SOURCE_BRANCH}
    git push origin ${SOURCE_BRANCH}
    echo "Changes committed and pushed to branch ${SOURCE_BRANCH}."
  else
    echo "Reusing the same image"

    if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
      echo "Error: $DEPLOYMENT_FILE does not exist!"
      exit 1
    fi

    EXISTING_IMAGE=$(grep -oP 'image:\s*\Kus-docker\.pkg\.dev/[^ ]+' "$DEPLOYMENT_FILE")

    if [[ -z "$EXISTING_IMAGE" ]]; then
      echo "Error: No image found in $DEPLOYMENT_FILE!"
      exit 1
    fi

    echo "Checking if the image $EXISTING_IMAGE exists in $REPOSITORY"

    if ! gcloud artifacts docker images list "$REPOSITORY" \
       --format="get(name)" | grep -q "$(basename "$EXISTING_IMAGE")"; then
      echo "Error: image $EXISTING_IMAGE not found in $REPOSITORY"
      exit 1
    fi

    echo "Image $EXISTING_IMAGE present"
  fi

  TAG_NAME="o11y-${SOURCE_BRANCH}"
  echo "Creating Git Tag: $TAG_NAME"
  git tag -f $TAG_NAME
  git push origin $TAG_NAME
  echo "Deployment completed successfully!"
else
  echo "Skipping deployment"
fi
