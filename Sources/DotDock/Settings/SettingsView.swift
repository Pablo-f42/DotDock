import ServiceManagement
import SwiftUI

struct SettingsView: View {

    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var settings: AppSettings
    @ObservedObject var media: MediaController
    let blob: BlobModel?

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: sectionBinding) { section in
                Label {
                    Text(section.title)
                } icon: {
                    SettingsIcon(symbol: section.symbol, tint: section.tint)
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            detail
                .navigationTitle(navigation.section.title)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    /// La lista pide una selección opcional; la sección nunca queda vacía.
    private var sectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { navigation.section },
            set: { if let section = $0 { navigation.section = section } }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section {
        case .general: GeneralSettings(settings: settings)
        case .modules: ModulesSettings(settings: settings)
        case .music: MusicSettings(settings: settings, media: media)
        case .dot: DotSettings(settings: settings, blob: blob)
        case .about: AboutSettings()
        }
    }
}

/// Icono blanco sobre un cuadro de color, como en Ajustes del Sistema.
struct SettingsIcon: View {

    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
    }
}

// MARK: - General

private struct GeneralSettings: View {

    @ObservedObject var settings: AppSettings

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Arrancar al iniciar sesión", isOn: launchBinding)
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Mostrar icono en la barra de menús", isOn: $settings.showsMenuBarIcon)
            } footer: {
                Text("El engrane del panel abre estos mismos ajustes, así que el icono es opcional.")
                    .settingsFootnote()
            }

            Section("Abrir el panel") {
                Picker("Se abre", selection: $settings.openTrigger) {
                    ForEach(OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)

                Picker("Velocidad", selection: $settings.hoverSpeed) {
                    ForEach(HoverSpeed.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(settings.openTrigger != .hover)
            }

            Section {
                Picker("Mostrar DotDock", selection: $settings.screenPolicy) {
                    ForEach(ScreenPolicy.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Pantallas")
            } footer: {
                Text("En pantallas sin muesca, el panel aparece como una pastilla negra arriba al centro.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    /// El estado real vive en macOS: se lee de `SMAppService` y, si el registro
    /// falla, el interruptor vuelve a su sitio y se explica por qué.
    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { wanted in
                do {
                    if wanted {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchError = nil
                } catch {
                    launchError = "macOS no lo permitió: \(error.localizedDescription). "
                        + "Instala la app con make install y vuelve a intentarlo."
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }
}

// MARK: - Módulos

private struct ModulesSettings: View {

    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(Array(settings.moduleOrder.enumerated()), id: \.element) { index, module in
                    moduleRow(module, index: index)
                }
            } header: {
                Text("Pestañas")
            } footer: {
                Text("Apaga las que no uses y ordénalas con las flechas. Siempre queda al menos una.")
                    .settingsFootnote()
            }

            Section {
                Picker("Al abrir, mostrar", selection: $settings.startModule) {
                    Text("La última pestaña que usaste").tag(DockModule?.none)
                    Divider()
                    ForEach(settings.visibleModules) { module in
                        Text(module.title).tag(DockModule?.some(module))
                    }
                }
            }

            Section("Pomodoro") {
                minutesStepper("Concentración", value: $settings.focusMinutes, range: 5...90, step: 5)
                minutesStepper("Descanso corto", value: $settings.shortBreakMinutes, range: 1...30, step: 1)
                minutesStepper("Descanso largo", value: $settings.longBreakMinutes, range: 5...60, step: 5)
                Toggle("Sonar al terminar cada fase", isOn: $settings.pomodoroSound)
            }

            Section {
                Picker("Copias que recuerda", selection: $settings.clipboardCapacity) {
                    ForEach(AppSettings.clipboardCapacityChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Portapapeles")
            } footer: {
                Text("Sólo texto. Se guarda en memoria y se borra al salir: nunca toca el disco.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    private func moduleRow(_ module: DockModule, index: Int) -> some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: module.symbol, tint: settings.isModuleEnabled(module) ? .blue : .gray)

            Text(module.title)
                .foregroundStyle(settings.isModuleEnabled(module) ? .primary : .secondary)

            Spacer()

            HStack(spacing: 2) {
                moveButton("chevron.up", disabled: index == 0) { move(from: index, by: -1) }
                moveButton("chevron.down", disabled: index == settings.moduleOrder.count - 1) {
                    move(from: index, by: 1)
                }
            }

            Toggle("", isOn: Binding(
                get: { settings.isModuleEnabled(module) },
                set: { settings.setModule(module, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            // La última que queda no se puede apagar.
            .disabled(settings.isModuleEnabled(module) && settings.visibleModules.count == 1)
        }
    }

    private func moveButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
    }

    private func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard settings.moduleOrder.indices.contains(target) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            settings.moduleOrder.swapAt(index, target)
        }
    }

    private func minutesStepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) min")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Música

private struct MusicSettings: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject var media: MediaController

    var body: some View {
        Form {
            Section {
                Toggle("Carátula y visualizador con el panel cerrado", isOn: $settings.showsLiveActivity)
            } footer: {
                Text("Mientras suena algo, la muesca se ensancha y muestra la carátula a la izquierda y el visualizador a la derecha.")
                    .settingsFootnote()
            }

            Section("Visualizador") {
                preview

                Picker("Estilo", selection: $settings.visualizerStyle) {
                    ForEach(VisualizerStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Color", selection: $settings.visualizerTint) {
                    ForEach(VisualizerTint.allCases) { Text($0.title).tag($0) }
                }

                if settings.visualizerTint == .custom {
                    ColorPicker("Color personalizado", selection: $settings.customTint, supportsOpacity: false)
                }

                if settings.visualizerTint == .artwork {
                    Text(media.artworkColor == nil
                         ? "Cuando suene algo con carátula a color, el visualizador tomará su tono. Mientras, se ve blanco."
                         : "Este es el tono de la carátula que suena ahora.")
                        .settingsFootnote()
                }
            }
            .disabled(!settings.showsLiveActivity)
        }
        .formStyle(.grouped)
    }

    /// Una muesca de muestra con el visualizador tal como se verá.
    private var preview: some View {
        HStack {
            Spacer()
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.15))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: 18, height: 18)
                    .frame(width: 34)

                Spacer().frame(width: 110)

                Visualizer(style: settings.visualizerStyle, tint: tint, isAnimating: true)
                    .frame(width: 34, height: 28)
            }
            .frame(height: 30)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                    .fill(.black)
            )
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var tint: Color {
        switch settings.visualizerTint {
        case .white: .white.opacity(0.85)
        case .artwork: media.artworkColor ?? .white.opacity(0.85)
        case .spotify: Color(red: 0.12, green: 0.84, blue: 0.38)
        case .custom: settings.customTint
        }
    }
}

// MARK: - Dot

private struct DotSettings: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject private var design = BlobDesign.shared
    let blob: BlobModel?

    @State private var previewMood: BlobMood = .normal
    @State private var holdsPose = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.blobEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mostrar a Dot")
                        Text("La gotita con ojos que se asoma bajo la muesca.")
                            .settingsFootnote()
                    }
                }

                HStack {
                    Picker("Vista previa", selection: $previewMood) {
                        ForEach(Self.previewMoods, id: \.mood) { Text($0.title).tag($0.mood) }
                    }
                    Button("Asomarse") { blob?.replayForDesign(mood: previewMood) }
                }

                Toggle("Mantenerla asomada mientras ajustas", isOn: $holdsPose)
                    .onChange(of: holdsPose) { _, hold in blob?.setDesignHold(hold) }
            }

            Group {
                Section {
                    Picker("Se asoma", selection: triggerBinding) {
                        Text("Al azar, cuando DotDock está en reposo").tag(0)
                        Divider()
                        ForEach(AppSettings.blobIntervalChoices, id: \.self) { minutes in
                            Text(minutes == 1 ? "Cada minuto" : "Cada \(minutes) minutos").tag(minutes)
                        }
                    }

                    if settings.blobTrigger == .resting {
                        Picker("Personalidad", selection: $settings.blobPersonality) {
                            ForEach(BlobPersonality.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        Text(settings.blobPersonality.detail).settingsFootnote()
                    }
                } header: {
                    Text("Por tiempo")
                } footer: {
                    Text("En reposo quiere decir con el panel cerrado y sin música ni pomodoro.")
                        .settingsFootnote()
                }

                Section {
                    ForEach(BlobReaction.allCases) { reaction in
                        reactionRow(reaction)
                    }
                } header: {
                    Text("Por acciones")
                } footer: {
                    Text("Con ▶ ves en la muesca la expresión que hará.")
                        .settingsFootnote()
                }

                Section("Comportamiento") {
                    Toggle("Seguir el cursor con los ojos", isOn: $settings.blobFollowsCursor)
                    Toggle("Esconderse si acercas el cursor", isOn: $settings.blobIsShy)
                }

                Section("Apariencia") {
                    eyeColorPicker

                    slider("Ancho", \.bodyWidth, 16...70)
                    slider("Alto", \.height, 10...44)
                    slider("Unión con la muesca", \.fillet, 0...16)
                    slider("Ancho de los ojos", \.eyeWidth, 2...12, step: 0.5)
                    slider("Alto de los ojos", \.eyeHeight, 2...16, step: 0.5)
                    slider("Separación de los ojos", \.eyeSpacing, 0...24, step: 0.5)
                    slider("Altura de los ojos", \.eyeLevel, 0.1...0.9, step: 0.05)

                    HStack {
                        Spacer()
                        Button("Restablecer forma") { design.proportions = BlobProportions() }
                    }
                }
            }
            .disabled(!settings.blobEnabled)
        }
        .formStyle(.grouped)
        .onDisappear {
            holdsPose = false
            blob?.setDesignHold(false)
        }
    }

    private func reactionRow(_ reaction: BlobReaction) -> some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: reaction.symbol, tint: .indigo)

            VStack(alignment: .leading, spacing: 1) {
                Text(reaction.title)
                Text(reaction.detail).settingsFootnote()
            }

            Spacer()

            Button {
                blob?.replayForDesign(mood: reaction.mood)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.indigo)
            }
            .buttonStyle(.borderless)
            .help("Ver la expresión: \(reaction.detail.lowercased())")

            Toggle("", isOn: Binding(
                get: { settings.blobReactions.contains(reaction) },
                set: { settings.setReaction(reaction, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private static let previewMoods: [(mood: BlobMood, title: String)] = [
        (.normal, "Normal"), (.happy, "Feliz"), (.sleepy, "Dormida"), (.worried, "Preocupada"),
        (.music, "Bailando"), (.wink, "Guiño"), (.gulp, "Tragando"), (.hello, "Saludando")
    ]

    /// 0 es "en reposo"; cualquier otro número, cada tantos minutos.
    private var triggerBinding: Binding<Int> {
        Binding(
            get: {
                if case .every(let minutes) = settings.blobTrigger { minutes } else { 0 }
            },
            set: { settings.blobTrigger = $0 > 0 ? .every(minutes: $0) : .resting }
        )
    }

    private var eyeColorPicker: some View {
        HStack {
            Text("Color de los ojos")
            Spacer()
            HStack(spacing: 8) {
                ForEach(EyeColor.allCases) { option in
                    Button {
                        settings.blobEyeColor = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                            .padding(3)
                            .overlay(
                                Circle().strokeBorder(
                                    settings.blobEyeColor == option ? Color.accentColor : .clear,
                                    lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                }
            }
        }
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<BlobProportions, CGFloat>,
        _ range: ClosedRange<CGFloat>,
        step: CGFloat = 1
    ) -> some View {
        let value = design.proportions[keyPath: keyPath]

        return LabeledContent(title) {
            HStack {
                // Se redondea a mano en vez de pasar `step`: con paso, el deslizador
                // dibuja una marca por valor y se llena de puntos.
                Slider(
                    value: Binding(
                        get: { design.proportions[keyPath: keyPath] },
                        set: { design.proportions[keyPath: keyPath] = ($0 / step).rounded() * step }
                    ),
                    in: range
                )
                Text(Double(value).formatted(.number.precision(.fractionLength(0...2))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

// MARK: - Acerca de

private struct AboutSettings: View {

    private static let repository = URL(string: "https://github.com/Pablo-f42/DotDock")!
    private static let updateCommand = "cd ~/Developer/DotDock && git pull && make install"

    @State private var copied = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)

                    Text("DotDock")
                        .font(.title2.weight(.semibold))

                    Text("Versión \(version)")
                        .foregroundStyle(.secondary)

                    Link("Código en GitHub", destination: Self.repository)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                HStack {
                    Text(Self.updateCommand)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button(copied ? "Copiado" : "Copiar") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.updateCommand, forType: .string)
                        copied = true
                    }
                }
            } header: {
                Text("Actualizar")
            } footer: {
                Text("Pégalo en la Terminal. Si clonaste el proyecto en otra carpeta, cambia la ruta.")
                    .settingsFootnote()
            }

            Section {
                LabeledContent("Autor", value: "Pablo Faz")
                LabeledContent("Licencia", value: "MIT")
            }
        }
        .formStyle(.grouped)
    }
}

private extension View {
    func settingsFootnote() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
