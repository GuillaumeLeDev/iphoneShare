# iPhone Photo Server

Envoie des photos depuis ton iPhone vers ton PC Ubuntu en quelques taps, via un Raccourci iOS et un serveur Flask dockerisé.

```
iPhone (Raccourci iOS)
    ↓  HTTP POST multipart
Serveur Python Flask (Docker, port 5005)
    ↓
~/Downloads/
```

---

## Prérequis

- Docker + Docker Compose installés sur le PC
- L'iPhone et le PC sont sur le **même réseau local**
- L'application **Raccourcis** sur iPhone (iOS 13+)

---

## Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/<ton-pseudo>/<ton-repo>.git
cd <ton-repo>
```

### 2. Créer le fichier `.env`

Le fichier `.env` contient le token secret qui protège le serveur. Il ne doit **jamais être commité**.

```bash
cp .env.example .env
```

Édite `.env` et remplace la valeur par un token fort :

```bash
# Générer un token aléatoire (recommandé)
openssl rand -hex 32
```

```
SECRET_TOKEN=colle_ton_token_ici
```

### 3. Lancer le serveur

```bash
docker compose up -d --build
```

Le conteneur démarre automatiquement au boot du PC (`restart: always`).

### 4. Vérifier que le serveur tourne

```bash
curl http://localhost:5005/health
# {"status": "ok"}
```

---

## Commandes utiles

```bash
docker compose logs -f           # logs en temps réel
docker compose down              # arrêter le serveur
docker compose up -d --build     # rebuilder après modification
```

---

## Configuration réseau

### IP fixe sur le PC

Pour que l'iPhone trouve toujours le PC à la même adresse, configure un **bail DHCP statique** dans ton routeur.

Sur Freebox : `mafreebox.freebox.fr` → Paramètres → DHCP → Baux statiques → ajouter le PC.

### Réseaux supportés par le Raccourci

Le Raccourci iOS détecte automatiquement le Wi-Fi et choisit la bonne IP :

| Réseau (SSID) | IP du PC |
|---|---|
| Réseau maison | IP fixe attribuée par le routeur |
| Réseau campus / autre | IP du PC sur ce réseau |

---

## Raccourci iOS

> Les captures d'écran du Raccourci sont disponibles ci-dessous.

### Logique générale

1. Reçoit la photo depuis le menu de partage iOS
2. Détecte le SSID Wi-Fi actuel
3. Choisit l'IP correspondante (ou affiche une erreur si le réseau est inconnu)
4. Envoie la photo en `POST /upload` avec le token dans le header `Authorization`
5. Affiche la confirmation

### Paramètres de la requête HTTP

| Paramètre | Valeur |
|---|---|
| URL | `http://<IP_DU_PC>:5005/upload` |
| Méthode | `POST` |
| Header | `Authorization: Bearer <SECRET_TOKEN>` |
| Corps | Multipart form-data, champ `file` = la photo |

> Le token à renseigner dans le Raccourci est celui que tu as mis dans ton fichier `.env`.  
> Ne le partage pas et ne le publie pas.

---

## Sécurité

- Le token secret transite dans le header HTTP — utilise ce serveur **uniquement en réseau local de confiance**.
- Le fichier `.env` est listé dans `.gitignore` et ne sera jamais commité.
- Si tu penses que ton token a été exposé, génère-en un nouveau avec `openssl rand -hex 32`, mets à jour `.env`, relance avec `docker compose up -d --build`, et mets à jour le Raccourci iOS.

---

## Format de la réponse

```json
{ "status": "ok", "filename": "2026-04-17_14-32-01.jpg" }
```

Les fichiers sont nommés avec la date et l'heure pour éviter les doublons et sauvegardés dans `~/Downloads/`.

Formats acceptés : JPEG, PNG, HEIC, HEIF, GIF, WebP. Taille max : 50 MB.
