import os
import logging
import ipaddress
from datetime import datetime
from flask import Flask, request, jsonify

app = Flask(__name__)

SECRET_TOKEN = os.environ.get("SECRET_TOKEN", "")
UPLOAD_DIR = "/downloads"
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50 MB

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".webp"}

ALLOWED_NETWORKS = [
    ipaddress.ip_network("192.168.1.0/24"),  # Freebox maison
    ipaddress.ip_network("10.109.0.0/16"),   # Campus IONIS
]


def is_allowed_ip(ip: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
        return any(addr in net for net in ALLOWED_NETWORKS)
    except ValueError:
        return False


@app.route("/upload", methods=["POST"])
def upload():
    client_ip = request.remote_addr
    if not is_allowed_ip(client_ip):
        log.warning("403 - IP non autorisee: %s", client_ip)
        return jsonify({"status": "error", "message": "Forbidden"}), 403

    auth = request.headers.get("Authorization", "")
    if not auth == f"Bearer {SECRET_TOKEN}":
        log.warning("Unauthorized upload attempt from %s", request.remote_addr)
        return jsonify({"status": "error", "message": "Unauthorized"}), 401

    if not request.files:
        log.warning("400 - no files in request. form keys: %s, content-type: %s",
                    list(request.form.keys()), request.content_type)
        return jsonify({"status": "error", "message": "No file provided"}), 400

    # Accept any field name (iOS Shortcuts may not use "file")
    file = request.files.get("file") or next(iter(request.files.values()))

    if file.filename == "":
        log.warning("400 - empty filename. files keys: %s", list(request.files.keys()))
        return jsonify({"status": "error", "message": "Empty filename"}), 400

    original_ext = os.path.splitext(file.filename)[1].lower()
    if original_ext not in ALLOWED_EXTENSIONS:
        original_ext = ".jpg"

    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    filename = f"{timestamp}{original_ext}"
    save_path = os.path.join(UPLOAD_DIR, filename)

    file.seek(0, 2)
    size = file.tell()
    file.seek(0)
    if size > MAX_FILE_SIZE:
        return jsonify({"status": "error", "message": "File too large (max 50 MB)"}), 413

    file.save(save_path)
    log.info("Photo saved: %s (%d bytes) from %s", filename, size, request.remote_addr)

    return jsonify({"status": "ok", "filename": filename})


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    app.run(host="0.0.0.0", port=5005)
