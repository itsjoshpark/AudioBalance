import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.isOn }, set: { model.setOn($0) })) {
                    Text("Turn on Audio Balance")
                    Text("Keeps your left–right balance locked, even when AirPods or other devices drift.")
                }
                .toggleStyle(.switch)
                .disabled(model.isChangingAgent)
                .accessibilityIdentifier("agentSwitch")

                agentNotice
            }

            Section("Lock Point") {
                LabeledContent("Lock at") {
                    Text(BalancePolicy.describe(Float(model.lockPoint)))
                        .monospacedDigit()
                        .accessibilityIdentifier("lockPointValue")
                }
                HStack {
                    Text("Left").foregroundStyle(.secondary)
                    Slider(value: snappedLockPoint, in: 0...1)
                        .labelsHidden()
                        .overlay(alignment: .bottom) { centerTick }
                        .sensoryFeedback(.alignment, trigger: isLockPointCentered) { _, isCentered in isCentered }
                        .accessibilityIdentifier("lockPointSlider")
                    Text("Right").foregroundStyle(.secondary)
                }
                .font(.callout)
                HStack {
                    Spacer()
                    Button("Center") { model.lockPoint = Double(BalancePolicy.center) }
                        .disabled(isLockPointCentered)
                        .accessibilityIdentifier("centerButton")
                }
            }
            .disabled(!model.isOn)

            Section("Notifications") {
                Toggle("Notify me when balance is corrected", isOn: $model.notifyOnFix)
            }
            .disabled(!model.isOn)

            Section("Status") {
                LabeledContent("Output device", value: model.deviceName ?? String(localized: "None"))
                LabeledContent("Current balance") {
                    Text(model.currentBalance.map(BalancePolicy.describe) ?? String(localized: "Not adjustable"))
                        .monospacedDigit()
                        .accessibilityIdentifier("currentBalance")
                }
                LabeledContent("Last correction") {
                    if let date = model.lastFixDate {
                        VStack(alignment: .trailing) {
                            Text(date, format: .relative(presentation: .named))
                                .help(date.formatted(date: .abbreviated, time: .standard))
                            if let device = model.lastFixDevice {
                                Text(device)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("lastCorrectionDevice")
                            }
                        }
                    } else {
                        Text("Never")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            Label(
                "Audio Balance keeps running in the background after you close this window. Manage it in System Settings › General › Login Items & Extensions.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refresh() }
    }

    private var isLockPointCentered: Bool {
        model.lockPoint == Double(BalancePolicy.center)
    }

    /// Writes slider values through ``BalancePolicy/snapped(_:)`` so dragging near the middle
    /// lands exactly on center.
    private var snappedLockPoint: Binding<Double> {
        Binding(
            get: { model.lockPoint },
            set: { model.lockPoint = Double(BalancePolicy.snapped(Float($0))) }
        )
    }

    private var centerTick: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 2, height: 6)
            .offset(y: 7)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var agentNotice: some View {
        switch model.agentState {
        case .requiresApproval:
            notice(
                Text("Audio Balance is turned off in Login Items & Extensions. Allow it in System Settings to keep your balance locked."),
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            ) {
                Button("Open System Settings…") { model.openLoginItemsSettings() }
                    .accessibilityIdentifier("openLoginItemsButton")
            }
        case .notRunning:
            notice(
                Text("Audio Balance is registered but isn't running."),
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            ) {
                Button("Restart") { model.setOn(true) }
                    .disabled(model.isChangingAgent)
                    .accessibilityIdentifier("restartButton")
            }
        case .running, .off:
            EmptyView()
        }
        if let error = model.agentError {
            notice(Text(verbatim: error), systemImage: "xmark.octagon.fill", tint: .red) { EmptyView() }
        }
    }

    private func notice(
        _ message: Text,
        systemImage: String,
        tint: Color,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: systemImage).foregroundStyle(tint)
            message.fixedSize(horizontal: false, vertical: true)
            Spacer()
            action()
        }
        .font(.callout)
    }
}
