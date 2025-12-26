# ComfyUI Dockerfile with optimized pip caching and layering
# syntax=docker/dockerfile:1.4

FROM python:3.11-slim as base

# Set working directory
WORKDIR /app

# Install system dependencies in a single layer
RUN apt-get update && apt-get install -y \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy only requirements first for better layer caching
# This layer will only rebuild if requirements.txt changes
COPY requirements.txt .

# Install Python dependencies with pip cache mount
# Using BuildKit cache mount to persist pip cache between builds
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Clone ComfyUI repository
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI

# Copy ComfyUI requirements and install
WORKDIR /app/ComfyUI
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Copy any additional files or custom nodes
# This should be done last as these change most frequently
COPY . /app/custom

# Expose port for ComfyUI
EXPOSE 8188

# Set the default command
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
