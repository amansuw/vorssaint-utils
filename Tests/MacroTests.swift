// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

enum MacroTests {
    static func run(expect: (Bool, String) -> Void) {
        let trigger = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: [.control, .option, .command])
        let otherTrigger = GlobalShortcut(keyCode: Int64(kVK_ANSI_J), modifiers: [.control, .option, .command])
        let returnKey = GlobalShortcut(keyCode: Int64(kVK_Return), modifiers: [])
        let typeHello = MacroStep(kind: .text, text: "Hello")
        let pressReturn = MacroStep(kind: .keys, shortcut: returnKey.storageValue)
        let waitHalf = MacroStep(kind: .wait, seconds: 0.5)
        let macro = Macro(name: "Greeting", shortcut: trigger.storageValue,
                          steps: [typeHello, waitHalf, pressReturn], keystrokeDelay: 0.02)

        // Storage
        expect(MacroSupport.decode(MacroSupport.encode([macro])) == [macro],
               "a macro survives being saved and read back")
        expect(MacroSupport.decode(nil).isEmpty && MacroSupport.decode(Data("not json".utf8)).isEmpty,
               "missing or damaged storage reads as no macros instead of failing")
        let newerFile = """
            [{"id":"\(macro.id.uuidString)","steps":[
              {"id":"\(typeHello.id.uuidString)","kind":"text","text":"Hello"},
              {"id":"\(UUID().uuidString)","kind":"click","x":10},
              {"id":"\(waitHalf.id.uuidString)","kind":"wait"}]}]
            """
        let tolerant = MacroSupport.decode(Data(newerFile.utf8))
        expect(tolerant.count == 1 && tolerant[0].steps.map(\.kind) == [.text, .wait],
               "a step of an unknown kind is dropped on its own and the macro still loads")
        expect(tolerant.first?.enabled == true && tolerant.first?.name == ""
               && tolerant.first?.shortcut == "" && tolerant.first?.keystrokeDelay == 0
               && tolerant.first?.steps.last?.seconds == MacroSupport.defaultWait,
               "fields a stored macro does not carry fall back to their defaults")

        // Triggers and key presses
        expect(MacroSupport.trigger(of: macro) == trigger,
               "a combination with modifiers is a valid trigger")
        expect(MacroSupport.trigger(of: Macro(shortcut: returnKey.storageValue)) == nil,
               "a bare key cannot trigger a macro, or typing would become impossible")
        expect(MacroSupport.keyPress(of: pressReturn) == returnKey,
               "a step may press a bare key such as Return")
        expect(MacroSupport.keyPress(of: MacroStep(kind: .keys, shortcut: "nonsense")) == nil,
               "a key step with no readable key presses nothing")

        // Runnable steps and saving
        expect(MacroSupport.isRunnable(typeHello) && MacroSupport.isRunnable(pressReturn)
               && MacroSupport.isRunnable(waitHalf)
               && !MacroSupport.isRunnable(MacroStep(kind: .text))
               && !MacroSupport.isRunnable(MacroStep(kind: .keys))
               && !MacroSupport.isRunnable(MacroStep(kind: .wait, seconds: 0)),
               "a step runs only when it has text, a key or a wait to act on")
        let messy = Macro(name: "  Padded  ", shortcut: returnKey.storageValue,
                          steps: [MacroStep(kind: .text), MacroStep(kind: .wait, seconds: 900),
                                  MacroStep(kind: .wait, seconds: 0.001),
                                  MacroStep(kind: .text, text: String(repeating: "x", count: 5000))],
                          keystrokeDelay: 30)
        let saved = MacroSupport.sanitized(messy)
        expect(saved.name == "Padded" && saved.shortcut.isEmpty
               && saved.keystrokeDelay == MacroSupport.maxKeystrokeDelay,
               "saving trims the name, drops an unusable trigger and bounds the typing delay")
        expect(saved.steps.count == 3
               && saved.steps[0].seconds == MacroSupport.waitRange.upperBound
               && saved.steps[1].seconds == MacroSupport.waitRange.lowerBound
               && saved.steps[2].text.count == MacroSupport.maxTextLength,
               "saving removes empty steps and keeps waits and text inside their limits")
        expect(MacroSupport.sanitized(macro) == macro,
               "saving leaves a well-formed macro exactly as it was")
        expect(MacroSupport.clampedWait(.nan) == MacroSupport.defaultWait
               && MacroSupport.clampedWait(.infinity) == MacroSupport.defaultWait,
               "a wait that is not a number falls back to the default instead of hanging a run")
        let tooMany = Macro(steps: Array(repeating: typeHello, count: MacroSupport.maxSteps + 10))
        expect(MacroSupport.sanitized(tooMany).steps.count == MacroSupport.maxSteps,
               "a macro keeps at most the allowed number of steps")

