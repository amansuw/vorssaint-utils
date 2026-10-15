// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import SwiftUI

/// The macros page: the enable toggle, the macro list and an editor sheet.
/// Edits persist to defaults and nudge the service, so a change answers to
/// its shortcut right away.
struct MacroSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = MacroService.shared
    @AppStorage(DefaultsKey.macrosEnabled) private var enabled = false
    @State private var macros: [Macro] = MacroSupport.decode(
        UserDefaults.standard.data(forKey: DefaultsKey.macros))
    @State private var editing: Macro?
    @State private var creating = false

    private var text: MacroFeatureStrings {
        FeatureStrings.macros(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        MacroService.shared.syncWithPreferences()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            }

            Section {
                if macros.isEmpty {
                    Text(text.emptyList)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(macros) { macro in
                    MacroRow(macro: macro,
                             text: text,
                             shortcutRefused: enabled && service.refusedMacroIDs.contains(macro.id),
                             refusedHelp: l10n.s.shortcutUnavailable,
                             toggle: { setEnabled($0, id: macro.id) },
                             edit: { editing = macro })
                }
                Button {
                    creating = true
                } label: {
                    Label(text.addButton, systemImage: "plus")
                }
                .disabled(macros.count >= MacroSupport.maxMacros)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $creating) {
            MacroEditor(text: text,
                        macro: Macro(steps: [MacroStep()]),
                        isNew: true,
                        conflictTitle: { shortcut, edited in conflictTitle(shortcut, for: edited) },
                        save: { upsert($0) },
                        delete: nil)
        }
        .sheet(item: $editing) { macro in
            MacroEditor(text: text,
                        macro: macro,
                        isNew: false,
                        conflictTitle: { shortcut, edited in conflictTitle(shortcut, for: edited) },
                        save: { upsert($0) },
                        delete: { remove(id: macro.id) })
        }
    }

    /// Who already answers to a combination, named the way the other shortcut
    /// rows name it. The other macros come from this page's own list, and
    /// everything else from the same checks those rows run.
    private func conflictTitle(_ shortcut: GlobalShortcut, for edited: Macro) -> String? {
        if let other = MacroSupport.macro(using: shortcut, apps: edited.apps, in: macros,
                                          excluding: edited.id) {
            return other.name.isEmpty ? text.untitled : other.name
        }
        if let role = GlobalShortcutRole.conflict(for: shortcut, excluding: nil) {
            return role.title(l10n.s)
        }
        if AppFeature.windowLayout.isAvailable,
           let title = WindowLayoutService.shared.shortcutConflictTitle(shortcut) {
            return title
        }
        if AppFeature.commandBar.isAvailable,
           let row = CommandBarRowShortcuts.key(for: shortcut, in: CommandBarService.shared.rowShortcuts) {
            return CommandBarService.shared.entryTitle(forStableKey: row)
                ?? FeatureStrings.commandBar(l10n.language).rowShortcutsTitle
        }
        return shortcut.conflictsWithSystemShortcut ? "macOS" : nil
    }

    private func upsert(_ macro: Macro) {
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index] = macro
        } else {
            macros.append(macro)
        }
        persist()
    }

    private func remove(id: UUID) {
        for step in macros.first(where: { $0.id == id })?.steps ?? [] where step.kind == .password {
            MacroPasswordStore.delete(step.id)
        }
        macros.removeAll { $0.id == id }
        persist()
    }

    private func setEnabled(_ on: Bool, id: UUID) {
        guard let index = macros.firstIndex(where: { $0.id == id }) else { return }
        macros[index].enabled = on
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(MacroSupport.encode(macros), forKey: DefaultsKey.macros)
        MacroService.shared.syncWithPreferences()
    }
}

