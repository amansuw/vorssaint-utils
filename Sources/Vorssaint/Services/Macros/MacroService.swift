// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Runs user-defined macros from global shortcuts: each macro is a list of
/// steps (type text, press keys, wait, type a password, open an app or a
/// link, click) played in order into whatever app is in front. Requires
/// Accessibility for the synthesized keys and clicks. Nothing here runs or
/// polls while no macro is playing: the feature is its registered hotkeys,
/// plus one app-activation observer while a macro is limited to apps.
final class MacroService: ObservableObject {
    static let shared = MacroService()

    /// Macros whose combination macOS refused (another app holds it), so
    /// Settings can say which row will never answer.
    @Published private(set) var refusedMacroIDs: Set<UUID> = []
    @Published private(set) var runningMacroID: UUID?

    private var hotkeys: [QuickToolHotkey] = []

    /// The list as last read, so an app coming to the front does not decode
    /// preferences again just to ask which macros apply there.
    private var macros: [Macro] = []
    /// What is registered now, to leave the keys alone when switching apps
    /// changes nothing.
    private var registered: [Registration] = []
    private var activationObserver: NSObjectProtocol?

    private struct Registration: Equatable {
        let id: UUID
        let shortcut: GlobalShortcut
    }

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
        guard AppFeature.macros.isAvailable,
              defaults.bool(forKey: DefaultsKey.macrosEnabled) else {
            suspend()
            if !refusedMacroIDs.isEmpty { refusedMacroIDs = [] }
            return
        }

