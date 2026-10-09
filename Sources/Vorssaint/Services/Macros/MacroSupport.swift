// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// One thing a macro does. Every kind keeps its own field, so switching a
/// step's kind in the editor and back loses nothing. Stored as JSON in
/// defaults; ids and raw values are persisted, so keep them stable.
struct MacroStep: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        /// Types `text` at the caret.
        case text
        /// Presses the combination in `shortcut`, which may be a bare key.
        case keys
        /// Does nothing for `seconds`.
        case wait
        /// Types a password kept in the Keychain under this step's id. The
        /// password itself is never part of the step, so it is never in
        /// preferences or in a settings backup.
        case password
        /// Opens `app`, or `link` when no app is chosen, and waits for it to
        /// come to the front, so the steps after it land in the right place.
        case open
        /// Clicks where the pointer is.
        case click
    }

    enum Click: String, Codable, CaseIterable {
        case left, right, double
    }

    var id = UUID()
    var kind = Kind.text
    var text = ""
    /// A `GlobalShortcut` storage value. Unlike a trigger, it needs no
    /// modifier: Return, Tab and the arrows are ordinary steps.
    var shortcut = ""
    var seconds = MacroSupport.defaultWait
    /// A password step refuses to type anywhere a password would be visible.
    var passwordFieldOnly = true
    /// The bundle identifier an open step launches; empty means `link`.
    var app = ""
    /// A web address, a file or a folder for an open step.
    var link = ""
    var click = Click.left

    enum CodingKeys: String, CodingKey {
        case id, kind, text, shortcut, seconds, passwordFieldOnly, app, link, click
    }
}

extension MacroStep {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
        seconds = try container.decodeIfPresent(Double.self, forKey: .seconds) ?? MacroSupport.defaultWait
        passwordFieldOnly = try container.decodeIfPresent(Bool.self, forKey: .passwordFieldOnly) ?? true
        app = try container.decodeIfPresent(String.self, forKey: .app) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        // A click of a kind this version does not know is still a click.
        click = (try? container.decodeIfPresent(Click.self, forKey: .click)) ?? .left
    }
}

/// A named sequence of steps that runs from one global shortcut.
struct Macro: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    /// A `GlobalShortcut` storage value; empty means no shortcut yet.
    var shortcut = ""
    var enabled = true
    var steps: [MacroStep] = []
    /// Seconds between typed characters. Zero types each text step at once.
    var keystrokeDelay = 0.0
    /// How many times the steps play on one press.
    var repeatCount = 1
    /// Bundle identifiers the macro is limited to; empty means every app. Its
    /// shortcut is only held while one of them is in front, so the same keys
    /// keep their own meaning everywhere else.
    var apps: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, name, shortcut, enabled, steps, keystrokeDelay, repeatCount, apps
    }
}

extension Macro {
    /// A step of a kind this version does not know (a file from a newer
    /// build, or one edited by hand) is dropped on its own, so the rest of
    /// the macro and every other macro in the list still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        steps = (try container.decodeIfPresent([LossyStep].self, forKey: .steps) ?? [])
            .compactMap(\.step)
        keystrokeDelay = try container.decodeIfPresent(Double.self, forKey: .keystrokeDelay) ?? 0
        repeatCount = try container.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        apps = try container.decodeIfPresent([String].self, forKey: .apps) ?? []
    }

    private struct LossyStep: Decodable {
        let step: MacroStep?

        init(from decoder: Decoder) throws {
            step = try? MacroStep(from: decoder)
        }
    }
}

/// The pure half of macros: limits, validation and the decisions the runner
/// and Settings share, all deterministic so the harness can pin them down.
enum MacroSupport {
    /// One Carbon key per macro, so the list is bounded like every other
    /// list of user shortcuts.
    static let maxMacros = 32
    static let maxSteps = 50
    static let maxTextLength = 4000
    static let defaultWait = 0.5
    static let waitRange: ClosedRange<Double> = 0.05...60
    static let maxKeystrokeDelay = 0.5
    static let repeatRange: ClosedRange<Int> = 1...99
    static let maxApps = 20
    /// What a text step may grow to once its variables are filled in: the
    /// clipboard can hold a whole document.
    static let maxExpandedTextLength = 20_000
    /// How long an open step waits for what it opened to come to the front.
    static let openTimeout = 10.0

    /// What the typing speed picker offers, as seconds between characters.
    enum TypingSpeed: Double, CaseIterable {
        case instant = 0
        case fast = 0.02
        case natural = 0.06
        case slow = 0.15

        /// The nearest offered speed, so a hand-edited delay still shows a
        /// selection instead of an empty picker.
        static func nearest(to delay: Double) -> TypingSpeed {
            allCases.min { abs($0.rawValue - delay) < abs($1.rawValue - delay) } ?? .instant
        }
    }

    /// The combination a macro answers to. A trigger needs a modifier (or a
    /// standalone function key), exactly like every other global shortcut.
    static func trigger(of macro: Macro) -> GlobalShortcut? {
        GlobalShortcut(storageValue: macro.shortcut)
    }

