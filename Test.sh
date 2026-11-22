#!/bin/sh

########################################################
# Test.sh - Fetch PteroVM Jar (curl/wget/node fallback) #
########################################################

set -eu

WORK_DIR="${PWD:-/home/container}"
SERVER_JARFILE="${SERVER_JARFILE:-server.jar}"
DOWNLOAD_URL="${DOWNLOAD_URL:-}"
WEB_PORT="${SERVER_PORT:-25628}"
VNC_PASSWORD="${VNC_PASSWORD:-}"

case "$(uname -m)" in
    x86_64) ARCH=x86_64 ;;
    aarch64|arm64) ARCH=aarch64 ;;
    riscv64) ARCH=riscv64 ;;
    *)
        echo "PteroVM is x86_64, aarch64, or riscv64. This machine is $(uname -m)."
        exit 1
        ;;
esac

download_file() {
    url="$1"
    dest="$2"
    tmp_dest="${dest}.partial"

    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 -o "${tmp_dest}" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --timeout=15 -O "${tmp_dest}" "${url}"
    elif command -v node >/dev/null 2>&1; then
        node -e '
            const fs = require("fs");
            const https = require("https");
            const http = require("http");
            const url = process.argv[1];
            const dest = process.argv[2];

            const fetchToFile = (target, hops = 0) => {
                if (hops > 8) {
                    console.error("Too many redirects");
                    process.exit(1);
                }
                const parsed = new URL(target);
                const client = parsed.protocol === "http:" ? http : https;
                const req = client.get(parsed, {
                    headers: { "User-Agent": "pterovm-installer" },
                    timeout: 15000
                }, (res) => {
                    if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
                        const nextUrl = new URL(res.headers.location, parsed.toString()).toString();
                        return fetchToFile(nextUrl, hops + 1);
                    }
                    if (res.statusCode < 200 || res.statusCode >= 300) {
                        console.error("HTTP status:", res.statusCode);
                        process.exit(1);
                    }
                    const out = fs.createWriteStream(dest);
                    res.pipe(out);
                    out.on("finish", () => out.close(() => process.exit(0)));
                    out.on("error", (err) => {
                        console.error(err.message);
                        process.exit(1);
                    });
                });
                req.on("timeout", () => {
                    req.destroy();
                    console.error("Request timed out");
                    process.exit(1);
                });
                req.on("error", (err) => {
                    console.error(err.message);
                    process.exit(1);
                });
            };

            fetchToFile(url);
        ' "${url}" "${tmp_dest}"
    else
        echo "[-] Neither curl, wget, nor node is available to download PteroVM." >&2
        exit 1
    fi

    if [ ! -s "${tmp_dest}" ]; then
        rm -f "${tmp_dest}"
        echo "[-] Downloaded file is empty: ${dest}" >&2
        exit 1
    fi

    mv -f "${tmp_dest}" "${dest}"
}

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

if [ -n "${DOWNLOAD_URL}" ]; then
    echo "Downloading PteroVM"
    download_file "${DOWNLOAD_URL}" "${SERVER_JARFILE}"
elif [ -f "${SERVER_JARFILE}" ]; then
    echo "Keeping the existing ${SERVER_JARFILE}"
else
    URL="https://github.com/Afnanksalal/Ptero-vm/releases/download/v2.1-${ARCH}/pterovm-${ARCH}.jar"
    echo "Downloading PteroVM for ${ARCH}"
    download_file "${URL}" "${SERVER_JARFILE}"
fi

echo "PteroVM jar is ready."

if command -v java >/dev/null 2>&1; then
    echo "Starting PteroVM (${SERVER_JARFILE}) on port ${WEB_PORT}..."
    if [ -n "${VNC_PASSWORD}" ]; then
        exec java -Dserver.port="${WEB_PORT}" -Dport="${WEB_PORT}" -Dvnc.password="${VNC_PASSWORD}" -Xms128M -XX:MaxRAMPercentage=95.0 -jar "${SERVER_JARFILE}"
    else
        exec java -Dserver.port="${WEB_PORT}" -Dport="${WEB_PORT}" -Xms128M -XX:MaxRAMPercentage=95.0 -jar "${SERVER_JARFILE}"
    fi
else
    echo "Note: 'java' is not installed in this container image; ${SERVER_JARFILE} is saved in ${WORK_DIR}."
fi
