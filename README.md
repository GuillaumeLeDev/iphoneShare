# iPhone Photo Server

Serveur Flask dockerisé permettant de recevoir des photos depuis un iPhone via un Raccourci iOS et de les enregistrer automatiquement dans un dossier local.

```
iPhone (Raccourci iOS)
    ↓  HTTPS POST multipart/form-data
Serveur Python Flask (Docker, port 5005)
    ↓
~/Downloads/
```

---

## Prérequis

- Docker et Docker Compose installés sur la machine hôte
- L'iPhone et la machine hôte doivent être sur le **même réseau local**
- L'application **Raccourcis** sur iPhone (iOS 14 ou supérieur)
- `avahi-daemon` installé sur la machine hôte (pour la résolution mDNS)

---

## Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/GuillaumeLeDev/iphoneShare.git
cd iphoneShare
```

### 2. Configurer le token secret

Le fichier `.env` contient le token d'authentification des requêtes entrantes. Il est listé dans `.gitignore` et ne doit jamais être commité.

```bash
cp .env.example .env
```

Générer un token aléatoire sécurisé et le coller dans `.env` :

```bash
openssl rand -hex 32
```

```env
SECRET_TOKEN=coller_le_token_ici
```

### 3. Générer le certificat HTTPS

Le serveur fonctionne en HTTPS. Un certificat auto-signé est nécessaire pour que l'iPhone puisse établir une connexion chiffrée sur le réseau local.

Remplacer `<IP_DU_PC>` par l'adresse IP de la machine sur le réseau local, et `<HOSTNAME>` par le nom de la machine (résultat de la commande `hostname`) :

```bash
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 825 -nodes \
  -subj "/CN=<HOSTNAME>.local" \
  -addext "subjectAltName=DNS:<HOSTNAME>.local,IP:<IP_DU_PC>"
```

> `cert.pem` et `key.pem` sont listés dans `.gitignore` et ne seront jamais commités.

### 4. Configurer avahi-daemon

`avahi-daemon` permet à la machine d'être joignable via son nom `.local` sur le réseau local (protocole mDNS). C'est indispensable pour que le Raccourci iOS puisse déclencher la permission d'accès au réseau local.

Restreindre avahi à l'interface Wi-Fi (remplacer `wlo1` par le nom de l'interface réseau si nécessaire) :

```bash
sudo sed -i 's/#allow-interfaces=eth0/allow-interfaces=wlo1/' /etc/avahi/avahi-daemon.conf
sudo systemctl restart avahi-daemon
```

Vérifier que la résolution fonctionne :

```bash
avahi-resolve-host-name -4 $(hostname).local
# Doit retourner l'IP Wi-Fi de la machine, pas une IP Docker
```

### 5. Lancer le serveur

```bash
docker compose up -d --build
```

Le conteneur est configuré avec `restart: always` et démarrera automatiquement au boot de la machine.

### 6. Vérifier que le serveur fonctionne

```bash
curl -sk https://$(hostname).local:5005/health
# Réponse attendue : {"status": "ok"}
```

---

## Installer le certificat sur l'iPhone

Cette étape est requise pour que l'iPhone fasse confiance au certificat auto-signé.

**Étape 1 — Envoyer le certificat sur l'iPhone**

Envoyer le fichier `cert.pem` par AirDrop depuis le PC vers l'iPhone.

**Étape 2 — Installer le profil**

Réglages → **Profil téléchargé** (visible en haut de l'écran) → Installer → saisir le code → Installer

**Étape 3 — Activer la confiance complète**

Réglages → Général → À propos → **Réglages des certificats de confiance** → activer le certificat installé

---

## Configurer le Raccourci iOS

### Vue d'ensemble

Le Raccourci est déclenché depuis le menu de partage natif d'iOS et effectue les actions suivantes :

1. Sélectionne la photo à envoyer
2. Lit le SSID du réseau Wi-Fi actuel
3. Définit l'adresse IP du serveur en fonction du réseau (ou affiche une erreur si le réseau n'est pas reconnu)
4. Envoie la photo via `POST /upload` avec le token dans le header `Authorization`
5. Affiche la confirmation

### Paramètres de la requête HTTP

| Paramètre | Valeur |
|---|---|
| URL | `https://<HOSTNAME>.local:5005/upload` |
| Méthode | `POST` |
| Header | `Authorization: Bearer <SECRET_TOKEN>` |
| Corps | Formulaire multipart, champ `file` = la photo |

> Le token doit correspondre à la valeur définie dans le fichier `.env` sur le serveur.

### Première exécution

Lors du premier lancement du Raccourci, iOS affichera la popup **"Raccourcis souhaite accéder aux appareils de votre réseau local"**. Il est impératif d'accepter pour que les requêtes puissent atteindre le serveur.

> **Pourquoi `.local` et pas une IP directe ?**
> iOS exige une permission explicite pour qu'une application accède au réseau local (`192.168.x.x`). Cette permission n'est déclenchée que lorsque l'application utilise le protocole mDNS (résolution d'un nom `.local`). Avec une adresse IP brute, iOS bloque silencieusement la connexion sans jamais afficher le dialogue de permission.

---

## Réseaux autorisés

Pour des raisons de sécurité, le serveur rejette toute requête provenant d'une IP hors des sous-réseaux configurés, avant même la vérification du token :

| Réseau | Plage |
|---|---|
| Réseau local domestique | `192.168.1.0/24` |
| Réseau campus / entreprise | `10.109.0.0/16` |

Adapter ces plages dans `server.py` selon la configuration réseau locale.

> **Note :** Sur un réseau d'entreprise ou de campus (`10.x.x.x` large), iOS ne considère pas l'adresse comme locale et n'applique pas la restriction mDNS. Une URL avec une IP directe et HTTP simple peut suffire dans ce contexte.

---

## Commandes utiles

```bash
docker compose logs -f            # Afficher les logs en temps réel
docker compose down               # Arrêter le serveur
docker compose up -d --build      # Rebuilder et redémarrer après modification
```

---

## Formats de fichiers supportés

JPEG, PNG, HEIC, HEIF, GIF, WebP — taille maximale : **50 Mo**

Les fichiers sont nommés d'après la date et l'heure de réception afin d'éviter les doublons :

```
2026-04-17_14-32-01.jpg
```

Ils sont enregistrés dans `~/Downloads/` sur la machine hôte.

---

## Sécurité

- Le serveur rejette toute requête dont l'IP source n'appartient pas aux sous-réseaux autorisés, avant la vérification du token.
- Le token secret transite dans le header HTTP `Authorization`. Ce serveur est conçu pour un usage sur **réseau local de confiance uniquement**.
- Le fichier `.env` est exclu du contrôle de version via `.gitignore`.
- En cas de compromission du token, générer un nouveau token avec `openssl rand -hex 32`, mettre à jour `.env`, relancer le conteneur avec `docker compose up -d --build`, et mettre à jour le Raccourci iOS.
