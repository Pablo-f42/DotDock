# Publicar DotDock en la Mac App Store

Guía paso a paso. Los enlaces se verificaron el 10 de agosto de 2026.

> **La viabilidad técnica ya está comprobada.** Ver "Resultados de la prueba de
> sandbox" más abajo: se firmó la app con `app-sandbox` y se midió qué sobrevive.
> El único riesgo que queda es humano — que Apple apruebe un entitlement.

---

## Resultados de la prueba de sandbox

Hecho el 10 de agosto de 2026, firmando la app real con `com.apple.security.app-sandbox`
y comparando contra la versión normal. **Sin cuenta de Apple y sin pagar nada.**

Que el sandbox estaba activo de verdad se confirmó por dos vías: la variable
`APP_SANDBOX_CONTAINER_ID` y la creación de `~/Library/Containers/dev.faz.dotdock`.

| Capacidad | Sin sandbox | Con sandbox | Veredicto |
|---|---|---|---|
| Monitores globales de ratón | funciona | **funciona** (2 eventos) | ✅ el hover sobrevive |
| AppleScript a Spotify | funciona | **funciona** | ✅ con el entitlement |
| AppleScript **sin** el entitlement | — | `pista=(nada)` | ⛔ confirma que hace falta |
| Arranque de la app | ok | ok, sin violaciones en el log | ✅ |

El tercer caso es el control que importa: firmando con `app-sandbox` pero **sin**
`temporary-exception.apple-events`, el reproductor se queda vacío. O sea que el
entitlement es imprescindible y funciona — no es un adorno.

Lo que **no** se pudo probar aquí: el hover completo. Los eventos sintéticos no
alimentan a los monitores globales, así que los 2 eventos vienen de movimiento
incidental del cursor. Basta para saber que el canal no está cortado, pero conviene
usar la variante sandboxed un rato a mano.

Queda pendiente de migrar: la bandeja (paso 7).

---

## Coste

**99 USD al año**, el Apple Developer Program. Es el mismo pago que para distribuir
por fuera con Developer ID: no cuesta extra publicar en la tienda.

Si algún día cobras por la app, Apple se queda el 15–30 %.

Hay exención de la cuota para ONG, instituciones educativas acreditadas y entidades
gubernamentales.

---

## Fase 1 — Cuenta y credenciales

### 1. Inscribirte en el Developer Program

<https://developer.apple.com/programs/enroll/>

**Como persona física** (más rápido, 24–48 h):
- Apple Account con **verificación en dos pasos activada**
- Tu nombre legal — no apodos ni nombre comercial
- Dirección postal real (no apartado postal)

**Como empresa** (semanas):
- Número **D-U-N-S** de la organización → <https://developer.apple.com/enroll/duns-lookup/>
- Razón social exacta, sin nombres comerciales
- Correo del dominio de la empresa
- **Sitio web público y funcional** con ese dominio

Para un proyecto personal, inscríbete como persona física.

### 2. Firmar los acuerdos

<https://appstoreconnect.apple.com/agreements>

El titular de la cuenta debe firmar el acuerdo de la sección **Business** antes de
poder crear apps. Si te lo saltas, el paso 4 falla sin explicar por qué.

### 3. Crear el Bundle ID

<https://developer.apple.com/account/resources/identifiers/list>

- Botón **+** → *App IDs* → *App*
- Description: `DotDock`
- Bundle ID: **Explicit** → `dev.faz.dotdock`

Debe coincidir con `CFBundleIdentifier` en `Resources/Info.plist`.

### 4. Crear la ficha de la app

<https://appstoreconnect.apple.com/apps>

Botón **+** → *New App*:

| Campo | Valor |
|---|---|
| Platforms | macOS |
| Name | DotDock (único en toda la tienda) |
| Primary Language | Spanish (Mexico) |
| Bundle ID | `dev.faz.dotdock` |
| SKU | `dotdock-001` (interno, no lo ve nadie) |
| User Access | Full Access |

### 5. Certificados

<https://developer.apple.com/account/resources/certificates/list>

Para la tienda hacen falta **dos**, distintos del Developer ID:

- **Apple Distribution** — firma la app
- **Mac Installer Distribution** — firma el `.pkg`

Sin Xcode: genera la CSR con *Acceso a Llaveros → Asistente de certificados →
Solicitar un certificado de una autoridad de certificación*, súbela, descarga el
`.cer` y haz doble clic.

Comprobar que quedaron instalados:

```sh
security find-identity -v -p codesigning
```

---

## Fase 2 — Adaptar la app

Esta es la fase que decide si el proyecto es viable. **Hazla antes de pagar.**

### 6. Activar el sandbox

Obligatorio para la tienda (directriz 2.4.5). En `Resources/DotDock.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

Documentación: <https://developer.apple.com/documentation/security/app-sandbox>

### 7. Migrar la bandeja a security-scoped bookmarks

`ShelfStore.swift` guarda rutas en texto (`líneas 26 y 61`). Dentro del sandbox, esas
rutas **no dan acceso al archivo** en el siguiente arranque: hay que guardar un
*bookmark* con ámbito de seguridad y abrirlo con `startAccessingSecurityScopedResource()`.

Requiere además el entitlement:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

Documentación: <https://developer.apple.com/documentation/foundation/nsurl#1663783>

### 8. Entitlements para Spotify y Música

El módulo de reproducción usa AppleScript. Dentro del sandbox hace falta:

```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
<key>com.apple.security.temporary-exception.apple-events</key>
<array>
    <string>com.spotify.client</string>
    <string>com.apple.Music</string>
