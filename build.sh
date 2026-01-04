#!/bin/bash
set -e

# Image names
ML_BASE_IMAGE="ml-base:cu126-pt26"
CUSTOM_NODES_IMAGE="custom-nodes-ready:cu126-pt26"
FINAL_IMAGE="sd-worker:latest"
STAGING_IMAGE="sd-worker:staging"

# Parse arguments
FORCE_BASE=false
FORCE_NODES=false
FORCE_ALL=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --force-base) FORCE_BASE=true; shift ;;
    --force-nodes) FORCE_NODES=true; shift ;;
    --force-all) FORCE_ALL=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ "$FORCE_ALL" = true ]; then
  FORCE_BASE=true
  FORCE_NODES=true
fi

# Check if file is newer than image
file_newer_than_image() {
  local file=$1
  local image=$2
  
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi
  
  local image_created=$(docker image inspect "$image" --format='{{.Created}}')
  local image_timestamp=$(date -d "$image_created" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$image_created" +%s 2>/dev/null)
  local file_timestamp=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
  
  if [ "$file_timestamp" -gt "$image_timestamp" ]; then
    return 0
  fi
  return 1
}

# Run compatibility analysis only if repo list changed
RUN_ANALYSIS=false
if [ ! -f "custom_node_repos.txt" ]; then
  echo "=== Running Compatibility Analysis (build list missing) ==="
  RUN_ANALYSIS=true
elif [ "custom_node_repos.txt" -nt "custom_node_repos.txt" ]; then
  echo "=== Running Compatibility Analysis (repo list changed) ==="
  RUN_ANALYSIS=true
else
  echo "=== Skipping Compatibility Analysis (repo list unchanged) ==="
fi

if [ "$RUN_ANALYSIS" = true ]; then
  ./find_compatible_builds.sh custom_nodes custom_node_repos.txt || { echo "Analysis failed"; exit 1; }
  cp build_configs/set-unified.txt custom_node_repos.txt
fi

echo ""
echo "=== Building ComfyUI Images (3-Stage) ==="

# Stage 1: Base ML environment
REBUILD_BASE=false
if [ "$FORCE_BASE" = true ]; then
  echo "[1/3] Rebuilding base (--force-base)"
  REBUILD_BASE=true
elif ! docker image inspect "${ML_BASE_IMAGE}" >/dev/null 2>&1; then
  echo "[1/3] Building base (image missing)"
  REBUILD_BASE=true
elif file_newer_than_image "Dockerfile.base" "${ML_BASE_IMAGE}"; then
  echo "[1/3] Rebuilding base (Dockerfile.base changed)"
  REBUILD_BASE=true
elif [ -f "llama_cpp_python-0.3.18-cp312-cp312-linux_x86_64.whl" ] && \
     file_newer_than_image "llama_cpp_python-0.3.18-cp312-cp312-linux_x86_64.whl" "${ML_BASE_IMAGE}"; then
  echo "[1/3] Rebuilding base (llama wheel changed)"
  REBUILD_BASE=true
else
  echo "[1/3] Skipping base (unchanged since $(docker image inspect ${ML_BASE_IMAGE} --format='{{.Created}}' | cut -d'T' -f1))"
fi

if [ "$REBUILD_BASE" = true ]; then
  DOCKER_BUILDKIT=1 docker build -f Dockerfile.base -t "${ML_BASE_IMAGE}" .
fi

# Stage 2: Custom nodes
REBUILD_NODES=false
if [ "$FORCE_NODES" = true ]; then
  echo "[2/3] Rebuilding custom nodes (--force-nodes)"
  REBUILD_NODES=true
elif ! docker image inspect "${CUSTOM_NODES_IMAGE}" >/dev/null 2>&1; then
  echo "[2/3] Building custom nodes (image missing)"
  REBUILD_NODES=true
elif [ "$REBUILD_BASE" = true ]; then
  echo "[2/3] Rebuilding custom nodes (base layer changed)"
  REBUILD_NODES=true
elif file_newer_than_image "Dockerfile.custom_nodes" "${CUSTOM_NODES_IMAGE}"; then
  echo "[2/3] Rebuilding custom nodes (Dockerfile.custom_nodes changed)"
  REBUILD_NODES=true
elif file_newer_than_image "custom_node_repos.txt" "${CUSTOM_NODES_IMAGE}"; then
  echo "[2/3] Rebuilding custom nodes (repo list changed)"
  REBUILD_NODES=true
else
  echo "[2/3] Skipping custom nodes (unchanged since $(docker image inspect ${CUSTOM_NODES_IMAGE} --format='{{.Created}}' | cut -d'T' -f1))"
fi

if [ "$REBUILD_NODES" = true ]; then
  DOCKER_BUILDKIT=1 docker build \
    -f Dockerfile.custom_nodes \
    --build-arg BASE_IMAGE="${ML_BASE_IMAGE}" \
    -t "${CUSTOM_NODES_IMAGE}" .
fi

# Stage 3: ComfyUI (Blue-Green Deployment)
echo "[3/3] Checking ComfyUI layer..."
REBUILD_COMFY=false

if ! docker image inspect "${FINAL_IMAGE}" >/dev/null 2>&1; then
  echo "  → Building (image missing)"
  REBUILD_COMFY=true
elif [ "$REBUILD_NODES" = true ]; then
  echo "  → Rebuilding (custom nodes changed)"
  REBUILD_COMFY=true
elif file_newer_than_image "Dockerfile.comfyui" "${FINAL_IMAGE}"; then
  echo "  → Rebuilding (Dockerfile.comfyui changed)"
  REBUILD_COMFY=true
elif file_newer_than_image "extra_packages.txt" "${FINAL_IMAGE}"; then
  echo "  → Rebuilding (extra_packages.txt changed)"
  REBUILD_COMFY=true
else
  echo "  → Rebuilding anyway (always fresh)"
  REBUILD_COMFY=true
fi

if [ "$REBUILD_COMFY" = true ]; then
  echo ""
  echo "=== Blue-Green Deployment ==="
  echo "[BUILD] Building staging image: ${STAGING_IMAGE}"
  
  DOCKER_BUILDKIT=1 docker build \
    -f Dockerfile.comfyui \
    --build-arg BASE_IMAGE="${CUSTOM_NODES_IMAGE}" \
    -t "${STAGING_IMAGE}" .
  
  echo "[SWITCH] Swapping images (zero-downtime)..."
  
  # Remove old production image
  if docker image inspect "${FINAL_IMAGE}" >/dev/null 2>&1; then
    echo "  → Removing old production image"
    docker rmi "${FINAL_IMAGE}" 2>/dev/null || true
  fi
  
  # Tag staging as production
  echo "  → Promoting staging → production"
  docker tag "${STAGING_IMAGE}" "${FINAL_IMAGE}"
  
  # Clean up staging tag
  echo "  → Cleaning up staging tag"
  docker rmi "${STAGING_IMAGE}" 2>/dev/null || true
  
  echo "[DONE] Image swapped successfully"
fi

echo ""
echo "=== Build Complete ==="
echo "Images:"
echo "  1. ${ML_BASE_IMAGE} ($(docker image inspect ${ML_BASE_IMAGE} --format='{{.Created}}' | cut -d'T' -f1))"
echo "  2. ${CUSTOM_NODES_IMAGE} ($(docker image inspect ${CUSTOM_NODES_IMAGE} --format='{{.Created}}' | cut -d'T' -f1))"
echo "  3. ${FINAL_IMAGE} ($(docker image inspect ${FINAL_IMAGE} --format='{{.Created}}' | cut -d'T' -f1))"
echo ""
echo "Current image in use: ${FINAL_IMAGE}"