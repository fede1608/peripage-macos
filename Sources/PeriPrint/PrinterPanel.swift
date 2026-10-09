import PeriPageKit
import PeriRender
import SwiftUI

struct PrinterPanel: View {
    @Environment(AppModel.self) private var model
    @State private var showScan = false
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.selectedDevice?.name ?? model.printer?.name ?? "Sin impresora")
                        .font(.callout.weight(.medium)).lineLimit(1)
                    Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let battery = model.battery {
                    Label("\(battery)%", systemImage: batteryIcon(battery))
                        .labelStyle(.titleAndIcon).font(.caption).monospacedDigit()
                        .foregroundStyle(battery <= 15 ? .red : .secondary)
                }
            }

            HStack(spacing: 6) {
                switch model.connection {
                case .connected:
                    Button("Desconectar") { model.disconnect() }
                case .connecting:
                    ProgressView().controlSize(.small)
                    Text("Conectando…").font(.caption)
                default:
                    Button("Conectar") { Task { await model.connect() } }
                        .disabled(model.selectedAddress == nil)
                }
                Spacer(minLength: 0)
                Menu {
                    Section("Impresoras") {
                        if model.pairedPrinters.isEmpty { Text("Ninguna") }
                        ForEach(model.pairedPrinters) { d in
                            Button {
                                model.select(d)
                            } label: {
                                if d.address == model.selectedAddress {
                                    Label(d.name, systemImage: "checkmark")
                                } else {
                                    Text(d.name)
                                }
                            }
                        }
                    }
                    Button("Buscar impresoras…") { showScan = true }
                        .disabled(!model.bluetoothReady)
                    Button("Actualizar lista") { model.refreshPairedPrinters() }
                    Divider()
                    Picker("Modelo para la vista previa", selection: Binding(get: { model.fallbackModel }, set: { model.fallbackModel = $0 })) {
                        ForEach(PrinterModel.all, id: \.self) { m in
                            Text("\(m.family.rawValue) · \(m.widthDots) px").tag(m)
                        }
                    }
                    Divider()
                    Button("Avanzar papel 1 cm") { Task { await model.feedPaper() } }
                        .disabled(model.connection != .connected)
                    Button("Actualizar estado") { Task { await model.refreshInfo() } }
                        .disabled(model.connection != .connected)
                    Button("Ver registro…") { showLog = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
        .sheet(isPresented: $showScan) { ScanSheet() }
        .sheet(isPresented: $showLog) { LogSheet() }
    }

    private var statusColor: Color {
        switch model.connection {
        case .connected: model.status.map { $0.isReady ? .green : .orange } ?? .green
        case .connecting: .yellow
        case .failed: .red
        case .disconnected: .gray
        }
    }

    private var statusText: String {
        switch model.connection {
        case .connected:
            var parts = [model.model.family.rawValue]
            if let s = model.status { parts.append(s.descriptions.joined(separator: ", ")) }
            if let fw = model.firmware, !fw.isEmpty { parts.append(fw) }
            return parts.joined(separator: " · ")
        case .connecting: return "Conectando…"
        case .failed(let message): return message
        case .disconnected:
            if let problem = model.bluetoothProblem { return problem }
            return model.selectedAddress == nil ? "Emparejala en Ajustes → Bluetooth" : "Desconectada · \(model.model.family.rawValue)"
        }
    }

    private func batteryIcon(_ v: Int) -> String {
        switch v {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

struct ScanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = PrinterScanner()
    @State private var found: [BluetoothDeviceInfo] = []
    @State private var scanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Buscar impresoras").font(.title2.bold())
            Text("Prendé la impresora (botón ~2 s hasta que se encienda la luz). Al conectar por primera vez, macOS puede pedir confirmar el emparejamiento.")
                .font(.callout).foregroundStyle(.secondary)
            List(found) { d in
                HStack {
                    VStack(alignment: .leading) {
                        Text(d.name)
                        Text("\(d.address) · \(d.model?.family.rawValue ?? "modelo desconocido")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Usar") {
                        model.select(d)
                        dismiss()
                        Task { await model.connect() }
                    }
                }
            }
            .frame(minHeight: 160)
            .overlay {
                if found.isEmpty {
                    Text(scanning ? "Buscando…" : "No se encontraron impresoras").foregroundStyle(.secondary)
                }
            }
            HStack {
                if scanning { ProgressView().controlSize(.small) }
                Spacer()
                Button(scanning ? "Buscando…" : "Buscar de nuevo") { start() }.disabled(scanning)
                Button("Cerrar") { scanner.stop(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
        .onAppear(perform: start)
        .onDisappear { scanner.stop() }
    }

    private func start() {
        scanning = true
        scanner.onUpdate = { found = $0 }
        scanner.onFinish = { scanning = false }
        scanner.start(seconds: 12)
    }
}

struct LogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            Text("Registro de comunicación").font(.title3.bold())
            ScrollView {
                Text(model.log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            HStack {
                Button("Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.log.joined(separator: "\n"), forType: .string)
                }
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
    }
}
