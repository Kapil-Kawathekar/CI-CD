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
# IMAGE_NAME="us.gcr.io/$PROJECT_ID/my-app:${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD)"
# IMAGE_NAME="us.gcr.io/my-kubernetes-project-438008/my-app:staging-3b1c578"

# Check whether to build the image
if [[ "$BUILD_IMAGE" == "yes" ]]; then
  IMAGE_NAME="us.gcr.io/$PROJECT_ID/my-app:${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD)"
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
  
  BASE_IMAGE="us.gcr.io/$PROJECT_ID/my-app"
  echo "Fetching the latest image tag..."
  LATEST_TAG=$(gcloud container images list-tags $BASE_IMAGE\
    --sort-by="~timestamp" --limit=1 --format="get(tags)")
  
  if [ -z "$LATEST_TAG" ]; then
    echo "No image tags found in GCR. Exiting."
    exit 1
  fi
  
  echo "Latest tag: $LATEST_TAG"
  # If skipping, assume a default or existing image tag
  IMAGE_NAME="$BASE_IMAGE:$LATEST_TAG # Resuing the latest images present in the GCP Image registry"
  echo "Using existing Docker image: $IMAGE_NAME"
fi

# Update deployment.yaml file
DEPLOYMENT_FILE="k8/${ENVIRONMENT}/deploy.yaml"

echo "Updating deployment.yaml with image tag: $IMAGE_NAME"
# sed -i "s|^\(\s*image:\s*\).*|\1${IMAGE_TAG}|" $DEPLOYMENT_FILE
# sed -i "s|image: us.gcr.io/$PROJECT_ID/my-app:.*|image: ${IMAGE_NAME}|" "$DEPLOYMENT_FILE"
sed -i "s|image: us.gcr.io.*my-app:.*|image: ${IMAGE_NAME}|" "$DEPLOYMENT_FILE"
# sed -i "s|image: *|image: ${IMAGE_TAG}|" "$DEPLOYMENT_FILE"

echo "Updated deployment.yaml file:"
cat $DEPLOYMENT_FILE

# Commit and push the updated file
echo "Setting Git user..."
git config --global user.name "ci-cd-bot"
git config --global user.email "ci-cd-bot@mydomain.com"



# Check if the branch exists
BRANCH_NAME="${ENVIRONMENT}-$(date +%Y%m%d)"
SOURCE_BRANCH=${GITHUB_REF#refs/heads/}
git fetch origin
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Local changes detected. Stashing them..."
  git stash
  STASH_APPLIED=true
else
  STASH_APPLIED=false
fi

if git fetch origin "$BRANCH_NAME" && git rev-parse --verify "origin/$BRANCH_NAME" > /dev/null 2>&1; then
  echo "Branch '$BRANCH_NAME' exists. Checking it out..."
  # Stash changes if any
  git checkout "$BRANCH_NAME"
  # git branch -D "$BRANCH_NAME" || true
  git pull origin "$BRANCH_NAME"

  # Optionally reapply stashed changes
  if [ "$STASH_APPLIED" = true ]; then
    echo "Reapplying stashed changes..."
    git stash pop || {
      echo "Conflicts detected. Resolving automatically using 'ours' strategy..."
      # Resolve all conflicts with 'ours'
      for file in $(git diff --name-only --diff-filter=U); do
        git checkout --ours "$file"
        git add "$file"
      done
      git stash drop
    }
  fi
else
  echo "Branch '$BRANCH_NAME' does not exist. Creating it..."
  git checkout -b "$BRANCH_NAME"
  git push --set-upstream origin "$BRANCH_NAME" || git push
fi

# echo "Branch '$BRANCH_NAME' does not exist/ deleted. Creating it..."
# git checkout -b "$BRANCH_NAME"

echo "Merging changes from '$SOURCE_BRANCH into '$BRANCH_NAME''"
git merge origin/"$SOURCE_BRANCH" --no-ff -m "Merge updates from '$SOURCE_BRANCH' into '$BRANCH_NAME'"

if [$? -ne 0]; then
  echo "Merge conflicts detected. Please check the source branch '$SOURCE_BRANCH' and target branch '$BRANCH_NAME'"
  exit 1
fi

git config core.fileMode false
# Commit and push changes if any
if git diff --exit-code $DEPLOYMENT_FILE; then
  echo "No changes detected in deployment.yaml, skipping commit."
else
  git add $DEPLOYMENT_FILE
  git add -u
  git commit -m "Update image tag for $ENVIRONMENT environment to ${IMAGE_NAME}"
  # Push changes and set upstream branch if it doesn't exist
 
  echo "Changes committed to branch '$BRANCH_NAME'."
  # echo "Changes committed and pushed to branch"
fi

git push --set-upstream origin "$BRANCH_NAME" || git push
echo "Changes committed and pushed to branch '$BRANCH_NAME'."
# Create a simplified Git tag
SHORT_SHA=$(date +%Y%m%d)
TAG_NAME="${ENVIRONMENT}-o11y-${SHORT_SHA}"
echo "Creating Git Tag: $TAG_NAME"

# Push the tag (with --force only if needed)
git tag -f $TAG_NAME
git push origin $TAG_NAME --force

echo "Deployment completed successfully!"
