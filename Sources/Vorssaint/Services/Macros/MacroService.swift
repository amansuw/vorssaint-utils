// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Runs user-defined macros from global shortcuts: each macro is a list of
/// steps (type text, press keys, wait) played in order into whatever app is
/// in front. Requires Accessibility for the synthesized keys. Nothing here
/// runs, polls or holds a resource while no macro is playing; the feature is
/// only its registered hotkeys.
final class MacroService: ObservableObject {
    static let shared = MacroService()

    /// Macros whose combination macOS refused (another app holds it), so
    /// Settings can say which row will never answer.
    @Published private(set) var refusedMacroIDs: Set<UUID> = []
    @Published private(set) var runningMacroID: UUID?

    private var hotkeys: [QuickToolHotkey] = []

    /// The permission prompt fires at most once per launch (PastePlain's
    /// pattern): a shortcut mashed without Accessibility nags once.
    private var promptedForAccessibility = false

    /// Bumped whenever a run starts or stops. Every scheduled step carries
    /// the value it was scheduled under, so a stopped run's pending steps
    /// find a newer value and do nothing.
    private var runToken = 0

    /// The beat between steps, so the app in front has handled one before
    /// the next arrives.
    private static let stepGap: TimeInterval = 0.05

    /// Past the quick tools, the command bar's rows (200...) and the radial
    /// menu's wheels (1700...), so the ids can never collide.
    private static let firstHotkeyID: UInt32 = 2400

    private init() {}

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys = []

        guard AppFeature.macros.isAvailable,
              defaults.bool(forKey: DefaultsKey.macrosEnabled) else {
            stop()
            if !refusedMacroIDs.isEmpty { refusedMacroIDs = [] }
            return
        }

