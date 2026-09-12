# syntax=docker/dockerfile:1

# ---------- Fuentes fijadas por hash ----------
ARG APPIMAGE_URL=https://github.com/Trinity-LA/Trinity-Launcher/releases/download/latest/Trinity_Launcher-x86_64.AppImage
ARG APPIMAGE_SHA256=
ARG MCPE_TAR_URL=https://huggingface.co/datasets/ccoffee20/trinity-installer/resolve/main/binarios.tar
ARG MCPE_TAR_SHA256=

# ---------- Etapa 1: AppImage (solo trinity + share + QML propio) ----------
FROM debian:13-slim AS appimage
ARG APPIMAGE_URL
ARG APPIMAGE_SHA256
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /w
RUN wget -qO trinity.AppImage "$APPIMAGE_URL" && chmod +x trinity.AppImage
RUN if [ -n "$APPIMAGE_SHA256" ]; then echo "$APPIMAGE_SHA256  trinity.AppImage" | sha256sum -c -; fi
RUN ./trinity.AppImage --appimage-extract >/dev/null 2>&1

# ---------- Etapa 2: binarios actualizados de mcpelauncher ----------
FROM debian:13-slim AS mcpe
ARG MCPE_TAR_URL
ARG MCPE_TAR_SHA256
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /w
RUN wget -qO binarios.tar "$MCPE_TAR_URL"
RUN if [ -n "$MCPE_TAR_SHA256" ]; then echo "$MCPE_TAR_SHA256  binarios.tar" | sha256sum -c -; fi
RUN mkdir bin && tar -xf binarios.tar -C bin

# ---------- Etapa 3: runtime Debian limpio + multiarch ----------
FROM debian:13-slim
ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y --no-install-recommends \
    # Qt6 del sistema + QML + WebEngine + plugins gráficos
    libqt6core6t64 libqt6gui6t64 libqt6widgets6t64 libqt6network6t64 libqt6qml6 libqt6quick6 \
    libqt6quickcontrols2-6 libqt6quicktemplates2-6 libqt6svg6 \
    libqt6webenginecore6-bin libqt6webengine6-data libqt6webenginequick6 \
    qml6-module-qtwebengine qml6-module-qtquick qml6-module-qtquick-controls \
    qml6-module-qtquick-templates qml6-module-qtquick-layouts qml6-module-qtquick-window \
    qml6-module-qtqml-workerscript \
    qt6-qpa-plugins qt6-wayland qt6-translations-l10n qt6-image-formats-plugins qt6-gtk-platformtheme \
    # GPU / X11 / Wayland / entrada
    libgl1 libegl1 libgles2 libglx0 libgldispatch0 libgl1-mesa-dri libvulkan1 libdrm2 libgbm1 \
    libx11-6 libxi6 libxext6 libxfixes3 libxcursor1 libxrandr2 libxss1 libxtst6 \
    libxkbcommon0 libxkbcommon-x11-0 libwayland-client0 libwayland-egl1 libwayland-cursor0 libdecor-0-0 \
    libevdev2 libudev1 libusb-1.0-0 libdbus-1-3 pciutils libpci3 \
    # Audio, red, varios
    libpulse0 libasound2t64 libcurl4t64 libssl3t64 libpng16-16t64 libzip5 libcups2t64 libunwind8 \
    fontconfig fonts-dejavu-core ca-certificates xdg-utils libgtk-3-0t64 \
    # ---- i386 para mcpelauncher-client ----
    libc6:i386 libstdc++6:i386 libgcc-s1:i386 zlib1g:i386 \
    libgl1:i386 libegl1:i386 libglx0:i386 libgldispatch0:i386 libgl1-mesa-dri:i386 \
    libx11-6:i386 libxi6:i386 libxext6:i386 libxfixes3:i386 libxcursor1:i386 libxrandr2:i386 \
    libxss1:i386 libxtst6:i386 libxkbcommon0:i386 libevdev2:i386 libudev1:i386 libdbus-1-3:i386 \
    libpulse0:i386 libasound2t64:i386 libcurl4t64:i386 libssl3t64:i386 libpng16-16t64:i386 \
    libwayland-client0:i386 libwayland-egl1:i386 \
    && rm -rf /var/lib/apt/lists/*

# ---------- Ensamblaje: binarios de trinity + recursos del AppImage ----------
COPY --from=appimage /w/squashfs-root /tmp/appdir
RUN R=/tmp/appdir/usr; [ -d "$R/bin" ] || R=/tmp/appdir; \
    # trinity (la UI) viene del AppImage
    install -Dm755 "$R/bin/trinity" /usr/local/bin/trinity; \
    # share/ completo: .desktop, iconos, metainfo, mcpelauncher/, etc.
    cp -a "$R/share/." /usr/share/ 2>/dev/null || true; \
    # QML propio de la app (excluimos módulos Qt* empaquetados)
    if [ -d "$R/qml" ]; then mkdir -p /usr/local/share/trinity/qml; \
        for d in "$R"/qml/*; do \
            case "$(basename "$d")" in Qt*) ;; *) cp -a "$d" /usr/local/share/trinity/qml/;; esac; \
        done; fi; \
    # Arreglar Exec del .desktop para que apunte al binario exportado
    sed -i 's|^Exec=.*|Exec=/usr/local/bin/trinity|; s|^TryExec=.*||' \
        /usr/share/applications/com.trench.trinity.launcher.desktop 2>/dev/null || true; \
    rm -rf /tmp/appdir

# ---------- Ensamblaje: TODOS los binarios de mcpelauncher desde HuggingFace ----------
COPY --from=mcpe /w/bin /tmp/mcpebin
RUN for b in mcpelauncher-client mcpelauncher-client86 msa-daemon mcpelauncher-extract \
             mcpelauncher-error mcpelauncher-webview; do \
        [ -e "/tmp/mcpebin/$b" ] && install -m755 "/tmp/mcpebin/$b" /usr/local/bin/ || true; \
    done; \
    rm -rf /tmp/mcpebin

# ---------- Guardarraíl: verificar libs faltantes ----------
RUN set -e; fail=0; \
    for b in /usr/local/bin/trinity /usr/local/bin/mcpelauncher-client /usr/local/bin/mcpelauncher-client86 \
             /usr/local/bin/mcpelauncher-webview /usr/local/bin/msa-daemon; do \
        [ -x "$b" ] || continue; \
        miss=$(ldd "$b" 2>/dev/null | grep 'not found' || true); \
        if [ -n "$miss" ]; then echo "FALTAN LIBS DEL SISTEMA en $b:"; echo "$miss"; fail=1; fi; \
    done; \
    [ "$fail" = 0 ] || exit 1

# ---------- Entorno estable (equivalente a los --env del flatpak) ----------
ENV QML_IMPORT_PATH=/usr/local/share/trinity/qml \
    QML_DISABLE_DISK_CACHE=1 \
    QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --ignore-gpu-blocklist" \
    QT_QUICK_CONTROLS_HOVER_ENABLED=1 \
    QT_QPA_PLATFORMTHEME=gtk3 \
    ALSA_CONFIG_PATH= \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs
