# DotDock

App de macOS que convierte la muesca de la pantalla en un panel desplegable:
reproductor de Spotify y Música, bandeja de archivos, historial del portapapeles,
uso de Claude, pomodoro y calculadora. Y una gotita con ojos que de vez en cuando
se asoma.

## Instalar en tu Mac

Necesitas **macOS 14 o superior**. Funciona en Apple Silicon e Intel. En Macs sin
muesca, el panel aparece como una pastilla negra arriba al centro.

La app se compila en tu Mac a partir del código, así que macOS no la bloquea como
app de "desarrollador no identificado".

### Opción A: pídeselo a tu asistente de terminal

Abre **Claude Code** (`claude`) o **Codex CLI** (`codex`) en la Terminal y pega
este prompt. Tiene que ser un asistente que pueda ejecutar comandos: el chat web de
Claude o ChatGPT no puede instalar nada en tu Mac.

```text
Instala la app DotDock en mi Mac compilándola desde su código fuente:

1. Comprueba que tengo macOS 14 o superior (sw_vers) y las Command Line Tools
   de Xcode (xcode-select -p). Si faltan, ejecuta xcode-select --install, avísame
   y espera a que termine la instalación antes de seguir.
2. Clona https://github.com/Pablo-f42/DotDock.git en ~/Developer/DotDock.
   Si la carpeta ya existe, entra y haz git pull.
3. Lee el README.md del proyecto, sobre todo la sección "Toolchain".
4. Ejecuta make install. Si falla por un SDK o compilador de Swift incompatible,
   sigue lo que dice la sección "Toolchain" y vuelve a intentarlo.
5. Confirma que /Applications/DotDock.app existe y que la app está corriendo
   (pgrep -x DotDock).

No uses sudo ni cambies nada fuera de esa carpeta sin preguntarme antes. Al
terminar, dime qué hiciste y cómo se usa la app.
```

### Opción B: a mano

```sh
xcode-select --install          # sólo si nunca instalaste las Command Line Tools
git clone https://github.com/Pablo-f42/DotDock.git ~/Developer/DotDock
cd ~/Developer/DotDock
make install                    # compila, copia a /Applications y la abre
```

Si `make install` falla con un error de SDK, mira la sección *Toolchain* más abajo.

### Primeros pasos

- Acerca el cursor a la muesca y el panel se despliega. El engrane del panel abre
  **Ajustes** y tiene la opción de salir.
- **Música:** la primera vez, el reproductor ofrece un botón para autorizar el
  acceso a Spotify o Música. macOS pide el permiso una sola vez.
- **Ajustes** tiene cinco secciones:
  - **General:** arrancar al iniciar sesión, icono en la barra de menús (apagado
    por defecto), abrir al pasar el cursor o con clic, y en qué pantallas aparece.
  - **Módulos:** activar, desactivar y ordenar las pestañas; duración del
    pomodoro; cuántas copias guarda el portapapeles.
  - **Música:** carátula con el panel cerrado y estilo y color del visualizador,
    incluido el color de la carátula que suena.
  - **Dot:** cada cuánto se asoma la gotita, a qué acciones reacciona, cómo se
    comporta y cómo se ve.
  - **Acerca de:** versión y cómo actualizar.

### Actualizar

Tus ajustes se conservan al actualizar. La versión que tienes aparece en
**Ajustes → Acerca de**.

En la Terminal:

```sh
cd ~/Developer/DotDock && git pull && make install
```

O pídeselo a Claude Code o Codex CLI:

```text
Actualiza la app DotDock que tengo en ~/Developer/DotDock: entra a la carpeta,
haz git pull y ejecuta make install. Si make install falla por un SDK o
compilador de Swift incompatible, sigue la sección "Toolchain" del README y
vuelve a intentarlo. Al terminar, confirma que DotDock está corriendo
(pgrep -x DotDock) y dime qué versión quedó instalada según
/Applications/DotDock.app/Contents/Info.plist.
```

`make install` cierra la versión que esté abierta, instala la nueva y la abre.

### Desinstalar

```sh
cd ~/Developer/DotDock && make uninstall
```

## Requisitos para desarrollar

macOS 14+ y un toolchain de Swift consistente (ver *Toolchain* abajo).

## Build

```sh
make          # compila build/DotDock.app (universal: arm64 + x86_64)
make run      # compila, mata la instancia anterior y abre la app
make install  # copia a /Applications
make dist     # empaqueta build/DotDock-<versión>.zip
make icon     # regenera Resources/AppIcon.icns
make stop
make clean
```

No usa Xcode ni SwiftPM: `swiftc` compila los fuentes y el Makefile arma el bundle a
mano. Menos ceremonia y funciona sólo con Command Line Tools.

La app corre como `LSUIElement` (sin icono en el Dock). Para salir, usa el engrane
del panel o `make stop`.

### Inspeccionar el panel abierto

```sh
DOTDOCK_DEBUG_OPEN=home  build/DotDock.app/Contents/MacOS/DotDock
DOTDOCK_DEBUG_OPEN=shelf build/DotDock.app/Contents/MacOS/DotDock
DOTDOCK_DEBUG_OPEN=live  build/DotDock.app/Contents/MacOS/DotDock
```

Arranca en el estado indicado y **sin** el tracker del cursor, que si no lo cerraría en
cuanto el ratón se mueva por cualquier punto de la pantalla. `live` fuerza además el
live activity sin necesidad de darle a play. Útil para capturar la ventana aislada del
resto del escritorio:

```sh
screencapture -x -o -l<window-id> shot.png
```

### Ver la gotita sin esperar

```sh
DOTDOCK_DEBUG_BLOB=normal  build/DotDock.app/Contents/MacOS/DotDock
DOTDOCK_DEBUG_BLOB=happy   build/DotDock.app/Contents/MacOS/DotDock
# también sleepy, worried, music, wink, gulp, hello
```

Se asoma en cuanto arranca, con el ánimo pedido. En **Ajustes → Dot** hay una vista
previa de cada ánimo y deslizadores para su forma, con la opción de dejarla asomada
mientras se ajusta.

### Abrir Ajustes en una sección

```sh
DOTDOCK_DEBUG_SETTINGS=dot build/DotDock.app/Contents/MacOS/DotDock
# general, modules, music, dot, about
```

## Repartir un .zip ya compilado

`make dist` produce un zip de ~750 KB con el binario universal (funciona en Apple
Silicon e Intel).

En el equipo de destino, **una sola vez**:

```sh
# 1. Descomprimir y mover DotDock.app a /Aplicaciones, luego:
xattr -dr com.apple.quarantine /Applications/DotDock.app
```

Sin ese comando macOS se niega a abrirla: *"DotDock está dañada y no se puede
abrir"*. No está dañada — es Gatekeeper.

### Por qué hace falta ese paso

La app va firmada **ad-hoc** (`codesign --sign -`), que es gratis pero no vale para
distribuir. Gatekeeper la evalúa como `rejected`:

```
$ spctl -a -vvv -t exec /Applications/DotDock.app
/Applications/DotDock.app: rejected
```

Para que se instale con doble clic y sin comandos hace falta firmarla con un
certificado **Developer ID** y notarizarla en Apple, lo que exige el Apple Developer
Program: **99 USD al año**. Es el único punto del proyecto que cuesta dinero. Todo lo
demás — compilador, SDK, firma ad-hoc, AppleScript — es gratis.

Mientras tanto, el zip más el comando de arriba funciona perfectamente; es lo que hacen
casi todos los proyectos de código abierto pequeños para macOS.

## Toolchain

Este proyecto no compila si el SDK y el compilador de Swift no coinciden de versión.
Síntoma:

```
error: failed to build module 'CoreFoundation'; this SDK is not supported by the
compiler (the SDK is built with 'Apple Swift version 6.2 …', while this compiler is
'Apple Swift version 6.2.4 …')
```

Se arregla actualizando Command Line Tools:

```sh
softwareupdate --list
sudo softwareupdate -i "Command Line Tools for Xcode 26.5-26.5"
```

O instalando Xcode completo y apuntando ahí:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Arquitectura

```
Sources/DotDock/
├── DotDockApp.swift        Punto de entrada (NSApplication, .accessory)
├── AppDelegate.swift       Ensambla paneles, tracker, menús y Ajustes
├── Core/
│   ├── AppSettings.swift   Todas las preferencias, guardadas en UserDefaults
│   ├── DockGeometry.swift  Mide la muesca de cada pantalla
│   ├── DockModel.swift     Estado (closed/peek/open), medidas y animaciones
│   ├── DockStores.swift    Datos compartidos entre pantallas
│   └── Timers.swift        Temporizadores que no se congelan con menús abiertos
├── Window/
│   ├── DockPanel.swift       NSPanel flotante sobre la barra de menús
│   ├── DockHostingView.swift Hit-test y destino de arrastre de la bandeja
│   └── MouseTracker.swift    Monitores globales de NSEvent para el hover
├── UI/
│   ├── DockRootView.swift    Raíz de SwiftUI
│   ├── DockShape.swift       Silueta con esquinas superiores cóncavas
│   ├── LiveActivityView.swift Carátula y visualizador con el panel cerrado
│   ├── ModuleSwitcher.swift  Barra de pestañas
│   ├── StatusIcon.swift      Icono de la barra de menús
│   └── Theme.swift, PieProgress.swift
├── Settings/
│   ├── SettingsWindow.swift  Ventana de Ajustes
│   └── SettingsView.swift    Sus cinco secciones
├── Blob/                   Dot, la gotita: modelo, coreografía, dibujo y forma
└── Modules/                Reproductor, bandeja, portapapeles, uso de Claude,
                            pomodoro y calculadora
```

