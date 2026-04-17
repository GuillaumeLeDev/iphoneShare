# Serveur de réception de photos iPhone → Ubuntu

## Contexte du projet

Je veux envoyer des photos depuis mon iPhone vers mon PC Ubuntu en un minimum de taps,
via un Raccourci iOS qui envoie la photo à un serveur Python local dockerisé.

## Architecture

```
iPhone (Raccourci iOS)
    ↓ HTTP POST multipart avec la photo
Serveur Python Flask dockerisé sur PC Ubuntu (port 5005)
    ↓
~/Downloads/
```

---

## Environnement

### PC Ubuntu
- **OS** : Ubuntu avec GNOME
- **IP maison** : 192.168.x.x (fixée via bail DHCP statique Freebox)
- **IP campus** : `10.109.252.31`
- **Dossier de destination** : `~/Downloads/` (directement, pas de sous-dossier)
- **Port souhaité** : 5005
- **Utilisateur** : guillaume

### iPhone
- **Déclencheur** : Raccourci iOS dans le menu de partage natif
- **Type de contenu envoyé** : photos (JPEG/PNG/HEIC)

---

## Ce qu'on veut

### Serveur Python
- Recevoir une photo via **HTTP POST**
- La sauvegarder directement dans `~/Downloads/`
- Nommer le fichier avec la **date et heure** pour éviter les doublons
  - Exemple : `2026-04-17_14-32-01.jpg`
- Répondre avec un **JSON de confirmation** `{"status": "ok", "filename": "..."}`
- Afficher un log dans le terminal à chaque photo reçue
- Être **léger** (pas de base de données, pas d'auth complexe)

### Sécurité minimale
- Ajouter un **token secret** dans les headers HTTP pour éviter que n'importe qui sur le réseau envoie des fichiers
- Exemple header : `Authorization: Bearer MON_TOKEN_SECRET`

### Dockerisation
- L'application est **dockerisée** avec Docker + Docker Compose
- Le conteneur démarre automatiquement au boot avec `restart: always`
- Le dossier `~/Downloads/` est monté en **volume Docker** pour que les photos arrivent directement dans Downloads sur le PC
- Les variables sensibles (token) passent par les **variables d'environnement** Docker via un fichier `.env`

---

## Stack technique

- **Python 3**
- **Flask**
- **Docker + Docker Compose** pour la containerisation et l'autostart

---

## Fichiers à créer

```
~/photo-server/
├── server.py              # Le serveur Flask principal
├── requirements.txt       # flask
├── Dockerfile             # Image Docker du serveur
├── docker-compose.yml     # Orchestration + volume + restart always
├── .env                   # Token secret (ne pas committer)
└── README.md              # Instructions d'installation et de lancement
```

### docker-compose.yml (structure attendue)
```yaml
services:
  photo-server:
    build: .
    ports:
      - "5005:5005"
    volumes:
      - /home/guillaume/Downloads:/downloads
    env_file:
      - .env
    restart: always
```

### .env (structure attendue)
```
SECRET_TOKEN=MON_TOKEN_SECRET
```

---

## Format de la requête HTTP attendue

```http
POST /upload HTTP/1.1
Host: 10.109.252.31:5005
Authorization: Bearer MON_TOKEN_SECRET
Content-Type: multipart/form-data

[données de la photo]
```

---

## Réponse attendue du serveur

```json
{
  "status": "ok",
  "filename": "2026-04-17_14-32-01.jpg"
}
```

---

## Détection automatique du réseau Wi-Fi (Raccourci iOS)

Le Raccourci iOS doit détecter automatiquement le réseau Wi-Fi actuel et choisir la bonne IP :

| Réseau Wi-Fi (SSID) | IP du PC |
|---|---|
| `Freebox-4C2A80` | IP maison fixe (à renseigner après config Freebox) |
| `IONIS` | `10.109.252.31` |

### Logique du Raccourci
```
Récupérer le nom du Wi-Fi actuel
Si Wi-Fi = "Freebox-4C2A80" → IP = [IP_MAISON_FIXE]
Si Wi-Fi = "IONIS"          → IP = 10.109.252.31
Sinon → Afficher erreur "Réseau non reconnu"

Envoyer la photo en HTTP POST à http://[IP]:5005/upload
Afficher confirmation ou erreur
```

### Remarque sur l'IP maison
Fixer l'IP du PC dans la Freebox via un bail DHCP statique :
```
mafreebox.freebox.fr → Paramètres → DHCP → Baux statiques → Ajouter le PC
```
Une fois fait, l'IP maison ne changera plus jamais.

---

## Contraintes importantes

- Le serveur doit accepter les fichiers **HEIC** (format photo iPhone par défaut)
  et les sauvegarder tels quels si la conversion JPEG n'est pas possible sans dépendances lourdes
- Taille max des fichiers : **50 MB**
- Le volume Docker doit pointer vers `/home/guillaume/Downloads` (chemin absolu)

---

## Tâches à accomplir

1. Créer `server.py` avec Flask (réception + sauvegarde + auth token)
2. Créer `requirements.txt`
3. Créer `Dockerfile`
4. Créer `docker-compose.yml` avec volume `~/Downloads` et `restart: always`
5. Créer `.env` avec le token secret
6. Créer `README.md` avec les commandes pour build et lancer le conteneur
7. Donner les instructions pas à pas pour créer le Raccourci iOS correspondant