        macros = MacroSupport.decode(defaults.data(forKey: DefaultsKey.macros))
        registerHotkeys(force: true)
        followFrontmostApp(MacroSupport.followsFrontmostApp(macros))
        // A macro removed or switched off mid-run must not keep playing.
        if let runningMacroID, !macros.contains(where: { $0.id == runningMacroID && $0.enabled }) {
            stop()
        }
    }

    func suspend() {
        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys = []
        registered = []
        macros = []
        followFrontmostApp(false)
        stop()
    }

    /// One Carbon key per macro that applies in the app in front. `force`
    /// registers again even when the list is the same: a shortcut field that
    /// was listening released every key behind this service's back.
    private func registerHotkeys(force: Bool) {
        let wanted = MacroSupport.registrations(
            macros, frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        let registrations = wanted.map { Registration(id: $0.macro.id, shortcut: $0.shortcut) }
        guard force || registrations != registered else { return }
        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys = []
        registered = registrations
        var refused: Set<UUID> = []
        for (index, registration) in registrations.enumerated() {
            let id = registration.id
            let hotkey = QuickToolHotkey(id: Self.firstHotkeyID + UInt32(index))
            hotkey.onPress = { [weak self] in self?.hotkeyPressed(for: id) }
            // Macros keep their combinations inside the list, so a claim is
            // named by the macro it belongs to.
            if !hotkey.sync(enabled: true, shortcut: registration.shortcut,
                            storageKey: "\(DefaultsKey.macros).\(id.uuidString)") {
                refused.insert(id)
            }
            hotkeys.append(hotkey)
        }
        // A macro waiting for its app is not refused, so only the macros
        // registered right now can change the answer for themselves.
        let applicable = Set(registrations.map(\.id))
        let merged = refusedMacroIDs.subtracting(applicable).union(refused)
            .intersection(macros.map(\.id))
        if merged != refusedMacroIDs { refusedMacroIDs = merged }
    }

    /// Watches which app is in front only while a macro is limited to apps,
    /// so its combination is held there and nowhere else.
    private func followFrontmostApp(_ follow: Bool) {
        let center = NSWorkspace.shared.notificationCenter
        if !follow {
            if let activationObserver { center.removeObserver(activationObserver) }
            activationObserver = nil
            return
        }
        guard activationObserver == nil else { return }
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // A shortcut field that is listening holds every key released.
            guard !ShortcutCapture.isCapturing else { return }
            self?.registerHotkeys(force: false)
        }
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
              macro.enabled,
              MacroSupport.applies(macro, inApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        else { return }
        run(macro)
    }

    /// Plays the macro now. Also how the Command Bar and the radial menu run
    /// one, so it answers for itself whether it may start.
    func run(_ macro: Macro) {
        guard runningMacroID == nil else {
            stop()
            return
        }
        let once = MacroSupport.runnableSteps(of: macro)
        guard !once.isEmpty else { return }
        // With Vorssaint itself in front (its Settings window, for example)
        // the synthetic typing would land in our own fields. A macro that
        // starts by opening something leaves before it types.
        if once.first?.kind != .open,
           NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier {
            NSSound.beep()
            return
        }
        let repeats = min(max(macro.repeatCount, MacroSupport.repeatRange.lowerBound),
                          MacroSupport.repeatRange.upperBound)
        let steps = Array(repeating: once, count: repeats).flatMap { $0 }
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
            // Secure input means a password field. Ordinary text is kept in
            // preferences, so it is never typed there: a password belongs in
            // a password step. The rest of the macro would land out of order,
            // so it ends.
            guard !IsSecureEventInputEnabled() else {
                fail(token)
                return
            }
            resolve(step.text, token: token) { [weak self] text in
                guard let self else { return }
                // The clipboard can take a moment to answer, and focus can
                // have moved into a password field by then.
                guard !IsSecureEventInputEnabled() else {
                    self.fail(token)
                    return
                }
                if text.isEmpty {
                    next()
                } else if keystrokeDelay > 0 {
                    self.type(MacroSupport.typedUnits(text)[...], delay: keystrokeDelay,
                              token: token, mayType: { !IsSecureEventInputEnabled() }, then: next)
                } else {
                    self.typeAtOnce(text, token: token, then: next)
                }
            }
        case .password:
            typePassword(step, delay: keystrokeDelay, token: token, then: next)
        case .open:
            open(step, token: token, then: next)
        case .click:
            click(step.click, token: token, then: next)
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

    /// The text with its variables filled in, the way a text snippet fills
    /// them. The clipboard is only read when the text asks for it, and off
    /// the main thread: it can hold content its owner renders on demand.
    private func resolve(_ text: String, token: Int, then type: @escaping (String) -> Void) {
        guard MacroSupport.usesVariables(text) else {
            type(text)
            return
        }
        let finish: (String?) -> Void = { clipboard in
            type(String(TextSnippetSupport.expand(text, date: Date(), clipboard: clipboard)
                .prefix(MacroSupport.maxExpandedTextLength)))
        }
        guard TextSnippetSupport.needsClipboard(text) else {
            finish(nil)
            return
        }
        GeneralPasteboardAccess.shared.async({ NSPasteboard.general.string(forType: .string) }) { [weak self] clipboard in
            guard let self, token == self.runToken else { return }
            finish(clipboard)
        }
    }

    /// Opens the app or the link and waits for what answered to be in front.
    /// The steps after it type into whatever is frontmost, so a macro that
    /// went on before the app arrived would type into the wrong window.
    private func open(_ step: MacroStep, token: Int, then next: @escaping () -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let opened: (NSRunningApplication?, Error?) -> Void = { [weak self] app, _ in
            DispatchQueue.main.async {
                guard let self, token == self.runToken else { return }
                guard let app else {
                    self.fail(token)
                    return
                }
                self.waitUntilFrontmost(app.processIdentifier,
                                        deadline: Date().addingTimeInterval(MacroSupport.openTimeout),
                                        token: token, then: next)
            }
        }
        if !step.app.isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: step.app) else {
                fail(token)
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: configuration,
                                               completionHandler: opened)
        } else if let url = MacroSupport.openURL(from: step.link) {
            NSWorkspace.shared.open(url, configuration: configuration, completionHandler: opened)
        } else {
            next()
        }
    }

    private func waitUntilFrontmost(_ pid: pid_t, deadline: Date, token: Int,
                                    then next: @escaping () -> Void) {
        guard token == runToken else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            // In front is not yet ready for keys: give its window a beat.
            after(0.3, token: token, next)
            return
        }
        guard Date() < deadline else {
            fail(token)
            return
        }
        after(0.05, token: token) { [weak self] in
            self?.waitUntilFrontmost(pid, deadline: deadline, token: token, then: next)
        }
    }

    /// A click where the pointer is. Each press is followed by its release
    /// even when the run was stopped in between, like a key.
    private func click(_ click: MacroStep.Click, token: Int, then next: @escaping () -> Void) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let right = click == .right
        let presses = click == .double ? 2 : 1
        func post(_ down: Bool, count: Int) {
            let type: CGEventType = right ? (down ? .rightMouseDown : .rightMouseUp)
                                          : (down ? .leftMouseDown : .leftMouseUp)
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                      mouseCursorPosition: location,
                                      mouseButton: right ? .right : .left) else { return }
            event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            event.post(tap: .cghidEventTap)
        }
        func press(_ count: Int) {
            post(true, count: count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                post(false, count: count)
                guard let self, token == self.runToken else { return }
                if count < presses {
                    self.after(0.06, token: token) { press(count + 1) }
                } else {
                    next()
                }
            }
        }
        press(1)
    }

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

    /// The password from the Keychain, typed key by key and never pasted, so
    /// it does not pass through the clipboard. The Keychain is read off the
    /// main thread because it can stop to ask the person, and where the
    /// password may land is decided after it answers: focus can move while
    /// that question is on screen.
    private func typePassword(_ step: MacroStep, delay: TimeInterval,
                              token: Int, then next: @escaping () -> Void) {
        let id = step.id
        let mayType: () -> Bool = step.passwordFieldOnly ? Self.focusIsPasswordField : { true }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let stored = MacroPasswordStore.password(for: id).map(MacroSupport.typedPassword)
            DispatchQueue.main.async {
                guard let self, token == self.runToken else { return }
                guard let password = stored, !password.isEmpty, mayType() else {
                    self.fail(token)
                    return
                }
                if delay > 0 {
                    self.type(MacroSupport.typedUnits(password)[...], delay: delay,
                              token: token, mayType: mayType, then: next)
                } else {
                    TextSnippetService.postExpansion(deleteCount: 0, text: password,
                                                     trailingKeyCode: nil, trailingFlags: [])
                    next()
                }
            }
        }
    }

    /// Whether the element with keyboard focus hides what is typed into it.
    private static func focusIsPasswordField() -> Bool {
        let secureInput = IsSecureEventInputEnabled()
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return MacroSupport.isPasswordField(role: nil, subrole: nil, secureInput: secureInput)
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // A busy target must not hold the main thread for AX's default
        // multi-second timeout.
        AXUIElementSetMessagingTimeout(application, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString,
                                            &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return MacroSupport.isPasswordField(role: nil, subrole: nil, secureInput: secureInput)
        }
        let focused = value as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.25)
        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(focused, attribute as CFString, &value) == .success
            else { return nil }
            return value as? String
        }
        return MacroSupport.isPasswordField(role: string(kAXRoleAttribute),
                                            subrole: string(kAXSubroleAttribute),
                                            secureInput: secureInput)
    }

    /// One character at a time, with line breaks and tabs pressed as keys.
    /// `mayType` is asked again before each one: a long text can outlive the
    /// field it started in.
    private func type(_ units: ArraySlice<MacroSupport.TypedUnit>, delay: TimeInterval,
                      token: Int, mayType: @escaping () -> Bool, then next: @escaping () -> Void) {
        guard token == runToken else { return }
        guard let unit = units.first else {
            next()
            return
        }
        guard mayType() else {
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
            self?.type(rest, delay: delay, token: token, mayType: mayType, then: next)
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
