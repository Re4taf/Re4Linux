#!/bin/sh

#####################################################################
# Cut (Move) Contents of a Source Folder (e.g. rootfs) to /home/container #
#####################################################################

set -eu

DEST_DIR="/home/container"
SRC_DIR="${1:-${SRC_DIR:-${DEST_DIR}/rootfs}}"

case "${SRC_DIR}" in
    /*) ;;
    *) SRC_DIR="${DEST_DIR}/${SRC_DIR}" ;;
esac

SRC_REAL=$(CDPATH= cd -- "${SRC_DIR}" 2>/dev/null && pwd -P || true)
DEST_REAL=$(CDPATH= cd -- "${DEST_DIR}" 2>/dev/null && pwd -P || true)

if [ -z "${SRC_REAL}" ] || [ ! -d "${SRC_REAL}" ]; then
    echo "[-] Source folder not found: ${SRC_DIR}" >&2
    exit 1
fi

if [ -z "${DEST_REAL}" ]; then
    mkdir -p "${DEST_DIR}"
    DEST_REAL=$(CDPATH= cd -- "${DEST_DIR}" && pwd -P)
fi

if [ "${SRC_REAL}" = "${DEST_REAL}" ]; then
    echo "[-] Source and destination cannot be the same directory (${DEST_REAL})." >&2
    exit 1
fi

case "${DEST_REAL}" in
    "${SRC_REAL}"/*)
        echo "[-] Destination (${DEST_REAL}) is inside source (${SRC_REAL}); refusing to cut." >&2
        exit 1
        ;;
esac

echo "[*] Cutting contents from: ${SRC_REAL}"
echo "[*] Moving into:          ${DEST_REAL}"

moved_count=0
for item in "${SRC_REAL}"/* "${SRC_REAL}"/.[!.]* "${SRC_REAL}"/..?*; do
    [ -e "${item}" ] || [ -L "${item}" ] || continue
    name=$(basename "${item}")
    target="${DEST_REAL}/${name}"

    if [ -e "${target}" ] || [ -L "${target}" ]; then
        if [ -d "${target}" ] && [ ! -L "${target}" ] && [ -d "${item}" ] && [ ! -L "${item}" ]; then
            if command -v cp >/dev/null 2>&1; then
                cp -a "${item}/." "${target}/"
                rm -rf "${item}"
            else
                mv "${item}"/* "${item}"/.[!.]* "${target}/" 2>/dev/null || true
                rmdir "${item}" 2>/dev/null || true
            fi
            moved_count=$((moved_count + 1))
        else
            rm -rf "${target}"
            mv "${item}" "${target}"
            moved_count=$((moved_count + 1))
        fi
    else
        mv "${item}" "${target}"
        moved_count=$((moved_count + 1))
    fi
done

echo "[+] Cut complete (${moved_count} top-level entries moved to ${DEST_REAL}/)."