private struct MacroRow: View {
    let macro: Macro
    let text: MacroFeatureStrings
    let shortcutRefused: Bool
    let refusedHelp: String
    let toggle: (Bool) -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(macro.name.isEmpty ? text.untitled : macro.name)
                            .fontWeight(.medium)
                        if let shortcut = MacroSupport.trigger(of: macro) {
                            ShortcutCaps(keys: shortcut.keyCaps)
                        }
                        if shortcutRefused {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .help(refusedHelp)
                                .accessibilityLabel(refusedHelp)
                        }
                    }
                    Text(MacroSupport.trigger(of: macro) == nil ? text.noShortcutNote : summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { macro.enabled }, set: toggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(macro.name.isEmpty ? text.untitled : macro.name)
        }
        .padding(.vertical, 1)
    }

    /// The steps at a glance: what is typed, which keys, how long it waits.
    private var summary: String {
        MacroSupport.runnableSteps(of: macro).map { step in
            switch step.kind {
            case .text:
                let line = step.text.replacingOccurrences(of: "\n", with: " ")
                return "“\(line.count > 24 ? String(line.prefix(24)) + "…" : line)”"
            case .keys:
                return MacroSupport.keyPress(of: step)?.displayString ?? ""
            case .wait:
                return "\(MacroSupport.secondsText(step.seconds)) \(text.secondsUnit)"
            case .password:
                return "••••••"
            case .open:
                return step.app.isEmpty ? step.link : InstalledApps.name(for: step.app)
            case .click:
                return text.title(step.click)
            }
        }
        .joined(separator: " → ")
    }
}

private struct MacroEditor: View {
    let text: MacroFeatureStrings
    @State var macro: Macro
    let isNew: Bool
    /// Names whoever already answers to a combination, or nil when it is free.
    let conflictTitle: (GlobalShortcut, Macro) -> String?
    let save: (Macro) -> Void
    let delete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State private var shortcutMessage: String?
    /// Passwords typed in this sheet, by step. They reach the Keychain only
    /// on Save, and never the macro itself.
    @State private var passwords: [UUID: String] = [:]
    /// The steps that already had a password when the sheet opened, asked
    /// once so drawing the sheet never goes back to the Keychain.
    @State private var storedPasswordIDs: Set<UUID> = []
    @State private var saveError: String?

    private func hasPassword(_ id: UUID) -> Bool {
        !MacroSupport.typedPassword(passwords[id] ?? "").isEmpty || storedPasswordIDs.contains(id)
    }

    private var hasRunnableStep: Bool {
        macro.steps.contains { step in
            MacroSupport.isRunnable(step) && (step.kind != .password || hasPassword(step.id))
        }
    }

    /// Passwords go to the Keychain first: a macro saved without the password
    /// its step types would only fail later, at the moment it is needed.
    private func commit() {
        let saved = MacroSupport.sanitized(macro, hasPassword: hasPassword)
        // The apps can change after the shortcut was recorded, and with them
        // who else answers to it.
        if let shortcut = MacroSupport.trigger(of: saved), let owner = conflictTitle(shortcut, saved) {
            shortcutMessage = String(format: l10n.s.shortcutConflictFormat, owner)
            return
        }
        let passwordSteps = saved.steps.filter { $0.kind == .password }
        for step in passwordSteps {
            let typed = MacroSupport.typedPassword(passwords[step.id] ?? "")
            guard typed.isEmpty || MacroPasswordStore.set(typed, for: step.id) else {
                saveError = text.passwordSaveFailed
                return
            }
        }
        // A step removed here, or changed into another kind, leaves nothing
        // behind in the Keychain.
        for id in storedPasswordIDs.subtracting(passwordSteps.map(\.id)) {
            MacroPasswordStore.delete(id)
        }
        save(saved)
        dismiss()
    }

