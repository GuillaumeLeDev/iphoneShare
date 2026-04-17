# iPhone Photo Server

A lightweight Flask server running in Docker that receives photos sent from an iPhone via an iOS Shortcut and saves them directly to a local directory.

```
iPhone (iOS Shortcut)
    ↓  HTTP POST multipart/form-data
Python Flask server (Docker, port 5005)
    ↓
~/Downloads/
```

---

## Requirements

- Docker and Docker Compose installed on the host machine
- The iPhone and the host machine must be on the **same local network**
- The **Shortcuts** app on iPhone (iOS 13 or later)

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/GuillaumeLeDev/iphoneShare.git
cd iphoneShare
```

### 2. Configure the secret token

The `.env` file holds the token used to authenticate incoming requests. It is listed in `.gitignore` and must never be committed.

```bash
cp .env.example .env
```

Generate a secure random token and paste it into `.env`:

```bash
openssl rand -hex 32
```

```env
SECRET_TOKEN=your_generated_token_here
```

### 3. Start the server

```bash
docker compose up -d --build
```

The container is configured with `restart: always` and will start automatically on system boot.

### 4. Verify the server is running

```bash
curl http://localhost:5005/health
# Expected response: {"status": "ok"}
```

---

## Usage

### Supported file formats

JPEG, PNG, HEIC, HEIF, GIF, WebP — maximum file size: **50 MB**

### Saved filenames

Files are named after the date and time of reception to avoid conflicts:

```
2026-04-17_14-32-01.jpg
```

They are saved to `~/Downloads/` on the host machine.

### API response

```json
{ "status": "ok", "filename": "2026-04-17_14-32-01.jpg" }
```

---

## Useful commands

```bash
docker compose logs -f            # Stream live logs
docker compose down               # Stop the server
docker compose up -d --build      # Rebuild and restart after changes
```

---

## Network configuration

### Static IP on the host machine

To ensure the iPhone always reaches the server at the same address, configure a **static DHCP lease** on the router for the host machine. Once set, the IP will never change.

### Allowed networks

For security, the server only accepts requests from the following subnets. Requests from any other IP are rejected with a `403` before the token is even checked:

| Network | Range |
|---|---|
| Home network (example) | `192.168.1.0/24` |
| Campus / other network | `10.109.0.0/16` |

Adjust these ranges in `server.py` to match your own network configuration.

---

## iOS Shortcut setup

> Screenshots of the Shortcut configuration are available below.

### Overview

The Shortcut is triggered from the iOS share sheet and performs the following steps:

1. Receives the photo from the share sheet
2. Reads the current Wi-Fi SSID
3. Selects the corresponding server IP address (or shows an error if the network is not recognized)
4. Sends the photo via `POST /upload` with the secret token in the `Authorization` header
5. Displays the server confirmation

### HTTP request parameters

| Parameter | Value |
|---|---|
| URL | `http://<HOST_IP>:5005/upload` |
| Method | `POST` |
| Header | `Authorization: Bearer <SECRET_TOKEN>` |
| Body | Multipart form-data, field `file` = the photo |

The token used in the Shortcut must match the value defined in the `.env` file on the server.

---

## Security

- The server rejects any request originating from an IP outside the configured subnets, before any token validation.
- The secret token is transmitted in the HTTP `Authorization` header. This server is intended for use on **trusted local networks only**.
- The `.env` file is excluded from version control via `.gitignore` and will never be committed to the repository.
- If the token is ever compromised, generate a new one with `openssl rand -hex 32`, update `.env`, restart the container with `docker compose up -d --build`, and update the token in the iOS Shortcut.
