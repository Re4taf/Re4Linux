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

http_get() {
    url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$url"
    elif command -v node >/dev/null 2>&1; then
        node -e '
            const https = require("https");
            const url = process.argv[1];
            const fetchUrl = (target, hops = 0) => {
                if (hops > 5) { console.error("Too many redirects"); process.exit(1); }
                https.get(target, { headers: { "User-Agent": "pterovm-fetcher" } }, (res) => {
                    if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
                        return fetchUrl(new URL(res.headers.location, target).toString(), hops + 1);
                    }
                    if (res.statusCode < 200 || res.statusCode >= 300) {
                        console.error("HTTP status:", res.statusCode);
                        process.exit(1);
                    }
                    let data = "";
                    res.on("data", (chunk) => data += chunk);
                    res.on("end", () => process.stdout.write(data));
                }).on("error", (err) => { console.error(err.message); process.exit(1); });
            };
            fetchUrl(url);
        ' "$url"
    else
        echo "[-] Neither curl, wget, nor node is available to download files." >&2
        return 1
    fi
}

download_file() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$dest" "$url"
    elif command -v node >/dev/null 2>&1; then
        node -e '
            const fs = require("fs");
            const https = require("https");
            const url = process.argv[1];
            const dest = process.argv[2];
            const fetchToFile = (target, hops = 0) => {
                if (hops > 5) { console.error("Too many redirects"); process.exit(1); }
                https.get(target, { headers: { "User-Agent": "pterovm-fetcher" } }, (res) => {
                    if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
                        return fetchToFile(new URL(res.headers.location, target).toString(), hops + 1);
                    }
                    if (res.statusCode < 200 || res.statusCode >= 300) {
                        console.error("HTTP status:", res.statusCode);
                        process.exit(1);
                    }
                    const file = fs.createWriteStream(dest);
                    res.pipe(file);
                    file.on("finish", () => file.close(() => process.exit(0)));
                }).on("error", (err) => { console.error(err.message); process.exit(1); });
            };
            fetchToFile(url);
        ' "$url" "$dest"
    else
        echo "[-] Neither curl, wget, nor node is available to download files." >&2
        return 1
    fi
}

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}" || exit 1

if [ -z "${PTEROVM_URL}" ]; then
    echo "[*] Querying GitHub latest release for ${REPO_SLUG} (${ARCH_JAR})..."
    RELEASE_JSON=$(http_get "https://api.github.com/repos/${REPO_SLUG}/releases/latest") || exit 1
    PTEROVM_URL=$(
        printf "%s\n" "${RELEASE_JSON}" |
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
download_file "${PTEROVM_URL}" "${WORK_DIR}/${JAR_NAME}.tmp" || exit 1
mv -f "${WORK_DIR}/${JAR_NAME}.tmp" "${WORK_DIR}/${JAR_NAME}"
chmod 644 "${WORK_DIR}/${JAR_NAME}"

if ! command -v java >/dev/null 2>&1; then
    echo "[-] Java runtime ('java') is not installed in this container."
    echo "[-] Switch your Pterodactyl server's Docker image to a Java egg image (e.g., Java 17 or 21) and restart."
    exit 1
fi

echo "[*] Starting PteroVM (${JAR_NAME}) on port ${WEB_PORT}..."
exec java -Dserver.port="${WEB_PORT}" -Dport="${WEB_PORT}" -jar "${WORK_DIR}/${JAR_NAME}"
