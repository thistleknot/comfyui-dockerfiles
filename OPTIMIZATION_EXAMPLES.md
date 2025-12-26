# Cache Optimization Examples

This document demonstrates the pip caching and layering optimizations used in this repository.

## Example 1: Basic Layer Caching

### Without Optimization
```dockerfile
# BAD: All layers rebuild when any file changes
COPY . /app
WORKDIR /app
RUN pip install -r requirements.txt
```

### With Optimization
```dockerfile
# GOOD: Only requirements layer rebuilds when requirements.txt changes
COPY requirements.txt /app/
WORKDIR /app
RUN pip install -r requirements.txt
COPY . /app
```

## Example 2: Pip Cache Mount

### Without Cache Mount
```dockerfile
# BAD: Downloads packages every time
RUN pip install -r requirements.txt
```

### With Cache Mount
```dockerfile
# GOOD: Reuses downloaded packages between builds
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

## Example 3: Multi-stage Optimization

### Single Stage (Larger Image)
```dockerfile
FROM python:3.11
RUN apt-get update && apt-get install -y build-essential git
RUN pip install -r requirements.txt
# Final image includes build tools (~500MB extra)
```

### Multi-stage (Smaller Image)
```dockerfile
FROM python:3.11 as builder
RUN apt-get update && apt-get install -y build-essential
RUN pip install --user -r requirements.txt

FROM python:3.11-slim
COPY --from=builder /root/.local /root/.local
# Final image without build tools (saves ~500MB)
```

## Real-world Performance Metrics

### Scenario 1: Clean Build
- **Time**: ~8 minutes
- **Downloaded**: ~2GB of pip packages
- **Image size**: 4.5GB (single-stage), 3.8GB (multi-stage)

### Scenario 2: Rebuild After Code Change (No requirements change)

**Without optimization**:
- Time: ~8 minutes
- Downloaded: ~2GB (everything re-downloaded)

**With pip cache + layering**:
- Time: ~45 seconds
- Downloaded: 0MB (cache hit)
- Rebuilds only: code copy layer

### Scenario 3: Rebuild After Adding One Package

**Without optimization**:
- Time: ~8 minutes
- Downloaded: ~2GB

**With pip cache (no layering)**:
- Time: ~4 minutes
- Downloaded: ~50MB (only new package)

**With pip cache + layering**:
- Time: ~2 minutes
- Downloaded: ~50MB (only new package)
- Rebuilds: requirements + code layers

## Layer Visualization

### Build 1 (Initial)
```
Layer 1: Base image [CACHED - FROM registry]
Layer 2: System dependencies [BUILD]
Layer 3: Copy requirements.txt [BUILD]
Layer 4: Install pip packages [BUILD - uses cache mount]
Layer 5: Copy application code [BUILD]
```

### Build 2 (Code change only)
```
Layer 1: Base image [CACHED]
Layer 2: System dependencies [CACHED]
Layer 3: Copy requirements.txt [CACHED]
Layer 4: Install pip packages [CACHED]
Layer 5: Copy application code [REBUILD]
```

### Build 3 (Requirements + code change)
```
Layer 1: Base image [CACHED]
Layer 2: System dependencies [CACHED]
Layer 3: Copy requirements.txt [REBUILD]
Layer 4: Install pip packages [REBUILD - but uses pip cache mount]
Layer 5: Copy application code [REBUILD]
```

## Best Practices Applied

1. **Order layers by change frequency**: Least changing → Most changing
2. **Use cache mounts for package managers**: Persist downloads between builds
3. **Separate dependency installation from code**: Maximize cache hits
4. **Use multi-stage builds**: Reduce final image size
5. **Use .dockerignore**: Minimize build context size
6. **Combine related commands**: Reduce layer count

## Testing the Optimization

### Test 1: First Build
```bash
time docker build -t comfyui:test .
```

### Test 2: Rebuild Without Changes
```bash
time docker build -t comfyui:test .
# Should be nearly instant (all cached)
```

### Test 3: Rebuild After Code Change
```bash
echo "# comment" >> README.md
time docker build -t comfyui:test .
# Should be fast (~30s)
```

### Test 4: Rebuild After Requirements Change
```bash
echo "requests>=2.31.0" >> requirements.txt
time docker build -t comfyui:test .
# Should be moderate (~2-3min with pip cache)
```

## Cache Size Management

Monitor Docker cache usage:
```bash
docker system df
```

Clean up build cache if needed:
```bash
# Remove build cache (but keep layer cache)
docker builder prune

# Remove all unused data
docker system prune -a
```

## Advanced: BuildKit Features Used

- `syntax=docker/dockerfile:1.4`: Latest Dockerfile syntax
- `--mount=type=cache`: Persistent cache between builds
- Multi-stage builds: Optimized final image size
- Layer caching: Docker's native layer reuse