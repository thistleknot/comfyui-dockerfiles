#!/bin/bash
set -e

echo "=== [1] onnxruntime ==="
echo $LD_LIBRARY_PATH
python3 -c "import onnxruntime; print(onnxruntime.__file__); print(onnxruntime.get_available_providers())"
ls /venv/lib/python3.12/site-packages/onnxruntime/capi/ | grep -i cuda

echo "=== [2] opencv ==="
python3 -c "import cv2; print(cv2.__version__, cv2.__file__)"
python3 -c "from cv2 import ximgproc; print('guidedFilter:', hasattr(ximgproc, 'guidedFilter'))"

echo "=== [3] comfy_env ==="
find /venv -name "comfy_env*" 2>/dev/null
find /default-comfyui-bundle -name "comfy_env*" 2>/dev/null
python3 -c "import comfy_aimdo; print(dir(comfy_aimdo))"

echo "=== [4] fixes ==="
# onnxruntime: reinstall gpu only
pip uninstall -y onnxruntime 2>/dev/null || true
pip install --force-reinstall onnxruntime-gpu
python3 -c "import onnxruntime; print(onnxruntime.get_available_providers())"

# opencv: upgrade to 4.13 which has guidedFilter
pip install --force-reinstall --no-deps opencv-contrib-python
python3 -c "from cv2 import ximgproc; print('guidedFilter:', hasattr(ximgproc, 'guidedFilter'))"

echo "=== [5] verify insightface ==="
python3 -c "from insightface.app.common import Face; print('insightface OK')"

echo "=== done ==="
