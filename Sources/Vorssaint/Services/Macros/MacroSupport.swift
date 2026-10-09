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
    }

    var id = UUID()
    var kind = Kind.text
    var text = ""
    /// A `GlobalShortcut` storage value. Unlike a trigger, it needs no
    /// modifier: Return, Tab and the arrows are ordinary steps.
    var shortcut = ""
    var seconds = MacroSupport.defaultWait

    enum CodingKeys: String, CodingKey {
        case id, kind, text, shortcut, seconds
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

    enum CodingKeys: String, CodingKey {
        case id, name, shortcut, enabled, steps, keystrokeDelay
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

    /// Whether running the step would do anything.
    static func isRunnable(_ step: MacroStep) -> Bool {
        switch step.kind {
        case .text: return !step.text.isEmpty
        case .keys: return keyPress(of: step) != nil
        case .wait: return step.seconds > 0
        }
    }

    static func runnableSteps(of macro: Macro) -> [MacroStep] {
        macro.steps.filter(isRunnable)
    }

    /// The macro as it is saved: values inside their limits and steps that
    /// would do nothing removed, so the runner never has to second-guess a
    /// stored macro.
    static func sanitized(_ macro: Macro) -> Macro {
        var result = macro
        result.name = String(macro.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        result.shortcut = trigger(of: macro)?.storageValue ?? ""
        result.keystrokeDelay = min(max(macro.keystrokeDelay.isFinite ? macro.keystrokeDelay : 0, 0),
                                    maxKeystrokeDelay)
        result.steps = macro.steps.prefix(maxSteps).compactMap { step in
            var step = step
            step.text = String(step.text.prefix(maxTextLength))
            step.seconds = clampedWait(step.seconds)
            return isRunnable(step) ? step : nil
        }
        return result
    }

    static func clampedWait(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultWait }
        return min(max(seconds, waitRange.lowerBound), waitRange.upperBound)
    }

    /// The macros that get a global key, in list order: switched on, with a
    /// valid combination and something to run. Two macros on one combination
    /// would leave one of them dead, so the first in the list keeps it.
    static func registrations(_ macros: [Macro]) -> [(macro: Macro, shortcut: GlobalShortcut)] {
        var taken: Set<GlobalShortcut> = []
        var result: [(macro: Macro, shortcut: GlobalShortcut)] = []
        for macro in macros where macro.enabled {
            guard result.count < maxMacros,
                  let shortcut = trigger(of: macro),
                  !runnableSteps(of: macro).isEmpty,
                  taken.insert(shortcut).inserted
            else { continue }
            result.append((macro, shortcut))
        }
        return result
    }

    /// The other macro that already answers to a combination.
    static func macro(using shortcut: GlobalShortcut, in macros: [Macro],
                      excluding id: UUID) -> Macro? {
        macros.first { $0.id != id && trigger(of: $0) == shortcut }
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

    /// How long the macro takes when nothing holds it up, for the summary
    /// under its name. Typed characters only count at a timed speed.
    static func estimatedDuration(of macro: Macro) -> Double {
        runnableSteps(of: macro).reduce(0) { total, step in
            switch step.kind {
            case .wait: return total + step.seconds
            case .text: return total + Double(step.text.count) * macro.keystrokeDelay
            case .keys: return total
            }
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

    /// The combinations the macros answer to, read the way `MacroService`
    /// registers them, so other shortcut fields can see what is taken.
    static func triggers(defaults: UserDefaults = .standard) -> [GlobalShortcut] {
        guard defaults.bool(forKey: AppFeature.macros.availabilityKey),
              defaults.bool(forKey: DefaultsKey.macrosEnabled) else { return [] }
        return registrations(decode(defaults.data(forKey: DefaultsKey.macros))).map(\.shortcut)
    }

    static func decode(_ data: Data?) -> [Macro] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Macro].self, from: data)) ?? []
    }

    static func encode(_ macros: [Macro]) -> Data? {
        try? JSONEncoder().encode(macros)
    }
}
