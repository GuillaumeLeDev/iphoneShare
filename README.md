# iPhoneShare

> Partage de photos et de presse-papier depuis iPhone vers PC Ubuntu, en 2 taps — via iOS Raccourcis et un serveur Flask dockerisé.

---

## Sommaire

- [Aperçu](#aperçu)
- [Fonctionnalités](#fonctionnalités)
- [Architecture](#architecture)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Configuration](#configuration)
- [Démarrage](#démarrage)
- [API](#api)
- [iOS — Raccourcis](#ios--raccourcis)
- [Sécurité](#sécurité)
- [Commandes utiles](#commandes-utiles)
- [Structure du projet](#structure-du-projet)

---

## Aperçu

**iPhoneShare** est un serveur local qui reçoit des photos et du texte depuis un iPhone et les dépose directement dans `~/Downloads/` ou le presse-papier GNOME du PC — sans cloud, sans câble, sans application tierce.

Le flux est entièrement piloté par un **Raccourci iOS natif** déclenché depuis le menu Partager. Tout le trafic reste sur le réseau local.

---

## Fonctionnalités

| Fonctionnalité | Détail |
|---|---|
| Envoi de photos | Dépose le fichier horodaté dans `~/Downloads/` |
| Copie presse-papier | Envoie du texte directement dans le presse-papier GNOME |
| Health check | Endpoint `/health` sans authentification |
| Multi-réseau | Routage automatique selon le SSID (domicile / campus) |
| HTTPS local | Certificat auto-signé requis par iOS |
| Sécurité | Token Bearer + filtrage par sous-réseau |

---

## Architecture

```
iPhone (iOS Shortcuts)
        │  HTTPS POST  (Bearer token)
        ▼
  Flask server :5005  ──► /upload    → ~/Downloads/<timestamp>.<ext>
  (Docker, host network)  /clipboard → GNOME clipboard (xclip)
                          /health    → {"status": "ok"}
```

- **Réseau** : `host` mode Docker pour que mDNS `.local` fonctionne
- **Résolution** : `avahi-daemon` expose `<hostname>.local` sur le Wi-Fi
- **Chiffrement** : TLS avec certificat auto-signé installé sur l'iPhone

---

## Prérequis

**Sur le PC :**
- Docker & Docker Compose
- `avahi-daemon` (résolution mDNS)
- `xclip` (presse-papier GNOME)
- iPhone et PC sur le même réseau Wi-Fi

**Sur l'iPhone :**
- iOS 14+
- Application Raccourcis
- Certificat `cert.pem` installé et approuvé

---

## Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/GuillaumeLeDev/iphoneShare.git
cd iphoneShare
```

### 2. Générer un token secret

```bash
openssl rand -hex 32
```

Copier la valeur générée.

### 3. Créer le fichier `.env`

```bash
cp .env.example .env
# Coller le token dans .env
```

```env
SECRET_TOKEN=<votre_token_32_hex>
```

### 4. Générer le certificat HTTPS

iOS exige HTTPS même sur réseau local. Le certificat doit inclure le nom d'hôte `.local` et l'IP Wi-Fi.

```bash
HOSTNAME=$(hostname)
IP=$(ip addr show wlo1 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 825 -nodes \
  -subj "/CN=${HOSTNAME}.local" \
  -addext "subjectAltName=DNS:${HOSTNAME}.local,IP:${IP}"
```

> `cert.pem` sera envoyé à l'iPhone via AirDrop. `key.pem` reste sur le PC (gitignored).

### 5. Configurer avahi-daemon

```bash
sudo sed -i 's/#allow-interfaces=eth0/allow-interfaces=wlo1/' /etc/avahi/avahi-daemon.conf
sudo systemctl restart avahi-daemon
```

Vérifier la résolution :

```bash
avahi-resolve-host-name -4 $(hostname).local
```

### 6. Autoriser Docker à accéder à l'affichage X11

À exécuter à chaque session (ou ajouter au démarrage) :

```bash
xhost +local:docker
```

### 7. Installer le certificat sur l'iPhone

1. Envoyer `cert.pem` par AirDrop
2. **Réglages → Général → Profils** → Installer le profil
3. **Réglages → Général → À propos → Réglages de confiance des certificats** → Activer la confiance totale

---

## Configuration

### Variables d'environnement (`.env`)

| Variable | Description |
|---|---|
| `SECRET_TOKEN` | Token Bearer requis pour toutes les requêtes authentifiées |

### Réseaux autorisés (`server.py`)

Les sous-réseaux suivants sont acceptés par défaut :

```python
ALLOWED_NETWORKS = [
    "192.168.1.0/24",   # Freebox domicile
    "10.109.0.0/16",    # Campus IONIS
]
```

Pour ajouter un réseau, modifier cette liste dans `server.py`.

### Paramètres serveur

| Paramètre | Valeur |
|---|---|
| Port | `5005` (HTTPS) |
| Taille max fichier | 50 Mo |
| Répertoire de dépôt | `~/Downloads/` |
| Formats acceptés | JPEG, PNG, HEIC, HEIF, GIF, WebP |
| Format nom de fichier | `YYYY-MM-DD_HH-MM-SS.<ext>` |

---

## Démarrage

```bash
# Lancer le serveur
docker compose up -d --build

# Vérifier qu'il tourne
curl -sk https://$(hostname).local:5005/health
# → {"status": "ok"}

# Voir les logs en direct
docker compose logs -f
```

---

## API

Toutes les routes (sauf `/health`) requièrent un header `Authorization: Bearer <SECRET_TOKEN>`.

### `GET /health`

Vérifie que le serveur est opérationnel. Pas d'authentification requise.

```bash
curl -sk https://<hostname>.local:5005/health
```

```json
{"status": "ok"}
```

---

### `POST /upload`

Reçoit une photo et la dépose dans `~/Downloads/`.

```bash
curl -sk \
  -H "Authorization: Bearer $SECRET_TOKEN" \
  -F "file=@photo.jpg" \
  https://<hostname>.local:5005/upload
```

**Réponse :**

```json
{
  "status": "ok",
  "filename": "2026-04-19_14-32-01.jpg"
}
```

---

### `POST /clipboard`

Envoie du texte dans le presse-papier GNOME.

```bash
curl -sk \
  -H "Authorization: Bearer $SECRET_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello World"}' \
  https://<hostname>.local:5005/clipboard
```

**Réponse :**

```json
{"status": "ok"}
```

---

## iOS — Raccourcis

Le Raccourci implémente la logique suivante :

1. Reçoit le contenu depuis le menu **Partager**
2. Lit le SSID Wi-Fi actuel
3. Choisit l'IP de destination selon le réseau :
   - `Freebox-XXXXXX` → `192.168.1.x`
   - `IONIS` → `10.109.x.x`
4. Envoie une requête HTTPS POST avec le token Bearer
5. Affiche une notification de succès ou d'erreur

Des captures d'écran de la configuration du Raccourci sont disponibles dans le dossier `screenshots/`.

---

## Sécurité

| Couche | Mécanisme |
|---|---|
| Réseau | Requêtes refusées si IP hors des sous-réseaux autorisés |
| Authentification | Token Bearer dans le header `Authorization` |
| Chiffrement | HTTPS/TLS (certificat auto-signé) |
| Confidentialité | Tout le trafic reste sur le réseau local |
| Rotation du token | Modifier `.env` et redémarrer le conteneur |

> Le filtrage réseau est appliqué **avant** la validation du token pour limiter l'exposition.

---

## Commandes utiles

```bash
# Démarrer
docker compose up -d --build

# Arrêter
docker compose down

# Redémarrer
docker compose restart

# Logs temps réel
docker compose logs -f

# Vérifier la résolution mDNS
avahi-resolve-host-name -4 $(hostname).local

# Regénérer un token
openssl rand -hex 32

# Autoriser X11 (à chaque session)
xhost +local:docker

# Health check rapide
curl -sk https://$(hostname).local:5005/health
```

---

## Structure du projet

```
iphoneShare/
├── server.py              # Serveur Flask (routes, auth, upload, clipboard)
├── requirements.txt       # Dépendances Python (flask==3.1.0)
├── Dockerfile             # Image Python 3.12-slim
├── docker-compose.yml     # Orchestration (host network, volumes X11)
├── .env.example           # Template de configuration
├── .env                   # Token secret (gitignored)
├── cert.pem               # Certificat TLS (à envoyer à l'iPhone)
├── key.pem                # Clé privée TLS (gitignored)
├── .gitignore
└── screenshots/           # Captures de configuration iOS Raccourcis
    ├── menupartagerenvoyer.png
    ├── notification.png
    ├── raccourci1.png
    └── Raccourci2.png
```

---

## Licence

Usage personnel. Aucune donnée ne quitte le réseau local.