    /// The key a step presses, which may carry no modifier at all.
    static func keyPress(of step: MacroStep) -> GlobalShortcut? {
        GlobalShortcut(storageValue: step.shortcut, requiringModifier: false)
    }

    /// Whether running the step would do anything. A password step counts:
    /// whether its password exists is the Keychain's to answer, at the moment
    /// the step is saved and again when it runs.
    static func isRunnable(_ step: MacroStep) -> Bool {
        switch step.kind {
        case .text: return !step.text.isEmpty
        case .keys: return keyPress(of: step) != nil
        case .wait: return step.seconds > 0
        case .password: return true
        case .open: return !step.app.isEmpty || openURL(from: step.link) != nil
        case .click: return true
        }
    }

    /// The address an open step's link stands for. A scheme is kept as typed,
    /// a path opens that file or folder, and a bare site such as
    /// "example.com/page" opens over https. Anything else opens nothing.
    static func openURL(from link: String) -> URL? {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return nil }
        if link.hasPrefix("/") || link.hasPrefix("~") {
            return URL(fileURLWithPath: (link as NSString).expandingTildeInPath)
        }
        guard !link.contains(where: \.isWhitespace) else { return nil }
        // "localhost:3000" and "example.com:8080" parse as a scheme followed
        // by a number, which no real scheme is.
        if let scheme = URL(string: link)?.scheme, !scheme.isEmpty,
           link.dropFirst(scheme.count).first == ":",
           link.dropFirst(scheme.count + 1).first?.isNumber != true {
            return URL(string: link)
        }
        if link.lowercased().hasPrefix("localhost") { return URL(string: "http://" + link) }
        guard link.contains(".") else { return nil }
        return URL(string: "https://" + link)
    }

    /// Whether a text step has variables to fill in before it is typed. They
    /// are the ones text snippets use: {{date}}, {{time}}, {{clipboard}}.
    static func usesVariables(_ text: String) -> Bool {
        text.contains("{{")
    }

    /// Roles whose content is shown as it is typed.
    static let visibleTextRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    static let secureTextRole = "AXSecureTextField"

    /// Whether what has focus hides what is typed into it. A field that says
    /// it is a password field is one, and a text field that does not say so
    /// is not, even while secure input is on: a terminal with secure keyboard
    /// entry still prints every character. Only when the focused element is
    /// unknown, or is not a text field at all, does secure input decide.
    static func isPasswordField(role: String?, subrole: String?, secureInput: Bool) -> Bool {
        if subrole == secureTextRole || role == secureTextRole { return true }
        if let role, visibleTextRoles.contains(role) { return false }
        return secureInput
    }

    /// A password as it is typed: one line, since a line break would press
    /// Return in the middle of it.
    static func typedPassword(_ password: String) -> String {
        password.filter { !$0.isNewline }
    }

    static func runnableSteps(of macro: Macro) -> [MacroStep] {
        macro.steps.filter(isRunnable)
    }

    /// The macro as it is saved: values inside their limits and steps that
    /// would do nothing removed, so the runner never has to second-guess a
    /// stored macro. `hasPassword` answers for the Keychain, so a password
    /// step with nothing to type is removed like any other empty step.
    static func sanitized(_ macro: Macro, hasPassword: (UUID) -> Bool = { _ in true }) -> Macro {
        var result = macro
        result.name = String(macro.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        result.shortcut = trigger(of: macro)?.storageValue ?? ""
        result.keystrokeDelay = min(max(macro.keystrokeDelay.isFinite ? macro.keystrokeDelay : 0, 0),
                                    maxKeystrokeDelay)
        result.repeatCount = min(max(macro.repeatCount, repeatRange.lowerBound), repeatRange.upperBound)
        var seenApps: Set<String> = []
        result.apps = Array(macro.apps.filter { !$0.isEmpty && seenApps.insert($0).inserted }.prefix(maxApps))
        result.steps = macro.steps.prefix(maxSteps).compactMap { step in
            var step = step
            step.text = String(step.text.prefix(maxTextLength))
            step.seconds = clampedWait(step.seconds)
            step.link = String(step.link.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
            if step.kind == .password, !hasPassword(step.id) { return nil }
            return isRunnable(step) ? step : nil
        }
        return result
    }

    static func clampedWait(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultWait }
        return min(max(seconds, waitRange.lowerBound), waitRange.upperBound)
    }

    /// Whether the macro answers while `bundleID` is the app in front.
    static func applies(_ macro: Macro, inApp bundleID: String?) -> Bool {
        macro.apps.isEmpty || (bundleID.map(macro.apps.contains) ?? false)
    }

    /// The macros that get a global key while `frontmostBundleID` is in
    /// front: switched on, with a valid combination, something to run and no
    /// app limit that leaves this app out. Two macros on one combination
    /// would leave one of them dead, so a macro made for this app comes
    /// before one that works everywhere, and otherwise the first in the list
    /// keeps the combination.
    static func registrations(_ macros: [Macro],
                              frontmostBundleID: String? = nil) -> [(macro: Macro, shortcut: GlobalShortcut)] {
        var taken: Set<GlobalShortcut> = []
        var result: [(macro: Macro, shortcut: GlobalShortcut)] = []
        let candidates = macros.filter { $0.enabled && applies($0, inApp: frontmostBundleID) }
        for macro in candidates.filter({ !$0.apps.isEmpty }) + candidates.filter(\.apps.isEmpty) {
            guard result.count < maxMacros,
                  let shortcut = trigger(of: macro),
                  !runnableSteps(of: macro).isEmpty,
                  taken.insert(shortcut).inserted
            else { continue }
            result.append((macro, shortcut))
        }
        return result
    }

    /// Whether any macro is limited to apps, which is the only reason to
    /// follow which app is in front.
    static func followsFrontmostApp(_ macros: [Macro]) -> Bool {
        macros.contains { $0.enabled && !$0.apps.isEmpty }
    }

    /// The other macro that would answer to the same combination in the same
    /// place. A macro limited to apps may share a combination with one that
    /// works everywhere, and two limited ones may share it when no app is on
    /// both lists.
    static func macro(using shortcut: GlobalShortcut, apps: [String] = [], in macros: [Macro],
                      excluding id: UUID) -> Macro? {
        macros.first { other in
            guard other.id != id, trigger(of: other) == shortcut else { return false }
            if other.apps.isEmpty || apps.isEmpty { return other.apps.isEmpty && apps.isEmpty }
            return !Set(other.apps).isDisjoint(with: apps)
        }
    }

    /// The macro behind a combination, for the other shortcut fields: any
    /// macro that can answer to it somewhere is in their way.
    static func owner(of shortcut: GlobalShortcut, defaults: UserDefaults = .standard) -> Macro? {
        guard defaults.bool(forKey: AppFeature.macros.availabilityKey),
              defaults.bool(forKey: DefaultsKey.macrosEnabled) else { return nil }
        return decode(defaults.data(forKey: DefaultsKey.macros)).first {
            $0.enabled && trigger(of: $0) == shortcut && !runnableSteps(of: $0).isEmpty
        }
    }

    /// The macros another surface may run by name: the feature installed and
    /// switched on, and each one switched on with something to do.
    static func runnableMacros(defaults: UserDefaults = .standard) -> [Macro] {
        guard defaults.bool(forKey: AppFeature.macros.availabilityKey),
              defaults.bool(forKey: DefaultsKey.macrosEnabled) else { return [] }
        return decode(defaults.data(forKey: DefaultsKey.macros)).filter {
            $0.enabled && !runnableSteps(of: $0).isEmpty
        }
    }

    /// One of them by id, for a surface that kept only the id.
    static func runnableMacro(withID id: UUID, defaults: UserDefaults = .standard) -> Macro? {
        runnableMacros(defaults: defaults).first { $0.id == id }
    }

    /// The owner's name the way a shortcut field shows who is in its way.
    static func ownerTitle(of shortcut: GlobalShortcut, defaults: UserDefaults = .standard) -> String? {
        owner(of: shortcut, defaults: defaults).map {
            $0.name.isEmpty ? FeatureStrings.macros(L10n.shared.language).untitled : $0.name
        }
    }

    /// One piece of a text step typed character by character.
    enum TypedUnit: Equatable {
        case characters(String)
        case key(Int)
    }

    /// The text as the timed typist sends it: one unit per character, with
    /// line breaks and tabs pressed as their keys. A line break of any
    /// spelling is one press, the way a person typing it would press once.
    static func typedUnits(_ text: String) -> [TypedUnit] {
        text.map { character in
            if character.isNewline { return .key(kVK_Return) }
            if character == "\t" { return .key(kVK_Tab) }
            return .characters(String(character))
        }
    }

    /// Seconds without a trailing zero: "0.5", "2", "1.25".
    static func secondsText(_ seconds: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: seconds)) ?? String(seconds)
    }

    /// Every combination a macro answers to somewhere, in list order and
    /// without repeats, for the pages that list what is taken.
    static func triggers(defaults: UserDefaults = .standard) -> [GlobalShortcut] {
        guard defaults.bool(forKey: AppFeature.macros.availabilityKey),
              defaults.bool(forKey: DefaultsKey.macrosEnabled) else { return [] }
        var seen: Set<GlobalShortcut> = []
        return decode(defaults.data(forKey: DefaultsKey.macros)).compactMap { macro in
            guard macro.enabled, !runnableSteps(of: macro).isEmpty,
                  let shortcut = trigger(of: macro), seen.insert(shortcut).inserted
            else { return nil }
            return shortcut
        }
    }

    static func decode(_ data: Data?) -> [Macro] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Macro].self, from: data)) ?? []
    }

    static func encode(_ macros: [Macro]) -> Data? {
        try? JSONEncoder().encode(macros)
    }
}