    private var typingSpeed: Binding<MacroSupport.TypingSpeed> {
        Binding(get: { MacroSupport.TypingSpeed.nearest(to: macro.keystrokeDelay) },
                set: { macro.keystrokeDelay = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? text.newTitle : text.editTitle)
                .font(.headline)
            Form {
                TextField(text.nameLabel, text: $macro.name, prompt: Text(text.namePlaceholder))
                LabeledContent(text.shortcutLabel) {
                    shortcutField
                }
                Picker(text.typingSpeedLabel, selection: typingSpeed) {
                    ForEach(MacroSupport.TypingSpeed.allCases, id: \.self) { speed in
                        Text(text.title(speed)).tag(speed)
                    }
                }
                // A Spacer in a label here takes the whole width from the
                // controls column, so the count sits beside the arrows.
                LabeledContent(text.repeatLabel) {
                    Stepper(value: $macro.repeatCount, in: MacroSupport.repeatRange) {
                        Text("\(macro.repeatCount)×")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(text.repeatLabel)
                }
            }
            .formStyle(.columns)
            if let shortcutMessage {
                Text(shortcutMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(text.typingSpeedCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text(text.stepsTitle)
                    .fontWeight(.medium)
                Spacer()
                Menu {
                    ForEach(MacroStep.Kind.allCases, id: \.self) { kind in
                        Button(text.title(kind)) {
                            macro.steps.append(MacroStep(kind: kind))
                        }
                    }
                } label: {
                    Label(text.addStepButton, systemImage: "plus")
                }
                .fixedSize()
                .disabled(macro.steps.count >= MacroSupport.maxSteps)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($macro.steps) { $step in
                        MacroStepRow(step: $step,
                                     password: Binding(get: { passwords[step.id] ?? "" },
                                                       set: { passwords[step.id] = $0 }),
                                     hasStoredPassword: storedPasswordIDs.contains(step.id),
                                     text: text,
                                     position: position(of: step.id),
                                     count: macro.steps.count,
                                     move: { move(step.id, by: $0) },
                                     remove: { macro.steps.removeAll { $0.id == step.id } })
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 120, maxHeight: 300)
            if macro.steps.contains(where: { $0.kind == .text }) {
                Text(FeatureStrings.snippets(l10n.language).variablesHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if macro.steps.contains(where: { $0.kind == .password }) {
                Text(text.passwordCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            AppBundleList(title: text.appsTitle,
                          caption: text.appsCaption,
                          addTitle: text.addApp,
                          removeLabel: text.removeApp,
                          bundleIDs: macro.apps,
                          reachesEveryApp: true,
                          onAdd: { bundleID in
                              guard !macro.apps.contains(bundleID),
                                    macro.apps.count < MacroSupport.maxApps else { return }
                              macro.apps.append(bundleID)
                          },
                          onRemove: { bundleID in macro.apps.removeAll { $0 == bundleID } })

            HStack {
                if let delete {
                    Button(role: .destructive) {
                        delete()
                        dismiss()
                    } label: {
                        Text(FeatureStrings.snippets(l10n.language).deleteButton)
                    }
                }
                Spacer()
                Button(l10n.s.uninstallerCancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(FeatureStrings.snippets(l10n.language).saveButton, action: commit)
                .buttonStyle(.borderedProminent)
                .disabled(!hasRunnableStep)
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear {
            storedPasswordIDs = Set(macro.steps.filter { $0.kind == .password }.map(\.id)
                .filter(MacroPasswordStore.has))
        }
        .onChange(of: l10n.language) { _, _ in
            shortcutMessage = nil
            saveError = nil
        }
    }

    private var shortcutField: some View {
        HStack(spacing: 6) {
            ShortcutRecorderButton(
                shortcut: MacroSupport.trigger(of: macro) ?? .radialMenuDefault,
                isEnabled: true,
                waitingTitle: l10n.s.shortcutPressKeys,
                emptyTitle: macro.shortcut.isEmpty ? l10n.s.shortcutNone : nil,
                clearAction: {
                    macro.shortcut = ""
                    shortcutMessage = nil
                },
                notCapturedAction: { shortcutMessage = l10n.s.shortcutNotCaptured },
                recordingChanged: { recording in
                    if recording { shortcutMessage = nil }
                },
                invalidAction: { shortcutMessage = l10n.s.shortcutInvalid },
                captureAction: { shortcut in
                    if let owner = conflictTitle(shortcut, macro) {
                        shortcutMessage = String(format: l10n.s.shortcutConflictFormat, owner)
                        return
                    }
                    macro.shortcut = shortcut.storageValue
                    shortcutMessage = nil
                })
                .frame(width: 150)
                .accessibilityLabel(text.shortcutLabel)
            if !macro.shortcut.isEmpty {
                Button {
                    macro.shortcut = ""
                    shortcutMessage = nil
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(l10n.s.shortcutNone)
            }
        }
    }

    private func position(of id: UUID) -> Int {
        macro.steps.firstIndex { $0.id == id } ?? 0
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = macro.steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard macro.steps.indices.contains(target) else { return }
        macro.steps.swapAt(index, target)
    }
}

private struct MacroStepRow: View {
    @Binding var step: MacroStep
    @Binding var password: String
    let hasStoredPassword: Bool
    let text: MacroFeatureStrings
    let position: Int
    let count: Int
    let move: (Int) -> Void
    let remove: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var choosingApp = false

    /// Keys a shortcut field cannot record on its own: Escape leaves the
    /// field, Delete clears it and Tab moves focus. They are offered by name.
    private static let specialKeys: [Int] = [
        kVK_Return, kVK_Tab, kVK_Space, kVK_Escape, kVK_Delete, kVK_ForwardDelete,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    ]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(position + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Picker(text.stepsTitle, selection: $step.kind) {
                ForEach(MacroStep.Kind.allCases, id: \.self) { kind in
                    Text(text.title(kind)).tag(kind)
                }
            }
            .labelsHidden()
            .fixedSize()
            content
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(position == 0)
                    .help(text.moveUp)
                    .accessibilityLabel(text.moveUp)
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(position >= count - 1)
                    .help(text.moveDown)
                    .accessibilityLabel(text.moveDown)
                Button(action: remove) { Image(systemName: "minus.circle") }
                    .help(text.removeStep)
                    .accessibilityLabel(text.removeStep)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var content: some View {
        switch step.kind {
        case .text:
            TextField(text.textPlaceholder, text: $step.text, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(text.stepText)
        case .keys:
            ShortcutRecorderButton(
                shortcut: MacroSupport.keyPress(of: step) ?? .radialMenuDefault,
                isEnabled: true,
                waitingTitle: l10n.s.shortcutPressKeys,
                requiresModifier: false,
                emptyTitle: MacroSupport.keyPress(of: step) == nil ? text.recordKeys : nil,
                invalidAction: {},
                captureAction: { step.shortcut = $0.storageValue })
                .frame(width: 150)
                .accessibilityLabel(text.stepKeys)
            Menu(text.specialKeyMenu) {
                ForEach(Self.specialKeys, id: \.self) { keyCode in
                    let key = GlobalShortcut(keyCode: Int64(keyCode), modifiers: [])
                    Button(key.displayString) { step.shortcut = key.storageValue }
                }
            }
            .fixedSize()
        case .wait:
            TextField(text.stepWait,
                      value: $step.seconds,
                      format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Stepper(text.stepWait, value: $step.seconds, in: MacroSupport.waitRange, step: 0.1)
                .labelsHidden()
            Text(text.secondsUnit)
                .foregroundStyle(.secondary)
        case .open:
            if step.app.isEmpty {
                TextField(text.openLinkPlaceholder, text: $step.link)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(text.stepOpen)
            } else {
                HStack(spacing: 6) {
                    Image(nsImage: InstalledApps.icon(for: step.app))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(InstalledApps.name(for: step.app))
                        .lineLimit(1)
                    Button { step.app = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(text.removeApp)
                }
            }
            Button(text.chooseApp) { choosingApp = true }
                .fixedSize()
                .sheet(isPresented: $choosingApp) {
                    AppPickerView(canBrowseApplications: true) {
                        choosingApp = false
                    } onSelect: { url in
                        choosingApp = false
                        if let bundleID = Bundle(url: url)?.bundleIdentifier { step.app = bundleID }
                    } onSelectApp: { app in
                        choosingApp = false
                        if let bundleID = app.bundleID ?? Bundle(url: app.url)?.bundleIdentifier {
                            step.app = bundleID
                        }
                    }
                }
        case .click:
            Picker(text.stepClick, selection: $step.click) {
                ForEach(MacroStep.Click.allCases, id: \.self) { click in
                    Text(text.title(click)).tag(click)
                }
            }
            .labelsHidden()
            .fixedSize()
        case .password:
            VStack(alignment: .leading, spacing: 4) {
                SecureField(hasStoredPassword ? text.passwordSavedPlaceholder : text.passwordPlaceholder,
                            text: $password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(text.stepPassword)
                Toggle(text.passwordFieldOnly, isOn: $step.passwordFieldOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
        }
    }
}
