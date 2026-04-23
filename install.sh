#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo "==========================================="
echo "     Installation iphoneShare"
echo "==========================================="
echo ""

# --- Installation automatique de Docker ---
install_docker() {
    echo "Docker non trouvé. Installation en cours..."
    OS_ID=$(. /etc/os-release && echo "$ID")
    [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]] && \
        err "Installation automatique non supportée sur $OS_ID. Installez Docker manuellement : https://docs.docker.com/engine/install/"

    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" \
        -o /etc/apt/keyrings/docker.asc 2>/dev/null
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/$OS_ID \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    sudo usermod -aG docker "$USER"
    ok "Docker installé"
    warn "Vous avez été ajouté au groupe 'docker'."
    warn "Les commandes docker de ce script tournent via 'sg docker'."
    DOCKER_CMD="sg docker -c"
}

# --- Vérifications prérequis ---
DOCKER_CMD=""
if ! command -v docker &>/dev/null; then
    install_docker
elif ! docker compose version &>/dev/null; then
    err "Docker Compose non trouvé. Mettez Docker à jour : https://docs.docker.com/engine/install/"
fi

# Vérifier les permissions Docker (même si Docker était déjà installé)
if ! docker info &>/dev/null 2>&1; then
    warn "Permissions Docker insuffisantes. Ajout au groupe docker..."
    sudo usermod -aG docker "$USER"
    DOCKER_CMD="sg docker -c"
    ok "Ajouté au groupe docker"
fi

command -v openssl &>/dev/null || err "openssl non trouvé : sudo apt install openssl"
command -v python3 &>/dev/null || err "python3 non trouvé : sudo apt install python3"
ok "Prérequis OK"

