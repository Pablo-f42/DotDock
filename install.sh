#!/bin/bash
# Instala o actualiza DotDock compilándolo en esta Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/Pablo-f42/DotDock/main/install.sh | bash
#
# Sirve igual para quien nunca ha usado la Terminal que para quien ya tiene todo:
#   1. Si faltan las herramientas de desarrollo de Apple, abre su instalador y espera.
#   2. Descarga el código, o lo actualiza si ya estaba.
#   3. Compila, instala en Aplicaciones y abre la app.
#
# La app se compila aquí mismo y no viene de internet ya hecha, así que macOS la abre
# sin avisos de "desarrollador no identificado" y sin tocar ninguna protección.

set -uo pipefail

REPO_URL="https://github.com/Pablo-f42/DotDock.git"
SRC="${DOTDOCK_DIR:-$HOME/Developer/DotDock}"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*"; exit 1; }

# Las preguntas se leen de la terminal y no de la entrada: con `curl | bash` la
# entrada es el propio script.
ask() {
    local answer
    printf '%s (s/n) ' "$1"
    read -r answer < /dev/tty || return 1
    [[ "$answer" =~ ^[sSyY] ]]
}

# --- 1. macOS ----------------------------------------------------------------

version=$(sw_vers -productVersion)
if [ "${version%%.*}" -lt 14 ]; then
    fail "DotDock necesita macOS 14 o superior. Esta Mac tiene $version."
fi

# --- 2. Herramientas de desarrollo -------------------------------------------

tools_ready() { xcrun --find swiftc >/dev/null 2>&1 && xcrun --find git >/dev/null 2>&1; }

if ! tools_ready; then
    say "Hacen falta las herramientas de desarrollo de Apple (Command Line Tools)."
    echo "Se abrirá una ventana de Apple: pulsa «Instalar» y acepta la licencia."
    echo "La descarga tarda entre 5 y 20 minutos. Deja esta ventana abierta: el"
    echo "instalador sigue solo en cuanto terminen."
    xcode-select --install >/dev/null 2>&1

    waited=0
    until tools_ready; do
        sleep 10
        waited=$((waited + 10))
        [ $((waited % 60)) -eq 0 ] && printf '  esperando… %d min\n' $((waited / 60))
        [ "$waited" -ge 3600 ] && fail "Pasó una hora y las herramientas no aparecen. Instálalas con «xcode-select --install» y vuelve a pegar la línea de instalación."
    done
    say "Herramientas listas."
fi

# Xcode completo recién instalado no compila hasta aceptar su licencia.
if ! xcrun swiftc --version >/dev/null 2>&1; then
    xcrun swiftc --version
    fail "El compilador de Swift no arranca. Si el mensaje habla de la licencia de Xcode, ejecuta «sudo xcodebuild -license accept» y vuelve a intentarlo."
fi

# --- 3. Código ---------------------------------------------------------------

if [ -d "$SRC/.git" ]; then
    say "Actualizando el código en ${SRC}…"
    git -C "$SRC" pull --ff-only \
        || fail "No se pudo actualizar $SRC. Si cambiaste archivos ahí, guárdalos aparte o borra la carpeta y vuelve a intentarlo."
elif [ -e "$SRC" ]; then
    fail "$SRC ya existe y no es una copia de DotDock. Muévela o bórrala y vuelve a intentarlo."
else
    say "Descargando el código en ${SRC}…"
    mkdir -p "$(dirname "$SRC")"
    git clone --depth 1 "$REPO_URL" "$SRC" || fail "No se pudo descargar el código. ¿Hay conexión a internet?"
fi

# --- 4. Compilar e instalar --------------------------------------------------

# Sin permiso para escribir en /Applications (usuario no administrador), se instala
# en la carpeta de apps del usuario, que macOS también reconoce.
dest="/Applications"
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

build() {
    say "Compilando (uno o dos minutos)…"
    make -C "$SRC" install INSTALLED="$dest/DotDock.app" 2>&1 | tee "$log"
}

log=$(mktemp)
trap 'rm -f "$log"' EXIT

if ! build; then
    # El fallo conocido: herramientas viejas cuyo compilador no coincide con el SDK.
    if grep -q "SDK is not supported by the compiler" "$log"; then
        label=$(softwareupdate --list 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | tail -1)
        [ -n "$label" ] || fail "Las herramientas de desarrollo están desactualizadas. Actualízalas en Ajustes del Sistema → General → Actualización de software y vuelve a intentarlo."

        say "Las herramientas de desarrollo están desactualizadas y hay que poner «$label»."
        ask "¿Actualizarlas ahora? Te pedirá la contraseña de tu Mac." \
            || fail "Actualízalas en Ajustes del Sistema → General → Actualización de software y vuelve a intentarlo."
        sudo softwareupdate -i "$label" < /dev/tty || fail "No se pudieron actualizar las herramientas."
        build || fail "La compilación falló. Envía a quien te pasó DotDock lo que aparece arriba."
    else
        fail "La compilación falló. Envía a quien te pasó DotDock lo que aparece arriba."
    fi
fi

installed=$(defaults read "$dest/DotDock.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
say "Listo: DotDock $installed instalado en $dest y abierto."
echo "Acerca el cursor a la parte de arriba al centro de la pantalla."
echo "Para actualizar en el futuro, pega esta misma línea otra vez."