        let macros = MacroSupport.decode(defaults.data(forKey: DefaultsKey.macros))
        var refused: Set<UUID> = []
        for (index, entry) in MacroSupport.registrations(macros).enumerated() {
            let id = entry.macro.id
            let hotkey = QuickToolHotkey(id: Self.firstHotkeyID + UInt32(index))
            hotkey.onPress = { [weak self] in self?.hotkeyPressed(for: id) }
            // Macros keep their combinations inside the list, so a claim is
            // named by the macro it belongs to.
            if !hotkey.sync(enabled: true, shortcut: entry.shortcut,
                            storageKey: "\(DefaultsKey.macros).\(id.uuidString)") {
                refused.insert(id)
            }
            hotkeys.append(hotkey)
        }
        if refused != refusedMacroIDs { refusedMacroIDs = refused }
        // A macro removed or switched off mid-run must not keep playing.
        if let runningMacroID, !macros.contains(where: { $0.id == runningMacroID && $0.enabled }) {
            stop()
        }
    }

    func suspend() {
        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys = []
        stop()
    }

    /// Ends the run in progress. Steps already posted stay posted; nothing
    /// further is sent.
    func stop() {
        runToken += 1
        if runningMacroID != nil { runningMacroID = nil }
    }

    // MARK: - Running

    private func hotkeyPressed(for id: UUID) {
        // Any macro shortcut pressed during a run stops it. That is the way
        // out of a long macro, and it also means a macro whose own steps
        // press a macro shortcut ends instead of looping forever.
        guard runningMacroID == nil else {
            stop()
            return
        }
        let defaults = UserDefaults.standard
        guard AppFeature.macros.isAvailable,
              defaults.bool(forKey: DefaultsKey.macrosEnabled),
              let macro = MacroSupport.decode(defaults.data(forKey: DefaultsKey.macros))
                  .first(where: { $0.id == id }),
              macro.enabled
        else { return }
        run(macro)
    }

    func run(_ macro: Macro) {
        let steps = MacroSupport.runnableSteps(of: macro)
        guard !steps.isEmpty else { return }
        // With Vorssaint itself in front (its Settings window, for example)
        // the synthetic typing would land in our own fields.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier {
            NSSound.beep()
            return
        }
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return
        }
        runToken += 1
        runningMacroID = macro.id
        startWhenModifiersReleased(steps: steps, keystrokeDelay: macro.keystrokeDelay,
                                   token: runToken, attempt: 0)
    }

    /// Typing while the summoning chord is still physically down turns every
    /// character into a shortcut in the target app, so wait for a clean
    /// keyboard first: every 15 ms for up to ~1.5 s, plus a settle beat. A
    /// modifier still pinned after that means the keyboard never came clean;
    /// give up audibly instead of typing anyway.
    private func startWhenModifiersReleased(steps: [MacroStep], keystrokeDelay: Double,
                                            token: Int, attempt: Int) {
        guard token == runToken else { return }
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if attempt >= 100 {
            fail(token)
            return
        }
        guard held.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                self?.startWhenModifiersReleased(steps: steps, keystrokeDelay: keystrokeDelay,
                                                 token: token, attempt: attempt + 1)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.perform(steps[...], keystrokeDelay: keystrokeDelay, token: token)
        }
    }

    private func perform(_ steps: ArraySlice<MacroStep>, keystrokeDelay: Double, token: Int) {
        guard token == runToken else { return }
        guard let step = steps.first else {
            runningMacroID = nil
            return
        }
        // Secure input means a password field: nothing may be typed there,
        // and the rest of the macro would land out of order, so it ends.
        guard !IsSecureEventInputEnabled() else {
            fail(token)
            return
        }
        let rest = steps.dropFirst()
        let next: () -> Void = { [weak self] in
            self?.after(Self.stepGap, token: token) {
                self?.perform(rest, keystrokeDelay: keystrokeDelay, token: token)
            }
        }
        switch step.kind {
        case .wait:
            after(MacroSupport.clampedWait(step.seconds), token: token) { [weak self] in
                self?.perform(rest, keystrokeDelay: keystrokeDelay, token: token)
            }
        case .keys:
            guard let shortcut = MacroSupport.keyPress(of: step) else {
                next()
                return
            }
            press(shortcut, token: token, then: next)
        case .text:
            if keystrokeDelay > 0 {
                type(MacroSupport.typedUnits(step.text)[...], delay: keystrokeDelay,
                     token: token, then: next)
            } else {
                typeAtOnce(step.text, token: token, then: next)
            }
        }
    }

    private func after(_ delay: TimeInterval, token: Int, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, token == self.runToken else { return }
            work()
        }
    }

    private func fail(_ token: Int) {
        guard token == runToken else { return }
        NSSound.beep()
        stop()
    }

    // MARK: - Steps

    /// The whole text through the routine the snippets use: typed when it is
    /// one line, pasted when it has line breaks, so a chat field receives
    /// the lines instead of sending on the first Return.
    private func typeAtOnce(_ text: String, token: Int, then next: @escaping () -> Void) {
        guard TextSnippetSupport.requiresPaste(text) else {
            TextSnippetService.postExpansion(deleteCount: 0, text: text,
                                             trailingKeyCode: nil, trailingFlags: [])
            next()
            return
        }
        let started = TransientPaste.shared.paste(
            text,
            didPostShortcut: next,
            didFail: { [weak self] in self?.fail(token) })
        if !started { fail(token) }
    }

    /// One character at a time, with line breaks and tabs pressed as keys.
    /// Secure input is asked again before each one: a long text can outlive
    /// the field it started in.
    private func type(_ units: ArraySlice<MacroSupport.TypedUnit>, delay: TimeInterval,
                      token: Int, then next: @escaping () -> Void) {
        guard token == runToken else { return }
        guard let unit = units.first else {
            next()
            return
        }
        guard !IsSecureEventInputEnabled() else {
            fail(token)
            return
        }
        switch unit {
        case .characters(let text):
            TextSnippetService.postExpansion(deleteCount: 0, text: text,
                                             trailingKeyCode: nil, trailingFlags: [])
        case .key(let keyCode):
            Self.postKey(GlobalShortcut(keyCode: Int64(keyCode), modifiers: []), down: true)
            Self.postKey(GlobalShortcut(keyCode: Int64(keyCode), modifiers: []), down: false)
        }
        let rest = units.dropFirst()
        after(delay, token: token) { [weak self] in
            self?.type(rest, delay: delay, token: token, then: next)
        }
    }

    /// The key goes back up even when the run was stopped in between: a key
    /// left down would repeat in the target app until something released it.
    private func press(_ shortcut: GlobalShortcut, token: Int, then next: @escaping () -> Void) {
        Self.postKey(shortcut, down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            Self.postKey(shortcut, down: false)
            guard let self, token == self.runToken else { return }
            next()
        }
    }

    private static func postKey(_ shortcut: GlobalShortcut, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(shortcut.carbonKeyCode), keyDown: down)
        else { return }
        // The flags a real press carries, so an arrow or an F key is
        // recognised beyond the app in front as well (issue #401).
        event.flags = shortcut.syntheticEventFlags
        event.post(tap: .cghidEventTap)
    }
}
