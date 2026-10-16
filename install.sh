#!/bin/bash
# Lou — installation en une ligne, sans alerte Gatekeeper :
#   curl -fsSL https://getlou.app/install.sh | bash
#
set -euo pipefail

main() {
BASE_URL="${LOU_BASE_URL:-https://github.com/DjimmyL/lou-releases/releases/latest/download}"
APP_NAME="Lou"

say()  { printf '\033[1m🦦 %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

if [ "$(uname)" != "Darwin" ] && [ "${LOU_TEST:-}" != "1" ]; then
  fail "Lou fonctionne uniquement sur Mac."
fi

# --- 1. Quel Mac ? (sysctl détecte aussi une puce Apple quand le Terminal tourne sous Rosetta)
ARCH="${LOU_ARCH:-}"
if [ -z "${ARCH}" ]; then
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] || [ "$(uname -m)" = "arm64" ]; then
    ARCH=arm64
  else
    ARCH=x64
  fi
fi
case "${ARCH}" in
  arm64) ASSET="Lou-mac-apple-silicon.zip"; LABEL="puce Apple" ;;
  x64)   ASSET="Lou-mac-intel.zip";         LABEL="processeur Intel" ;;
  *)     fail "Type de Mac inconnu : ${ARCH}" ;;
esac

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lou-install.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

# --- 2. Téléchargement + vérification
say "Téléchargement de Lou pour Mac avec ${LABEL}…"
curl -fL --progress-bar --retry 3 -o "${TMP}/${ASSET}" "${BASE_URL}/${ASSET}" \
  || fail "Téléchargement impossible. Vérifie ta connexion Internet et réessaie."
curl -fsSL --retry 3 -o "${TMP}/${ASSET}.sha256" "${BASE_URL}/${ASSET}.sha256" \
  || fail "Empreinte de vérification introuvable. Réessaie dans quelques minutes."

EXPECTED="$(awk '{print $1; exit}' "${TMP}/${ASSET}.sha256" | tr 'A-F' 'a-f')"
ACTUAL="$(sha256 "${TMP}/${ASSET}")"
[ -n "${EXPECTED}" ] && [ "${EXPECTED}" = "${ACTUAL}" ] \
  || fail "Le fichier téléchargé est incomplet ou abîmé (empreinte différente). Rien n'a été installé : relance la commande."
say "Fichier vérifié."

# --- 3. Décompression (ditto garde les liens internes de l'app ; unzip en test sur Linux)
mkdir "${TMP}/x"
if command -v ditto >/dev/null 2>&1; then ditto -x -k "${TMP}/${ASSET}" "${TMP}/x"
else unzip -q "${TMP}/${ASSET}" -d "${TMP}/x"; fi
[ -d "${TMP}/x/${APP_NAME}.app" ] || fail "Archive inattendue : ${APP_NAME}.app est introuvable."

# --- 4. Où installer ?
if [ -n "${LOU_APPS_DIR:-}" ]; then
  DIR="${LOU_APPS_DIR}"
elif [ -w /Applications ] && { [ ! -e "/Applications/${APP_NAME}.app" ] || [ -w "/Applications/${APP_NAME}.app" ]; }; then
  DIR=/Applications
else
  DIR="${HOME}/Applications"
fi
mkdir -p "${DIR}"
DEST="${DIR}/${APP_NAME}.app"

# --- 5. Fermer Lou si elle tourne, remplacer en gardant une copie de secours
if [ "${LOU_TEST:-}" != "1" ] && pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  say "Fermeture de Lou…"
  osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "${APP_NAME}" >/dev/null 2>&1 || break; sleep 0.5; done
  pkill -x "${APP_NAME}" 2>/dev/null || true
fi

BACKUP=""
if [ -e "${DEST}" ]; then
  BACKUP="${DIR}/.${APP_NAME}.app.previous"
  rm -rf "${BACKUP}"
  mv "${DEST}" "${BACKUP}"
fi
if ! mv "${TMP}/x/${APP_NAME}.app" "${DEST}"; then
  [ -n "${BACKUP}" ] && mv "${BACKUP}" "${DEST}"
  fail "Impossible d'écrire dans ${DIR}. Ton ancienne version de Lou est intacte."
fi
[ -n "${BACKUP}" ] && rm -rf "${BACKUP}"

# Par sécurité (rien ne devrait être marqué, curl ne pose pas ce drapeau)
command -v xattr >/dev/null 2>&1 && xattr -dr com.apple.quarantine "${DEST}" 2>/dev/null || true

say "Lou est installée dans ${DIR}."

# --- 6. Ouvrir
if [ "${LOU_TEST:-}" != "1" ]; then
  open "${DEST}"
  say "Lou s'ouvre : cherche la petite loutre dans la barre des menus, en haut à droite de l'écran."
fi
}

main "$@"
