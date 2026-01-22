#!/bin/bash
set -e

echo "====================================="
echo " Installing Monitoring Stack"
echo " Node Exporter + Prometheus + Grafana"
echo " Ubuntu 24.04 (Noble) SAFE"
echo "====================================="

# -------------------------------
# CLEAN BROKEN GRAFANA REPOS FIRST
# -------------------------------
sudo rm -f /etc/apt/sources.list.d/*grafana*
sudo rm -f /etc/apt/sources.list.d/archive_uri-https_packages_grafana_com_oss_deb*.list

# -------------------------------
# SYSTEM UPDATE (SAFE NOW)
# -------------------------------
sudo apt clean
sudo apt update -y

# -------------------------------
# NODE EXPORTER
# -------------------------------
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvf node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=ubuntu
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl restart node_exporter

# -------------------------------
# PROMETHEUS
# -------------------------------
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown -R ubuntu:ubuntu /etc/prometheus /var/lib/prometheus

cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v2.49.0/prometheus-2.49.0.linux-amd64.tar.gz
tar xvf prometheus-2.49.0.linux-amd64.tar.gz

sudo cp prometheus-2.49.0.linux-amd64/prometheus /etc/prometheus/
sudo cp prometheus-2.49.0.linux-amd64/promtool /etc/prometheus/
sudo cp -r prometheus-2.49.0.linux-amd64/consoles /etc/prometheus/
sudo cp -r prometheus-2.49.0.linux-amd64/console_libraries /etc/prometheus/

sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=ubuntu
ExecStart=/etc/prometheus/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus

[Install]
WantedBy=default.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl restart prometheus

# -------------------------------
# GRAFANA (OFFICIAL .DEB — SAFE)
# -------------------------------
cd /tmp
wget -q https://dl.grafana.com/oss/release/grafana_10.3.1_amd64.deb
sudo dpkg -i grafana_10.3.1_amd64.deb || sudo apt -f install -y

sudo systemctl enable grafana-server
sudo systemctl restart grafana-server

# -------------------------------
# DONE
# -------------------------------
echo "====================================="
echo " Monitoring Stack Installed SUCCESSFULLY"
echo "====================================="
echo "Grafana      : http://<EC2-IP>:3000"
echo "Prometheus   : http://<EC2-IP>:9090"
echo "Node Exporter: http://<EC2-IP>:9100/metrics"
