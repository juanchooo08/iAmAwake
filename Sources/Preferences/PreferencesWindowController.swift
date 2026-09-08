import AppKit
import AwakeCore
import SwiftUI

/// Ventana de preferencias. Lee y escribe unicamente via `PreferencesStoring`.
@MainActor
public final class PreferencesWindowController: NSWindowController {

    private let viewModel: PreferencesViewModel

    public init(store: PreferencesStoring) {
        let viewModel = PreferencesViewModel(store: store)
        self.viewModel = viewModel

        let hosting = NSHostingController(rootView: PreferencesView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Preferencias de iAmAwake"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 420, height: 560))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }

    /// Trae la ventana al frente activando la app (la app vive en la barra de menu,
    /// asi que sin `activate` la ventana aparece detras de todo).
    public func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Guarda de batería") {
                Toggle("Desarmar cuando la batería esté baja", isOn: $viewModel.batteryGuardEnabled)
                HStack {
                    Text("Umbral")
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.batteryThreshold) },
                            set: { viewModel.batteryThreshold = Int($0.rounded()) }
                        ),
                        in: Double(PreferencesSnapshot.batteryThresholdRange.lowerBound)
                            ... Double(PreferencesSnapshot.batteryThresholdRange.upperBound),
                        step: 1
                    )
                    Text("\(viewModel.batteryThreshold) %")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .disabled(!viewModel.batteryGuardEnabled)
            }

            Section("Guarda térmica") {
                Toggle("Desarmar cuando la Mac se caliente", isOn: $viewModel.thermalGuardEnabled)
                Picker("Techo térmico", selection: $viewModel.thermalCeiling) {
                    ForEach(PreferencesViewModel.selectableCeilings, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .disabled(!viewModel.thermalGuardEnabled)
                Text("A partir de este nivel iAmAwake se desarma. Con la tapa cerrada el calor no se disipa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Guarda de red") {
                Toggle("Desarmar cuando se caiga la conexión", isOn: $viewModel.networkGuardEnabled)
                Picker("Esperar", selection: $viewModel.networkGraceSeconds) {
                    ForEach(PreferencesViewModel.selectableGraces, id: \.self) { seconds in
                        Text(PreferencesViewModel.graceLabel(seconds)).tag(seconds)
                    }
                }
                .disabled(!viewModel.networkGuardEnabled)
                Text("""
                    Sin internet no hay descargas ni Claude Code que cuidar. La espera \\
                    evita que un salto de WiFi te desarme la sesión.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Animación") {
                Toggle("Animar el párpado al cerrar y abrir la tapa", isOn: $viewModel.animationsEnabled)
                Text("""
                    Al cerrar casi no se alcanza a ver: la pantalla se apaga a los \
                    0,2 s de que el sistema se entera. La que se ve es la de abrir, \
                    que te dice cuánto aguantó.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Atajo de teclado") {
                HStack {
                    Text(viewModel.isCapturingHotkey ? "Pulsá la combinación…" : viewModel.hotkeyDisplayString)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 90, alignment: .leading)
                    Spacer()
                    Button(viewModel.isCapturingHotkey ? "Cancelar" : "Cambiar…") {
                        if viewModel.isCapturingHotkey {
                            viewModel.cancelCapturingHotkey()
                        } else {
                            viewModel.beginCapturingHotkey()
                        }
                    }
                    Button("Restaurar ⌃⌥S") { viewModel.resetHotkeyToDefault() }
                }
                if viewModel.isCapturingHotkey {
                    Text("Necesita al menos un modificador. Esc cancela.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
