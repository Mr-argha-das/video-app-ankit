#!/bin/bash
# Server setup script for videcall1.duckdns.org (8003) and videcall2.duckdns.org (8004)
# Run this on your VPS as root

set -e

SERVER_IP=$(hostname -I | awk '{print $1}')

echo "========================================="
echo " VideoCall App Server Setup"
 echo "========================================="
echo "Server IP: $SERVER_IP"
echo ""

# 1. Update system
echo "[1/10] Updating system..."
apt update && apt upgrade -y

# 2. Install dependencies
echo "[2/10] Installing dependencies..."
apt install -y python3 python3-pip python3-venv python3-full python3-dev \
    nginx curl wget gnupg git ufw

# 3. Install MongoDB
echo "[3/10] Installing MongoDB..."
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
    gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
    tee /etc/apt/sources.list.d/mongodb-org-7.0.list
apt update
apt install -y mongodb-org
systemctl start mongod
systemctl enable mongod

# 4. Clone repo
echo "[4/10] Cloning repository..."
cd /opt
if [ -d video-app-ankit ]; then
    cd video-app-ankit
    git pull origin arena/01a0d32d-video-app-ankit
else
    git clone https://github.com/Mr-argha-das/video-app-ankit.git
    cd video-app-ankit
    git checkout arena/01a0d32d-video-app-ankit
fi

# 5. Python venv + dependencies
echo "[5/10] Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 6. Create .env file
echo "[6/10] Creating .env file..."
cat > .env <<EOF
SECRET_KEY=$(openssl rand -hex 32)
ADMIN_PASSWORD=Admin@123
MONGODB_URL=mongodb://localhost:27017
EOF

# 7. Create systemd services for two backend instances
echo "[7/10] Creating systemd services..."

cat > /etc/systemd/system/videoapp1.service <<EOF
[Unit]
Description=VideoCall App Backend 1 (Orange) - Port 8003
After=network.target mongod.service

[Service]
User=root
WorkingDirectory=/opt/video-app-ankit
Environment="PATH=/opt/video-app-ankit/venv/bin"
ExecStart=/opt/video-app-ankit/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8003
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/videoapp2.service <<EOF
[Unit]
Description=VideoCall App Backend 2 (Dating) - Port 8004
After=network.target mongod.service

[Service]
User=root
WorkingDirectory=/opt/video-app-ankit
Environment="PATH=/opt/video-app-ankit/venv/bin"
ExecStart=/opt/video-app-ankit/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8004
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable videoapp1
systemctl enable videoapp2
systemctl start videoapp1
systemctl start videoapp2

# 8. Install Caddy
echo "[8/10] Installing Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian/deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# 9. Configure Caddy
echo "[9/10] Configuring Caddy..."
cat > /etc/caddy/Caddyfile <<EOF
videcall1.duckdns.org {
    reverse_proxy localhost:8003
}

videcall2.duckdns.org {
    reverse_proxy localhost:8004
}
EOF
systemctl restart caddy

# 10. Firewall
echo "[10/10] Configuring firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable

echo ""
echo "========================================="
echo " Setup Complete!"
 echo "========================================="
echo ""
echo "Backend 1 (Orange):  http://videcall1.duckdns.org  (port 8003)"
echo "Backend 2 (Dating):  http://videcall2.duckdns.org  (port 8004)"
echo "Admin Panel 1:       http://videcall1.duckdns.org/admin-panel"
echo "Admin Panel 2:       http://videcall2.duckdns.org/admin-panel"
echo ""
echo "Flutter build commands (run on your dev machine):"
echo ""
echo "# Orange app (videcall1.duckdns.org):"
echo "cd flutter_app"
echo "flutter build apk --release --flavor orange --dart-define=API_BASE_URL=https://videcall1.duckdns.org"
echo ""
echo "# Dating app (videcall2.duckdns.org):"
echo "flutter build apk --release --flavor dating --dart-define=DATING_API_BASE_URL=https://videcall2.duckdns.org"
echo ""