### Decisiones que importan

**La ventana nunca cambia de tamaño.** El `NSPanel` mide siempre el máximo desplegado
más margen; lo que crece es el contenido SwiftUI. Animar el frame de una `NSWindow` se
ve entrecortado y desincronizado con la animación interna.

**El hit-test es manual.** Como la ventana es enorme y transparente, `DockHostingView`
devuelve `nil` para cualquier punto fuera del `interactiveRect` del modelo. Sin eso, la
app se tragaría todos los clics de la parte superior de la pantalla.

**El hover se detecta con monitores globales de `NSEvent`, no con `onHover`.** El panel
no es la ventana activa, y las tracking areas de SwiftUI pierden eventos cuando el foco
está en otra app. Los monitores de ratón no requieren permisos de accesibilidad (los de
teclado sí).

**Las esquinas superiores son cóncavas** y se dibujan *fuera* del rect de la forma. Es
el detalle que hace que el panel parezca una extensión de la muesca y no una ventana
pegada debajo. Cualquier contenedor de `DockShape` necesita margen horizontal.

**El arrastre se maneja en AppKit, no con `.onDrop`.** Durante una sesión de arrastre
macOS deja de entregar eventos de ratón a las otras apps: el `MouseTracker` no ve nada,
el panel nunca se abre por hover y el área de drop se queda del tamaño cerrado.
`DockHostingView` se registra como destino de arrastre y abre el panel desde
`draggingEntered`.

**La calculadora no usa `NSExpression`.** `NSExpression(format:)` lanza excepciones de
Objective-C ante entrada malformada, y Swift no las puede capturar — el proceso muere.
Una calculadora recibe expresiones a medio escribir en cada pulsación, así que ese
camino es un crash garantizado. `ExpressionParser` es un descenso recursivo que
devuelve `nil` en vez de explotar.

**Sólo la calculadora toma el teclado.** `DockPanel` se vuelve ventana clave únicamente
cuando el módulo abierto lo pide, y lo devuelve al cerrarse: un panel que retiene el
foco deja a la app en primer plano sin poder escribir. AppKit no expone "renuncia a ser
key", así que se hace con `orderOut` + `orderFrontRegardless`.

## Estado

Hecho:

- Detección de la muesca por pantalla, con pill sintético en pantallas sin muesca
- Panel flotante en todos los espacios, sin robar foco
- Estados closed → peek → open con springs y radios interpolados
- Bandeja de archivos con drag in y drag out
- Reposicionamiento al conectar/desconectar monitores

- Now Playing de Music y Spotify vía AppleScript, con carátula y controles
- Live activity: carátula y visualizador (o cuenta atrás del pomodoro) en reposo
- Pomodoro con ciclos de 25/5/15 y descanso largo cada 4 sesiones
- Calculadora con parser propio (ver abajo) y copiado con Enter
- Selector de módulos y arranque al iniciar sesión

Pendiente:

- "Live activity": mostrar carátula y visualizador a los lados del panel cerrado
- Preferencias y persistencia de la bandeja entre reinicios
- Más módulos: calendario, batería, AirDrop
- Soporte multi-monitor simultáneo (hoy sólo la pantalla con muesca)

## Por qué el Now Playing va por AppleScript y no por MediaRemote

Desde macOS 15.4, `MediaRemote` exige el entitlement privado `com.apple.mediaremote.*`,
que Apple no otorga a terceros. Firmar con Developer ID **no** desbloquea nada.

Comprobado en macOS 26.5 con un binario sin entitlements: `dlopen` del framework
funciona, `dlsym` encuentra `MRMediaRemoteGetNowPlayingInfo`, el callback responde —
pero el diccionario vuelve con **0 claves**, aun con una pista cargada en Spotify. Sin
rechazo explícito en los logs del sistema: simplemente devuelve vacío.

El costo de AppleScript es la cobertura: sólo apps con diccionario de scripting. Music
y Spotify sí; navegadores, Podcasts y apps de Electron no.

Si algún día hace falta cobertura universal, la alternativa conocida es delegar en un
binario de plataforma firmado por Apple que sí pueda cargar `MediaRemote` y transmitir
el resultado. Es API privada: se rompe con cada actualización de macOS y cierra la
puerta a la Mac App Store. Encaja como otra implementación detrás de la misma interfaz,
sin tocar la UI.
