#!/bin/sh

########################################################
# Manually Extract server.jar into /home/container/    #
########################################################

set -eu

WORK_DIR="/home/container"
JAR_FILE="${WORK_DIR}/server.jar"
OUT_DIR="${WORK_DIR}"

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

if [ ! -f "${JAR_FILE}" ]; then
    echo "[-] ${JAR_FILE} not found." >&2
    exit 1
fi

if command -v unzip >/dev/null 2>&1; then
    echo "[*] Extracting ${JAR_FILE} using unzip -> ${OUT_DIR}/"
    unzip -oq "${JAR_FILE}" -d "${OUT_DIR}"
elif command -v jar >/dev/null 2>&1; then
    echo "[*] Extracting ${JAR_FILE} using jar -> ${OUT_DIR}/"
    jar xf "${JAR_FILE}"
elif command -v python3 >/dev/null 2>&1; then
    echo "[*] Extracting ${JAR_FILE} using python3 -> ${OUT_DIR}/"
    python3 -c '
import os, sys, zipfile

jar_path, out_dir = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(jar_path, "r") as zf:
    for info in zf.infolist():
        target = os.path.normpath(os.path.join(out_dir, info.filename))
        if not target.startswith(os.path.abspath(out_dir) + os.sep) and target != os.path.abspath(out_dir):
            continue
        if info.is_dir() or info.filename.endswith("/"):
            os.makedirs(target, exist_ok=True)
        else:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with zf.open(info, "r") as src, open(target, "wb") as dst:
                dst.write(src.read())
            mode = (info.external_attr >> 16) & 0o777
            if mode:
                try:
                    os.chmod(target, mode)
                except OSError:
                    pass
' "${JAR_FILE}" "${OUT_DIR}"
elif command -v node >/dev/null 2>&1; then
    echo "[*] Extracting ${JAR_FILE} using node -> ${OUT_DIR}/"
    node -e '
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const jarPath = process.argv[1];
const outDir = process.argv[2];
const buf = fs.readFileSync(jarPath);

// Locate End of Central Directory (EOCD) signature: 0x06054b50
let eocd = -1;
const minPos = Math.max(0, buf.length - 65557);
for (let i = buf.length - 22; i >= minPos; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
        const commentLen = buf.readUInt16LE(i + 20);
        if (i + 22 + commentLen === buf.length) {
            eocd = i;
            break;
        }
    }
}
if (eocd === -1) {
    console.error("[-] Invalid ZIP/JAR: EOCD not found");
    process.exit(1);
}

const totalEntries = buf.readUInt16LE(eocd + 10);
let cdOffset = buf.readUInt32LE(eocd + 16);
const resolvedOut = path.resolve(outDir);

for (let n = 0; n < totalEntries; n++) {
    if (cdOffset + 46 > buf.length || buf.readUInt32LE(cdOffset) !== 0x02014b50) {
        console.error("[-] Invalid central directory entry at", cdOffset);
        process.exit(1);
    }
    const method = buf.readUInt16LE(cdOffset + 10);
    const compSize = buf.readUInt32LE(cdOffset + 20);
    const nameLen = buf.readUInt16LE(cdOffset + 28);
    const extraLen = buf.readUInt16LE(cdOffset + 30);
    const commentLen = buf.readUInt16LE(cdOffset + 32);
    const extAttr = buf.readUInt32LE(cdOffset + 38);
    const localOffset = buf.readUInt32LE(cdOffset + 42);

    const rawName = buf.subarray(cdOffset + 46, cdOffset + 46 + nameLen).toString("utf8");
    cdOffset += 46 + nameLen + extraLen + commentLen;

    if (!rawName || rawName.includes("..")) continue;
    const target = path.resolve(resolvedOut, rawName);
    if (!target.startsWith(resolvedOut + path.sep) && target !== resolvedOut) continue;

    if (rawName.endsWith("/")) {
        fs.mkdirSync(target, { recursive: true });
        continue;
    }

    if (localOffset + 30 > buf.length || buf.readUInt32LE(localOffset) !== 0x04034b50) {
        continue;
    }
    const lhNameLen = buf.readUInt16LE(localOffset + 26);
    const lhExtraLen = buf.readUInt16LE(localOffset + 28);
    const dataStart = localOffset + 30 + lhNameLen + lhExtraLen;
    const dataEnd = dataStart + compSize;
    if (dataEnd > buf.length) continue;

    fs.mkdirSync(path.dirname(target), { recursive: true });
    const rawData = buf.subarray(dataStart, dataEnd);
    let outData;
    if (method === 0) {
        outData = rawData;
    } else if (method === 8) {
        outData = zlib.inflateRawSync(rawData);
    } else {
        console.warn("[!] Skipping unsupported compression method", method, "for", rawName);
        continue;
    }

    fs.writeFileSync(target, outData);
    const mode = (extAttr >>> 16) & 0o777;
    if (mode) {
        try { fs.chmodSync(target, mode); } catch (_) {}
    }
}
' "${JAR_FILE}" "${OUT_DIR}"
else
    echo "[-] No extraction tool (unzip, jar, python3, node) available." >&2
    exit 1
fi

echo "[+] Done! Extracted contents directly into: ${OUT_DIR}/"
ls -la "${OUT_DIR}"
