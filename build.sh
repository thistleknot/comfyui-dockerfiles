set -e

VENV_DIR="${HOME}/comfyui-venv"

# Image names
ML_BASE_IMAGE="ml-base:cu126-pt26"
CUSTOM_NODES_IMAGE="custom-nodes-ready:cu126-pt26"
FINAL_IMAGE="sd-worker:latest"

echo "=== Setting up build environment ==="

mkdir -p "${VENV_DIR}"

echo "=== Building ComfyUI Images (3-Stage) ==="

# Stage 1: Base ML environment (PyTorch + llama-cpp + UV)
echo "[1/4] Building base ML image..."
DOCKER_BUILDKIT=1 docker build \
  -f Dockerfile.base \
  -t "${ML_BASE_IMAGE}" .

# Stage 2: Custom nodes (CACHED unless custom_nodes/ changes)
echo "[2/4] Building custom nodes layer..."
DOCKER_BUILDKIT=1 docker build \
  -f Dockerfile.custom_nodes \
  -t "${CUSTOM_NODES_IMAGE}" .

# Stage 3: ComfyUI latest (ALWAYS REBUILDS for fresh ComfyUI)
echo "[3/4] Building ComfyUI latest (final image)..."
DOCKER_BUILDKIT=1 docker build \
  -f Dockerfile.comfyui \
  -t "${FINAL_IMAGE}" .

# Stage 4: Populate venv (use bash not python to avoid CUDA init)
echo "[4/4] Copying venv to ${VENV_DIR}..."
docker run --rm \
  -v "${VENV_DIR}:/host-venv" \
  --entrypoint bash \
  "${FINAL_IMAGE}" \
  -c "cp -a /venv/. /host-venv/"

echo ""
echo "=== Build Complete ==="
echo "Images:"
echo "  1. ${ML_BASE_IMAGE} (base + PyTorch + llama-cpp)"
echo "  2. ${CUSTOM_NODES_IMAGE} (+ custom nodes CACHED)"
echo "  3. ${FINAL_IMAGE} (+ ComfyUI latest ALWAYS FRESH)"
echo ""
echo "Venv: ${VENV_DIR}"
echo ""
echo "Run:"
echo "docker run -it --rm --gpus all -p 8188:8188 -v ${VENV_DIR}:/venv ${FINAL_IMAGE}"