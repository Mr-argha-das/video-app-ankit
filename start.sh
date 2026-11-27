#!/bin/bash
echo "🎥 VideoCall App Backend Setup"
echo "================================"

cd "$(dirname "$0")"

# Create virtual environment if needed (ya existing toota hua ho)
if [ ! -x "venv/bin/python" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# .env check — bina SECRET_KEY/ADMIN_PASSWORD ke app start nahi hogi
if [ ! -f ".env" ]; then
    echo "⚠️  .env not found — .env.example copy karke configure karo:"
    cp .env.example .env
    echo "   → .env banaya gaya. SECRET_KEY aur ADMIN_PASSWORD set karo phir wapas run karo."
fi

# Activate
source venv/bin/activate

# Install requirements
echo "📥 Installing dependencies..."
pip install -r requirements.txt -q

# Create necessary directories
mkdir -p static/uploads/profiles
mkdir -p static/uploads/hosts/pics
mkdir -p static/uploads/hosts/videos

echo ""
echo "✅ Setup complete!"
echo ""
echo "🚀 Starting server..."
echo "   API Docs:    http://localhost:8000/docs"
echo "   Admin Panel: http://localhost:8000/admin-panel"
echo "   Admin Login: admin / Admin@123"
echo ""

# --proxy-headers: nginx/Caddy ke peeche sahi client IP + https scheme
uvicorn main:app --host 0.0.0.0 --port 8000 --reload --proxy-headers --forwarded-allow-ips="*"
