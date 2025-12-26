# ComfyUI Dockerfiles

Optimized Docker configurations for ComfyUI with advanced pip caching and layer management for faster builds.

## Features

- **Pip Cache Mounting**: Uses BuildKit cache mounts to persist pip cache between builds
- **Optimized Layer Caching**: Separates requirements installation from application code
- **Multi-stage Builds**: Reduces final image size while maintaining fast builds
- **Docker Compose Support**: Easy deployment with docker-compose

## Build Optimization Techniques

### 1. Pip Cache Mounting
The Dockerfiles use BuildKit's `--mount=type=cache` feature to persist pip's cache directory between builds:

```dockerfile
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

This significantly speeds up rebuilds when dependencies haven't changed.

### 2. Layer Caching Strategy
Requirements are copied and installed before the application code:

```dockerfile
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
COPY . /app
```

This ensures pip install layer is cached and only rebuilds when requirements.txt changes.

### 3. Multi-stage Builds
`Dockerfile.multistage` uses multiple stages to separate build dependencies from runtime:

- **Builder stage**: Installs all dependencies
- **Runtime stage**: Copies only necessary files, resulting in smaller images

## Quick Start

### Prerequisites
- Docker 18.09+ (for BuildKit support)
- Docker Compose (optional)

### Using Standard Dockerfile

Enable BuildKit and build:

```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Build the image
docker build -t comfyui:latest .

# Run the container
docker run -p 8188:8188 comfyui:latest
```

### Using Multi-stage Dockerfile

```bash
export DOCKER_BUILDKIT=1
docker build -f Dockerfile.multistage -t comfyui:multistage .
docker run -p 8188:8188 comfyui:multistage
```

### Using Docker Compose

```bash
# Build and start (BuildKit enabled by default in recent versions)
docker compose build
docker compose up -d

# Or in one command
docker compose up -d --build
```

## Customization

### Adding Custom Dependencies

Edit `requirements.txt` to add your custom Python packages:

```txt
opencv-python>=4.7.0
scikit-image>=0.20.0
transformers>=4.30.0
```

The layered approach ensures that only the pip install layer rebuilds when you modify requirements.

### Adding Custom Nodes

Place your custom nodes in the repository directory. They will be copied to `/app/custom` in the container.

### Volume Mounts

The docker-compose.yml includes volume mounts for:
- `models/`: Model files (persistent)
- `output/`: Generated outputs
- `input/`: Input files

## Performance Comparison

### Without Caching
- First build: ~5-10 minutes
- Rebuild after code change: ~5-10 minutes (reinstalls everything)

### With Pip Caching & Layering
- First build: ~5-10 minutes
- Rebuild after code change: ~30 seconds (reuses cached layers)
- Rebuild after requirements change: ~2-3 minutes (reuses pip cache)

## Build Arguments

You can customize builds with arguments:

```bash
docker build --build-arg PYTHON_VERSION=3.10 -t comfyui:py310 .
```

## Troubleshooting

### BuildKit not enabled
If you see errors about `--mount=type=cache`, ensure BuildKit is enabled:

```bash
export DOCKER_BUILDKIT=1
# Or add to ~/.bashrc or ~/.zshrc
```

For docker-compose, use version 1.25.0+, which has BuildKit enabled by default.

### Cache not working
Verify BuildKit is active by checking for cache mount messages in build output:

```
#8 [3/5] RUN --mount=type=cache,target=/root/.cache/pip ...
```

## Files

- `Dockerfile`: Standard optimized build with pip caching
- `Dockerfile.multistage`: Multi-stage build for smaller final images
- `docker-compose.yml`: Docker Compose configuration
- `requirements.txt`: Example Python dependencies
- `.dockerignore`: Excludes unnecessary files from build context

## Contributing

When adding custom dependencies:
1. Update `requirements.txt`
2. Test the build with caching
3. Ensure the layer structure is preserved

## License

This repository provides Docker configurations for ComfyUI. Please refer to the [ComfyUI repository](https://github.com/comfyanonymous/ComfyUI) for ComfyUI licensing.
