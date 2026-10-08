APP_NAME  := DotDock
VERSION   := 0.2.3
BUILD_DIR := build
APP       := $(BUILD_DIR)/$(APP_NAME).app
BIN       := $(APP)/Contents/MacOS/$(APP_NAME)
ICON      := Resources/AppIcon.icns

SOURCES := $(shell find Sources -name '*.swift')
SDK     := $(shell xcrun --show-sdk-path)

# Universal: sin el slice de x86_64 la app no arranca en Macs Intel.
ARCHS       := arm64 x86_64
DEPLOYMENT  := macos14.0
SWIFT_FLAGS := -swift-version 5 -sdk $(SDK) -O \
               -framework AppKit -framework SwiftUI -framework UniformTypeIdentifiers

INSTALLED := /Applications/$(APP_NAME).app
ZIP       := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip
DMG       := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg

# Distribución firmada. Requiere Apple Developer Program (99 USD/año).
#   DEV_ID       nombre exacto del certificado: security find-identity -v -p codesigning
#   KEYCHAIN_ID  perfil guardado con: xcrun notarytool store-credentials
DEV_ID      ?= Developer ID Application: $(shell whoami)
KEYCHAIN_ID ?= dotdock-notary
ENTITLEMENTS := Resources/$(APP_NAME).entitlements

.PHONY: all run stop clean install uninstall icon dist sign notarize dmg share release sandbox

all: $(APP)

$(APP): $(SOURCES) Resources/Info.plist $(ICON)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@for arch in $(ARCHS); do \
		echo "  compilando $$arch"; \
		swiftc $(SWIFT_FLAGS) -target $$arch-apple-$(DEPLOYMENT) \
			-o $(BUILD_DIR)/$(APP_NAME)-$$arch $(SOURCES) || exit 1; \
	done
	@lipo -create -output $(BIN) $(addprefix $(BUILD_DIR)/$(APP_NAME)-,$(ARCHS))
	@rm -f $(addprefix $(BUILD_DIR)/$(APP_NAME)-,$(ARCHS))
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@cp $(ICON) $(APP)/Contents/Resources/
	@codesign --force --deep --sign - $(APP)
	@touch $(APP)
	@echo "$(APP) — $$(lipo -archs $(BIN))"

# El icono se versiona: sólo hace falta regenerarlo si cambia el diseño.
icon:
	@swiftc -O -o $(BUILD_DIR)/makeicon Tools/makeicon.swift
	@mkdir -p $(BUILD_DIR)
	@$(BUILD_DIR)/makeicon $(BUILD_DIR)
	@iconutil -c icns $(BUILD_DIR)/AppIcon.iconset -o $(ICON)
	@echo "Generado $(ICON)"

run: all stop
	@open $(APP)

stop:
	@pkill -x $(APP_NAME) || true

clean:
	@rm -rf $(BUILD_DIR)

# INSTALLED se puede cambiar al llamar: install.sh lo usa para instalar en
# ~/Applications cuando el usuario no puede escribir en /Applications.
# El arranque al iniciar sesión sólo funciona desde una ruta estable: macOS rechaza
# registrar un bundle que vive en un directorio de compilación.
install: all stop
	@rm -rf $(INSTALLED)
	@ditto $(APP) $(INSTALLED)
	@codesign --force --deep --sign - $(INSTALLED)
	@open $(INSTALLED)
	@echo "Instalado en $(INSTALLED)"

uninstall: stop
	@rm -rf $(INSTALLED)
	@echo "Eliminado $(INSTALLED)"