        // Which macros get a global key
        var disabled = macro
        disabled.id = UUID()
        disabled.enabled = false
        disabled.shortcut = otherTrigger.storageValue
        var duplicate = macro
        duplicate.id = UUID()
        var empty = macro
        empty.id = UUID()
        empty.shortcut = otherTrigger.storageValue
        empty.steps = []
        var second = macro
        second.id = UUID()
        second.shortcut = otherTrigger.storageValue
        let registered = MacroSupport.registrations([disabled, macro, duplicate, empty, second])
        expect(registered.map(\.macro.id) == [macro.id, second.id]
               && registered.map(\.shortcut) == [trigger, otherTrigger],
               "only switched-on macros with steps register, and the first keeps a shared combination")
        let crowd = (0..<(MacroSupport.maxMacros + 5)).map { index in
            Macro(shortcut: GlobalShortcut(keyCode: Int64(index), modifiers: [.control, .option, .command])
                    .storageValue,
                  steps: [waitHalf])
        }
        expect(MacroSupport.registrations(crowd).count <= MacroSupport.maxMacros,
               "the number of registered macro keys is bounded")
        expect(MacroSupport.macro(using: trigger, in: [macro, second], excluding: second.id)?.id == macro.id
               && MacroSupport.macro(using: trigger, in: [macro, second], excluding: macro.id) == nil,
               "a combination is reported as taken by another macro, never by the one being edited")

        // Timed typing
        expect(MacroSupport.typedUnits("a\r\nb\tc\n") == [
            .characters("a"), .key(kVK_Return), .characters("b"), .key(kVK_Tab),
            .characters("c"), .key(kVK_Return),
        ], "timed typing presses Return once per line break and Tab for a tab")
        expect(MacroSupport.typedUnits("👩‍💻é") == [.characters("👩‍💻"), .characters("é")],
               "timed typing never splits a character made of several code points")
        expect(abs(MacroSupport.estimatedDuration(of: macro) - (0.5 + 5 * 0.02)) < 0.0001,
               "the estimate adds the waits and the time spent typing at a timed speed")
        expect(MacroSupport.TypingSpeed.nearest(to: 0) == .instant
               && MacroSupport.TypingSpeed.nearest(to: 0.05) == .natural
               && MacroSupport.TypingSpeed.nearest(to: 9) == .slow,
               "a stored typing delay shows as the nearest offered speed")
        expect(MacroSupport.TypingSpeed.allCases.allSatisfy { $0.rawValue <= MacroSupport.maxKeystrokeDelay },
               "every offered typing speed survives saving")
        expect(MacroSupport.secondsText(0.5, locale: Locale(identifier: "en_US")) == "0.5"
               && MacroSupport.secondsText(2, locale: Locale(identifier: "en_US")) == "2",
               "seconds read without a trailing zero")

        // The combinations other shortcut fields see as taken
        let suiteName = "com.vorssaint.tests.macros"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.set(MacroSupport.encode([macro, second]), forKey: DefaultsKey.macros)
            expect(MacroSupport.triggers(defaults: defaults).isEmpty,
                   "macros claim nothing while the feature is not installed")
            defaults.set(true, forKey: AppFeature.macros.availabilityKey)
            expect(MacroSupport.triggers(defaults: defaults).isEmpty,
                   "macros claim nothing while switched off")
            defaults.set(true, forKey: DefaultsKey.macrosEnabled)
            expect(MacroSupport.triggers(defaults: defaults) == [trigger, otherTrigger],
                   "installed and switched on, each macro claims its combination")
            defaults.removePersistentDomain(forName: suiteName)
        }

        // Catalog
        expect(AppFeature.macros.group == .tools && !AppFeature.macros.installedByDefault
               && AppFeature.macros.permissions == [.accessibility]
               && AppFeature.macros.enabledKeys == [DefaultsKey.macrosEnabled]
               && AppFeature.macros.energyProfile == .idle,
               "macros are an opt-in tool that needs Accessibility and costs nothing at rest")
        expect(Defaults.registeredDefaults[DefaultsKey.macrosEnabled] as? Bool == false,
               "macros start switched off")
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.macros, DefaultsKey.macrosEnabled,
                                                                 AppFeature.macros.availabilityKey]),
               "the macro list, its switch and its availability travel with a settings backup")
        expect(GlobalShortcutRole.featuresToSilenceWhileRecording.contains(.macros),
               "macro keys step aside while a shortcut field is listening")
        expect(AppFeature.macros.settingsDestination == FeatureSettingsDestination(.macros)
               && FeatureVisibilitySupport.features(for: .macros) == [.macros],
               "macros have a Settings page of their own that follows the feature")

        // Strings
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.macros(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == Mirror(reflecting: strings).children.count
                   && values.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "every macro string is present and avoids em-dashes (\(language.rawValue))")
            expect(Set(MacroStep.Kind.allCases.map(strings.title)).count == MacroStep.Kind.allCases.count
                   && Set(MacroSupport.TypingSpeed.allCases.map(strings.title)).count
                       == MacroSupport.TypingSpeed.allCases.count,
                   "step kinds and typing speeds each read differently (\(language.rawValue))")
        }
    }
}