# Wrapper pour les commandes docker (gère le cas post-install sans logout)
docker_run() {
    if [[ -n "$DOCKER_CMD" ]]; then
        sg docker -c "$*"
    else
        eval "$*"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Détection des IPs de la machine ---
echo ""
echo "Détection des interfaces réseau..."
mapfile -t IPS < <(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -v '^127\.')

if [[ ${#IPS[@]} -eq 0 ]]; then
    err "Aucune IP locale détectée. Vérifiez votre connexion réseau."
fi

LETTERS=({a..z})
echo "IPs détectées :"
for i in "${!IPS[@]}"; do
    echo "  ${LETTERS[$i]}) ${IPS[$i]}"
done

echo ""
read -rp "À quelle lettre correspond votre IP ? (192.168.1.x est la plus probable) : " choice
idx=$(( $(printf '%d' "'$choice") - $(printf '%d' "'a") ))
CURRENT_IP="${IPS[$idx]}"
[[ -z "$CURRENT_IP" ]] && err "Choix invalide."
ok "IP sélectionnée : $CURRENT_IP"

# Détection du sous-réseau via ip route
CURRENT_SUBNET=$(python3 -c "
import subprocess, ipaddress
result = subprocess.run(['ip', 'route'], capture_output=True, text=True)
for line in result.stdout.splitlines():
    parts = line.split()
    if parts and '/' in parts[0]:
        try:
            net = ipaddress.ip_network(parts[0], strict=False)
            if ipaddress.ip_address('$CURRENT_IP') in net:
                print(parts[0])
                exit()
        except:
            pass
print('.'.join('$CURRENT_IP'.split('.')[:3]) + '.0/24')
")
ok "Sous-réseau détecté : $CURRENT_SUBNET"

# --- Réseau maison ou campus ? ---
echo ""
echo "Où êtes-vous actuellement ?"
echo "  a) Maison"
echo "  b) Campus"
read -rp "Votre choix [a/b] : " location

if [[ "$location" == "a" ]]; then
    HOME_IP="$CURRENT_IP"
    HOME_SUBNET="$CURRENT_SUBNET"
    echo ""
    read -rp "IP campus (laisser vide si inconnue) : " CAMPUS_IP
    if [[ -n "$CAMPUS_IP" ]]; then
        read -rp "Sous-réseau campus [$(echo "$CAMPUS_IP" | cut -d. -f1-3).0/24] : " CAMPUS_SUBNET
        CAMPUS_SUBNET="${CAMPUS_SUBNET:-$(echo "$CAMPUS_IP" | cut -d. -f1-3).0/24}"
    fi
else
    CAMPUS_IP="$CURRENT_IP"
    CAMPUS_SUBNET="$CURRENT_SUBNET"
    echo ""
    read -rp "IP maison (laisser vide si inconnue) : " HOME_IP
    if [[ -n "$HOME_IP" ]]; then
        HOME_SUBNET="$(echo "$HOME_IP" | cut -d. -f1-3).0/24"
    fi
fi

# --- SSIDs Wi-Fi ---
echo ""
DETECTED_SSID=$(iwgetid -r 2>/dev/null || echo "")

confirm_ssid() {
    local label="$1" detected="$2" varname="$3"
    if [[ -n "$detected" ]]; then
        read -rp "Wi-Fi $label détecté : '$detected' — c'est correct ? [O/n] : " confirm
        if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
            read -rp "Nom du Wi-Fi $label (SSID) : " val
            eval "$varname=\"$val\""
        else
            eval "$varname=\"$detected\""
        fi
    else
        read -rp "Nom du Wi-Fi $label (SSID) : " val
        eval "$varname=\"$val\""
    fi
}

if [[ "$location" == "a" ]]; then
    confirm_ssid "maison" "$DETECTED_SSID" HOME_SSID
    read -rp "Nom du Wi-Fi campus (SSID) : " CAMPUS_SSID
else
    confirm_ssid "campus" "$DETECTED_SSID" CAMPUS_SSID
    read -rp "Nom du Wi-Fi maison (SSID) : " HOME_SSID
fi

# --- Dossier de destination ---
echo ""
DEFAULT_DIR="$HOME/Downloads"
read -rp "Dossier de destination [$DEFAULT_DIR] : " DOWNLOAD_DIR
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$DEFAULT_DIR}"
mkdir -p "$DOWNLOAD_DIR"
ok "Dossier : $DOWNLOAD_DIR"

# --- Génération du token ---
TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(32))")
ok "Token généré"

# --- Génération du certificat SSL ---
echo ""
echo "Génération du certificat SSL..."

SAN="subjectAltName=IP:127.0.0.1,DNS:localhost,DNS:$(hostname).local"
[[ -n "$HOME_IP"   ]] && SAN="$SAN,IP:$HOME_IP"
[[ -n "$CAMPUS_IP" ]] && SAN="$SAN,IP:$CAMPUS_IP"

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout key.pem \
    -out cert.pem \
    -days 3650 \
    -subj "/CN=$(hostname)" \
    -addext "$SAN" 2>/dev/null

chmod 600 key.pem
ok "Certificat SSL généré (valable 10 ans)"

# --- Fichier .env ---
NETWORKS=""
[[ -n "$HOME_SUBNET"   ]] && NETWORKS="$HOME_SUBNET"
[[ -n "$CAMPUS_SUBNET" ]] && NETWORKS="${NETWORKS:+$NETWORKS,}$CAMPUS_SUBNET"

cat > .env << EOF
SECRET_TOKEN=$TOKEN
ALLOWED_NETWORKS="$NETWORKS"
EOF
ok ".env créé"

# --- docker-compose.yml ---
cat > docker-compose.yml << EOF
services:
  photo-server:
    build: .
    network_mode: host
    volumes:
      - ${DOWNLOAD_DIR}:/downloads
      - /tmp/.X11-unix:/tmp/.X11-unix
    environment:
      - DISPLAY=\${DISPLAY:-:0}
    env_file:
      - .env
    restart: always
EOF
ok "docker-compose.yml mis à jour"

# --- Build et lancement ---
echo ""
echo "Build et lancement du conteneur..."
docker_run "docker compose up -d --build"
ok "Serveur démarré"

# --- Test de sanité ---
echo ""
echo "Test de sanité..."
sleep 2
if curl -sk "https://$CURRENT_IP:5005/health" | grep -q '"ok"'; then
    ok "Serveur répond sur https://$CURRENT_IP:5005/health"
else
    warn "Le serveur ne répond pas encore (normal si le build prend du temps)."
    warn "Vérifiez avec : docker compose logs -f"
fi

# --- Fichier de config iPhone ---
IPHONE_FILE="SETUP_IPHONE.txt"
{
echo "==========================================="
echo "  Configuration Raccourci iOS - iphoneShare"
echo "==========================================="
echo ""
echo "TOKEN D'AUTHENTIFICATION"
echo "  $TOKEN"
echo ""
echo "RÉSEAU MAISON ($HOME_SSID)"
if [[ -n "$HOME_IP" ]]; then
echo "  URL upload : https://$HOME_IP:5005/upload"
echo "  URL test   : https://$HOME_IP:5005/health"
else
echo "  IP non configurée (relancez install.sh depuis chez vous)"
fi
echo ""
echo "RÉSEAU CAMPUS ($CAMPUS_SSID)"
if [[ -n "$CAMPUS_IP" ]]; then
echo "  URL upload : https://$CAMPUS_IP:5005/upload"
echo "  URL test   : https://$CAMPUS_IP:5005/health"
else
echo "  IP non configurée (relancez install.sh depuis le campus)"
fi
echo ""
echo "==========================================="
echo "  Instructions Raccourci iOS"
echo "==========================================="
echo ""
echo "1. Ouvrez l'app Raccourcis → Nouveau raccourci"
echo "2. Ajoutez l'action 'Récupérer le réseau Wi-Fi actuel'"
echo "   → Variable : wifi"
echo ""
echo "3. Ajoutez un bloc 'Si' :"
echo "   Condition : wifi contient '$HOME_SSID'"
echo "   → Ajoutez 'Obtenir le contenu de l'URL' :"
echo "       URL     : https://$HOME_IP:5005/upload"
echo "       Méthode : POST"
echo "       Corps   : Formulaire → clé 'photo' = [Entrée du raccourci]"
echo "       Headers : Authorization = Bearer $TOKEN"
echo ""
echo "4. Bloc 'Sinon si' :"
echo "   Condition : wifi contient '$CAMPUS_SSID'"
echo "   → Ajoutez 'Obtenir le contenu de l'URL' :"
echo "       URL     : https://$CAMPUS_IP:5005/upload"
echo "       Méthode : POST"
echo "       Corps   : Formulaire → clé 'photo' = [Entrée du raccourci]"
echo "       Headers : Authorization = Bearer $TOKEN"
echo ""
echo "5. Bloc 'Sinon' :"
echo "   → Afficher une alerte : 'Réseau Wi-Fi non reconnu'"
echo ""
echo "6. Ajoutez 'Afficher le résultat' à la fin pour voir la confirmation"
echo ""
echo "IMPORTANT : Lors du premier test depuis Safari iPhone,"
echo "ouvrez https://$CURRENT_IP:5005/health et acceptez"
echo "l'avertissement de sécurité SSL (certificat auto-signé)."
} > "$IPHONE_FILE"

ok "Fichier $IPHONE_FILE généré"

echo ""
echo "==========================================="
echo -e "${GREEN}  Installation terminée !${NC}"
echo "==========================================="
echo ""
echo "  Prochaines étapes :"
echo "  1. Lisez SETUP_IPHONE.txt pour configurer le Raccourci"
echo "  2. Testez depuis Safari iPhone : https://$CURRENT_IP:5005/health"
echo "  3. Logs du serveur : docker compose logs -f"
echo ""
if [[ -n "$DOCKER_CMD" ]]; then
    echo "==========================================="
    echo -e "${YELLOW}  IMPORTANT — permissions Docker${NC}"
    echo "==========================================="
    echo ""
    echo "  Vous venez d'être ajouté au groupe docker."
    echo "  Pour utiliser 'docker' dans ce terminal, exécutez :"
    echo ""
    echo "    newgrp docker"
    echo ""
fi