# `ditto` y no `zip`: preserva los metadatos del bundle y la firma.
dist: all
	@rm -f $(ZIP)
	@ditto -c -k --keepParent $(APP) $(ZIP)
	@echo
	@echo "Paquete: $(ZIP) ($$(du -h $(ZIP) | cut -f1))"
	@echo
	@echo "La app va firmada ad-hoc, así que Gatekeeper la bloquea en otro Mac."
	@echo "Quien la reciba debe, una sola vez:"
	@echo "  1. Descomprimir y mover DotDock.app a /Aplicaciones"
	@echo "  2. xattr -dr com.apple.quarantine /Applications/DotDock.app"
	@echo "  3. Abrirla normalmente"
	@echo
	@echo "Para evitar ese paso hace falta firmar y notarizar: make release"

# ---------------------------------------------------------------------------
# Distribución firmada
# ---------------------------------------------------------------------------

# `--options runtime` (hardened runtime) y `--timestamp` son obligatorios para que
# Apple acepte la notarización. Los frameworks se firman antes que el bundle: la firma
# va de dentro hacia fuera o el sello exterior queda inválido.
sign: all
	@codesign --force --options runtime --timestamp \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(DEV_ID)" $(APP)
	@codesign --verify --strict --verbose=2 $(APP)
	@echo "Firmado con: $(DEV_ID)"

notarize: sign
	@rm -f $(ZIP)
	@ditto -c -k --keepParent $(APP) $(ZIP)
	@echo "Subiendo a Apple (tarda entre 1 y 15 minutos)…"
	@xcrun notarytool submit $(ZIP) --keychain-profile "$(KEYCHAIN_ID)" --wait
	@xcrun stapler staple $(APP)
	@xcrun stapler validate $(APP)
	@spctl -a -vvv -t exec $(APP)

# DMG con enlace a /Aplicaciones: es el gesto que la gente ya conoce.
dmg: all
	@rm -rf $(BUILD_DIR)/dmgroot $(DMG)
	@mkdir -p $(BUILD_DIR)/dmgroot
	@cp -R $(APP) $(BUILD_DIR)/dmgroot/
	@cp Resources/LEEME.txt $(BUILD_DIR)/dmgroot/
	@ln -s /Applications $(BUILD_DIR)/dmgroot/Aplicaciones
	@hdiutil create -volname "$(APP_NAME)" -srcfolder $(BUILD_DIR)/dmgroot \
		-ov -format UDZO $(DMG) >/dev/null
	@rm -rf $(BUILD_DIR)/dmgroot
	@echo "Imagen: $(DMG) ($$(du -h $(DMG) | cut -f1))"

# Paquete para pasarle a alguien. Se limpia la cuarentena del propio DMG para que no
# se la herede la app al copiarla desde una USB o una carpeta compartida.
share: dmg
	@xattr -cr $(DMG)
	@echo
	@echo "Listo: $(DMG)"
	@echo
	@echo "Quien lo reciba verá un aviso de \"Apple no puede comprobar...\" la primera"
	@echo "vez. Es esperable: la firma es válida pero la app no está notarizada."
	@echo "Se desbloquea en Configuración del Sistema > Privacidad y seguridad >"
	@echo "Seguridad > \"Abrir de todas formas\". Sólo una vez, sin Terminal."
	@echo
	@echo "El LEEME.txt dentro del DMG lo explica paso a paso."

# El DMG se firma y se sella aparte: el ticket del .app no cubre el contenedor.
release: notarize dmg
	@codesign --force --timestamp --sign "$(DEV_ID)" $(DMG)
	@xcrun notarytool submit $(DMG) --keychain-profile "$(KEYCHAIN_ID)" --wait
	@xcrun stapler staple $(DMG)
	@echo
	@echo "Listo para publicar: $(DMG)"

# Variante sandboxed, sólo para comprobar si la app sobreviviría a la Mac App Store.
# No se distribuye: es un experimento. Ver docs/app-store.md, fase 2.
sandbox: all
	@codesign --force --sign - \
		--entitlements Resources/$(APP_NAME)-sandbox.entitlements $(APP)
	@codesign -d --entitlements :- $(APP) 2>/dev/null | grep -q app-sandbox \
		&& echo "Firmada CON sandbox" || echo "ERROR: no se aplicó el sandbox"
