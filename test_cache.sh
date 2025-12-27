cd /tmp/cache-test

# Build test1 (populate cache)
echo "=== Test 1: First build (populating cache) ==="
time docker build -f Dockerfile.test1 -t cache-test1 .

# Check cache was populated
echo ""
echo "=== Cache status after test1 ==="
docker builder du | grep -A5 "ID.*SIZE"

# Build test2 WITH cache
echo ""
echo "=== Test 2a: Build with cache ==="
time docker build -f Dockerfile.test2 -t cache-test2 .

# Clear cache
echo ""
echo "=== Clearing cache ==="
docker builder prune -af

# Rebuild test2 WITHOUT cache
echo ""
echo "=== Test 2b: Rebuild without cache ==="
time docker build -f Dockerfile.test2 -t cache-test2-nocache .