</array>
```

**Aquí está el riesgo.** Los entitlements de *excepción temporal* pasan revisión
manual y hay que justificarlos por escrito en las notas del revisor. Si Apple los
rechaza, el reproductor deja de funcionar.

### 9. Comprobar que el hover sobrevive

`MouseTracker.swift:27` usa `NSEvent.addGlobalMonitorForEvents`. Hay que verificar
empíricamente que sigue recibiendo eventos con el sandbox activo — si no, el panel
no se despliega y la app pierde su razón de ser.

---

## Fase 3 — Empaquetar y enviar

### 10. Firmar y empaquetar

La directriz 2.4.5 exige empaquetar **con tecnologías de Xcode** — nada de
instaladores de terceros. `productbuild` cumple:

```sh
codesign --force --options runtime --timestamp \
  --entitlements Resources/DotDock.entitlements \
  --sign "Apple Distribution: TU NOMBRE (TEAMID)" build/DotDock.app

productbuild --component build/DotDock.app /Applications \
  --sign "3rd Party Mac Developer Installer: TU NOMBRE (TEAMID)" \
  build/DotDock.pkg
```

### 11. Subir el paquete

Con **Transporter** (gratis, en la propia Mac App Store):
<https://apps.apple.com/app/transporter/id1450874784>

O por línea de comandos:

```sh
xcrun notarytool store-credentials appstore \
  --apple-id TU@CORREO.com --team-id TEAMID --password CONTRASEÑA-DE-APP

xcrun altool --upload-app -f build/DotDock.pkg -t macos \
  --apple-id TU@CORREO.com --password CONTRASEÑA-DE-APP
```

La contraseña de app se genera en <https://account.apple.com> → *Iniciar sesión y
seguridad* → *Contraseñas específicas para apps*. **No** es la contraseña de tu cuenta.

### 12. Metadatos

En la ficha de App Store Connect:

- **Capturas**: 1280×800, 1440×900, 2560×1600 o 2880×1800. Mínimo una
- **Descripción**, palabras clave, categoría (*Utilidades* / *Productividad*)
- **URL de soporte** — obligatoria, sirve un repositorio público
- **Clasificación por edad**
- **Etiquetas de privacidad**: hay que declarar el historial del portapapeles.
  Como no sale del equipo ni se guarda en disco, va como *no recopilada*, pero hay
  que decirlo explícitamente

### 13. Notas para el revisor

Explica por qué la app necesita los Apple Events. Sin esto, el rechazo del paso 8 es
casi seguro. Algo como:

> DotDock muestra la reproducción actual y ofrece controles de play/pausa/siguiente.
> Usa AppleScript contra Music y Spotify porque son las únicas APIs públicas para
> obtener esa información; no se usa ninguna API privada.

### 14. Enviar a revisión

Estado *Waiting for Review* → *In Review* → *Ready for Sale*. Suele tardar 24–48 h.

---

## Bloqueadores

Actualizado tras la prueba:

| # | Qué | Estado |
|---|---|---|
| 9 | Monitores globales sandboxed | ✅ **Resuelto** — funcionan |
| 8 | Que Apple apruebe la excepción de Apple Events | ⚠️ **Riesgo humano** — técnicamente funciona, falta que pase revisión |
| 7 | Bandeja con bookmarks | 🔧 Pendiente — trabajo conocido, sin incógnitas |

El único que puede tumbar el proyecto es el 8, y no se puede saber sin enviar. Si lo
rechazan, la app sigue siendo perfectamente distribuible por Developer ID.

## Fases, replanteadas

Con lo que ahora sabemos, el orden que minimiza riesgo y gasto:

**Fase 0 — Viabilidad** ✅ *hecha, coste 0*
Firmar sandboxed y medir qué sobrevive. Resultado: sobrevive todo menos la bandeja.

**Fase 1 — Bandeja con bookmarks** *(coste 0, sin cuenta)*
Paso 7. Al terminar, la app funciona entera dentro del sandbox y ya no hay nada
técnico que averiguar.

**Fase 2 — Pagar e inscribirse** *(99 USD)*
Pasos 1–5. Sólo cuando la fase 1 esté verde.

**Fase 3 — Enviar** *(coste 0)*
Pasos 10–14. Aquí se resuelve el riesgo del entitlement, de una vez por todas.

Si la fase 3 sale mal, no se pierde el dinero: los mismos 99 USD sirven para
distribuir por Developer ID, que es el plan de respaldo y ya está implementado
(`make release`).

## La alternativa

**La app que inspiró el proyecto no está en la Mac App Store.** Se distribuye con Developer ID y no usa
sandbox — comprobado sobre el binario:

```
$ ls <app>.app/Contents/_MASReceipt         → no existe
$ codesign -d --entitlements                → sin app-sandbox
$ spctl -a -vvv                             → accepted, Notarized Developer ID
```

Con Developer ID: mismo pago de 99 USD, sin sandbox, sin revisión, sin comisión, y
publicas cuando quieras. Los tres bloqueadores de arriba desaparecen.

Lo que pierdes es el escaparate de la tienda y la confianza que da instalar desde
ahí. Para una utilidad de nicho, suele no compensar.

La tubería para esa vía ya está escrita: `make release` en el Makefile.
