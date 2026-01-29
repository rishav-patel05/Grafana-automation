#!/bin/bash
set -e

echo "=== STEP 1: Install Docker (official, Ubuntu 24.04 safe) ==="

sudo apt remove docker docker-engine docker.io containerd runc -y || true
sudo apt update
sudo apt install -y ca-certificates curl gnupg software-properties-common
sudo add-apt-repository universe -y

sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
| sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker ubuntu || true
newgrp docker <<EOF

echo "=== STEP 2: Create project structure ==="

mkdir -p ~/mimir-stack/{mimir,prometheus,grafana}
cd ~/mimir-stack

echo "=== STEP 3: Write Mimir config (latest schema) ==="

cat > mimir/mimir.yml <<'YAML'
multitenancy_enabled: false

server:
  http_listen_port: 9009

ingester:
  ring:
    kvstore:
      store: inmemory
    replication_factor: 1

blocks_storage:
  backend: filesystem
  filesystem:
    dir: /data/blocks

limits:
  max_global_series_per_user: 0
YAML

echo "=== STEP 4: Write Prometheus config ==="

cat > prometheus/prometheus.yml <<'YAML'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["prometheus:9090"]

  - job_name: "node-exporter"
    static_configs:
      - targets: ["node-exporter:9100"]

remote_write:
  - url: "http://mimir:9009/api/v1/push"
YAML

echo "=== STEP 5: Write docker-compose.yml ==="

cat > docker-compose.yml <<'YAML'
services:
  mimir:
    image: grafana/mimir:latest
    command: ["-config.file=/etc/mimir/mimir.yml"]
    volumes:
      - ./mimir/mimir.yml:/etc/mimir/mimir.yml
      - mimir-data:/data
    ports:
      - "9009:9009"

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
    ports:
      - "9090:9090"
    depends_on:
      - mimir

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    depends_on:
      - mimir

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'

volumes:
  mimir-data:
YAML

echo "=== STEP 6: Start stack ==="

docker compose down || true
docker compose up -d

echo "=== STEP 7: Health checks ==="

sleep 5

echo "Mimir status:"
curl -s http://localhost:9009/ready || echo "Mimir not ready yet"

echo
echo "Node Exporter sample metrics:"
curl -s http://localhost:9100/metrics | head -n 5

echo
echo "Containers running:"
docker ps

echo
echo "=== SETUP COMPLETE ==="
echo "Grafana:  http://<EC2-IP>:3000  (admin/admin)"
echo "Prometheus: http://<EC2-IP>:9090"
echo "Mimir: http://<EC2-IP>:9009"
EOF
