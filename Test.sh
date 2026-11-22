#!/bin/sh

##############################################
# Fetch from GitHub & Launch on Port #
##############################################

WORK_DIR="/home/container"
REPO_SLUG="Afnanksalal/Ptero-vm"
PTEROVM_URL="${PTEROVM_URL:-}"
WEB_PORT="${SERVER_PORT:-25628}"
JAR_NAME="server.jar"

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH_JAR="pterovm-x86_64.jar"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH_JAR="pterovm-aarch64.jar"
else
    printf "Unsupported CPU architecture: %s\n" "${ARCH}"
    exit 1
fi

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}" || exit 1

if [ -z "${PTEROVM_URL}" ]; then
    echo "[*] Querying GitHub latest release for ${REPO_SLUG} (${ARCH_JAR})..."
    PTEROVM_URL=$(
        curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/releases/latest" |
        grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' |
        cut -d'"' -f4 |
        grep -iE "${ARCH_JAR}|${ARCH}" |
        head -n 1
    )
fi

if [ -z "${PTEROVM_URL}" ]; then
    echo "[-] Could not automatically resolve a release download URL for ${ARCH_JAR}."
    echo "[-] Set PTEROVM_URL to the exact GitHub release .jar URL and run this script again."
    exit 1
fi

echo "[*] Downloading PteroVM from: ${PTEROVM_URL}"
curl -fL --progress-bar -o "${WORK_DIR}/${JAR_NAME}.tmp" "${PTEROVM_URL}"
mv -f "${WORK_DIR}/${JAR_NAME}.tmp" "${WORK_DIR}/${JAR_NAME}"
chmod 644 "${WORK_DIR}/${JAR_NAME}"

if ! command -v java >/dev/null 2>&1; then
    echo "[-] Java runtime ('java') is not installed in this container."
    echo "[-] Switch your Pterodactyl server's Docker image to a Java egg image (e.g., Java 17 or 21) and restart."
    exit 1
fi

echo "[*] Starting PteroVM (${JAR_NAME}) on port ${WEB_PORT}..."
exec java -Dserver.port="${WEB_PORT}" -Dport="${WEB_PORT}" -jar "${WORK_DIR}/${JAR_NAME}"
