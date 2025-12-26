#!/bin/bash
# Build script demonstrating pip cache and layer optimization

set -e

echo "==================================="
echo "ComfyUI Docker Build with Caching"
echo "==================================="

# Enable BuildKit for cache mount support
export DOCKER_BUILDKIT=1

# Parse command line arguments
DOCKERFILE="Dockerfile"
IMAGE_TAG="comfyui:latest"

while [[ $# -gt 0 ]]; do
  case $1 in
    --multistage)
      DOCKERFILE="Dockerfile.multistage"
      IMAGE_TAG="comfyui:multistage"
      shift
      ;;
    --tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE="--no-cache"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--multistage] [--tag IMAGE_TAG] [--no-cache]"
      exit 1
      ;;
  esac
done

echo "Building with:"
echo "  Dockerfile: $DOCKERFILE"
echo "  Image tag: $IMAGE_TAG"
echo "  BuildKit: enabled"
echo ""

# Build the image
echo "Starting build..."
docker build $NO_CACHE -f "$DOCKERFILE" -t "$IMAGE_TAG" .

echo ""
echo "==================================="
echo "Build completed successfully!"
echo "==================================="
echo ""
echo "To run the container:"
echo "  docker run -p 8188:8188 $IMAGE_TAG"
echo ""
echo "To run with docker-compose:"
echo "  docker compose up -d"
