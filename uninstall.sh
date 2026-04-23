#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

echo "==========================================="
echo "     Désinstallation iphoneShare"
echo "==========================================="
echo ""
warn "Cette opération va arrêter le serveur et supprimer les fichiers générés."
read -rp "Continuer ? [o/N] " confirm
[[ "$confirm" != "o" && "$confirm" != "O" ]] && echo "Annulé." && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Arrêt et suppression du conteneur + image
if command -v docker &>/dev/null && [[ -f docker-compose.yml ]]; then
    echo ""
    echo "Arrêt du conteneur Docker..."
    docker compose down --rmi all 2>/dev/null && ok "Conteneur et image supprimés" || warn "Rien à arrêter."
fi

# Suppression des fichiers générés
echo ""
echo "Suppression des fichiers générés..."
for f in .env cert.pem key.pem SETUP_IPHONE.txt; do
    if [[ -f "$f" ]]; then
        rm "$f"
        ok "$f supprimé"
    fi
done

# Remise à zéro de docker-compose.yml depuis l'exemple
if [[ -f docker-compose.yml ]]; then
    cat > docker-compose.yml << 'EOF'
services:
  photo-server:
    build: .
    network_mode: host
    volumes:
      - ~/Downloads:/downloads
      - /tmp/.X11-unix:/tmp/.X11-unix
    environment:
      - DISPLAY=${DISPLAY:-:0}
    env_file:
      - .env
    restart: always
EOF
    ok "docker-compose.yml remis à zéro"
fi

echo ""
ok "Désinstallation terminée."
echo ""
echo "Les fichiers source (server.py, Dockerfile, etc.) sont conservés."
echo "Pour réinstaller : ./install.sh"
echo ""
