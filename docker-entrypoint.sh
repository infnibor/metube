#!/bin/sh
set -eu

PUID="${UID:-$PUID}"
PGID="${GID:-$PGID}"
AUDIO_DOWNLOAD_DIR="${AUDIO_DOWNLOAD_DIR:-$DOWNLOAD_DIR}"

echo "Setting umask to ${UMASK}"
umask "${UMASK}"

echo "Creating directories"
mkdir -p "${DOWNLOAD_DIR}" "${AUDIO_DOWNLOAD_DIR}" "${STATE_DIR}" "${TEMP_DIR}"

export PYTHONNOUSERSITE=1
export PATH="/usr/local/bin:$PATH"

clean_ytdlp() {
    echo "Cleaning old yt-dlp..."

    python3 -m pip uninstall -y yt-dlp || true

    rm -f /usr/local/bin/yt-dlp || true
    rm -rf /usr/local/lib/python3.13/site-packages/yt_dlp* || true
}

install_sabr() {
    echo "Installing SABR fork..."

    python3 -m pip install --no-cache-dir --force-reinstall \
        --no-deps \
        "git+https://github.com/coletdjnz/yt-dlp-dev@feat/youtube/sabr"
}

verify() {
    echo "yt-dlp binary:"
    which yt-dlp || true

    echo "yt-dlp version:"
    yt-dlp --version || true

    echo "yt-dlp python source:"
    python3 -c "import yt_dlp; print(yt_dlp.__file__)"
}

force_sabr() {
    clean_ytdlp
    install_sabr
    hash -r
    verify
}

run_supervised() {
    while true; do
        "$@" &
        pid=$!

        trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null' TERM INT
        wait "$pid"
        code=$?

        trap - TERM INT

        if [ "$code" -eq 42 ]; then
            echo "Restart request -> reinstall SABR"
            force_sabr || true
            continue
        fi

        return "$code"
    done
}

nightly_enabled() {
    [ -n "${YTDL_NIGHTLY_UPDATE_TIME:-}" ]
}

disable_nightly_for_non_root() {
    if nightly_enabled; then
        echo "Disabling nightly updates (non-root)"
        unset YTDL_NIGHTLY_UPDATE_TIME
    fi
}

echo "Forcing SABR yt-dlp on startup..."
force_sabr || true

if [ "$(id -u)" -eq 0 ] && [ "$(id -g)" -eq 0 ]; then

    chown -R "${PUID}:${PGID}" /app "${DOWNLOAD_DIR}" "${AUDIO_DOWNLOAD_DIR}" "${STATE_DIR}" "${TEMP_DIR}" || true

    echo "Starting BgUtils POT Provider"
    gosu "${PUID}:${PGID}" bgutil-pot server >/tmp/bgutil-pot.log 2>&1 &

    echo "Starting MeTube"
    run_supervised gosu "${PUID}:${PGID}" python3 app/main.py

else
    disable_nightly_for_non_root

    echo "Starting BgUtils POT Provider"
    bgutil-pot server >/tmp/bgutil-pot.log 2>&1 &

    run_supervised python3 app/main.py
fi
