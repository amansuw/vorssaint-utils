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
              {"id":"\(UUID().uuidString)","kind":"teleport","x":10},
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

        // Password steps
        let typePassword = MacroStep(kind: .password)
        let withPassword = Macro(shortcut: trigger.storageValue, steps: [typeHello, typePassword])
        let encodedPassword = MacroSupport.encode([withPassword]).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        expect(MacroSupport.decode(MacroSupport.encode([withPassword])) == [withPassword]
               && encodedPassword.contains("\"kind\":\"password\""),
               "a password step is stored as a step of its own kind")
        expect(Mirror(reflecting: typePassword).children.allSatisfy { ($0.label ?? "") != "password" },
               "a password step has nowhere to hold the password, so it cannot reach preferences or a backup")
        let olderPasswordStep = """
            [{"id":"\(macro.id.uuidString)","steps":[{"id":"\(typePassword.id.uuidString)","kind":"password"}]}]
            """
        expect(MacroSupport.decode(Data(olderPasswordStep.utf8)).first?.steps.first?.passwordFieldOnly == true,
               "a password step that does not say otherwise only types into password fields")
        expect(MacroSupport.isRunnable(typePassword)
               && MacroSupport.registrations([Macro(shortcut: trigger.storageValue, steps: [typePassword])]).count == 1,
               "a password step is something to run, so a macro made only of one still registers")
        expect(MacroSupport.sanitized(withPassword, hasPassword: { _ in false }).steps == [typeHello]
               && MacroSupport.sanitized(withPassword, hasPassword: { $0 == typePassword.id }).steps
                   == [typeHello, typePassword],
               "saving drops a password step with no password and keeps one that has it")
        expect(MacroSupport.typedPassword("pa\nss\r\nword") == "password"
               && MacroSupport.typedPassword("p@ss wörd 🔑") == "p@ss wörd 🔑",
               "a password is typed as one line and otherwise exactly as saved")
        expect(MacroSupport.isPasswordField(role: "AXTextField", subrole: "AXSecureTextField", secureInput: false)
               && MacroSupport.isPasswordField(role: "AXSecureTextField", subrole: nil, secureInput: false),
               "a field that says it is a password field is one, whatever secure input says")
        expect(!MacroSupport.isPasswordField(role: "AXTextField", subrole: nil, secureInput: true)
               && !MacroSupport.isPasswordField(role: "AXTextArea", subrole: nil, secureInput: true)
               && !MacroSupport.isPasswordField(role: "AXComboBox", subrole: "AXSearchField", secureInput: true),
               "a visible text field is never a password field, even while secure input is on")
        expect(MacroSupport.isPasswordField(role: nil, subrole: nil, secureInput: true)
               && !MacroSupport.isPasswordField(role: nil, subrole: nil, secureInput: false)
               && MacroSupport.isPasswordField(role: "AXWebArea", subrole: nil, secureInput: true)
               && !MacroSupport.isPasswordField(role: "AXWebArea", subrole: nil, secureInput: false),
               "when the focused element is unknown or is not a text field, secure input decides")

        // Open and click steps
        func link(_ text: String) -> String? { MacroSupport.openURL(from: text)?.absoluteString }
        expect(link("https://example.com/a?b=1") == "https://example.com/a?b=1"
               && link("example.com/page") == "https://example.com/page"
               && link("mailto:someone@example.com") == "mailto:someone@example.com"
               && link("slack://open") == "slack://open"
               && link("x-apple.systempreferences:com.apple.preference.security")
                   == "x-apple.systempreferences:com.apple.preference.security",
               "a link keeps the scheme it was typed with and a bare site opens over https")
        expect(link("localhost:3000") == "http://localhost:3000"
               && link("example.com:8080/x") == "https://example.com:8080/x",
               "a host with a port is a site, not a scheme")
        expect(MacroSupport.openURL(from: "/Applications")?.isFileURL == true
               && MacroSupport.openURL(from: "~/Documents")?.path.hasSuffix("/Documents") == true
               && MacroSupport.openURL(from: "~/Documents")?.path.hasPrefix("/") == true,
               "a path opens that file or folder, with the home folder spelled out")
        expect(link("") == nil && link("   ") == nil && link("hello") == nil && link("two words.com") == nil,
               "text that is neither an address nor a path opens nothing")
        expect(MacroSupport.isRunnable(MacroStep(kind: .open, app: "com.apple.Safari"))
               && MacroSupport.isRunnable(MacroStep(kind: .open, link: "example.com"))
               && !MacroSupport.isRunnable(MacroStep(kind: .open))
               && !MacroSupport.isRunnable(MacroStep(kind: .open, link: "nonsense"))
               && MacroSupport.isRunnable(MacroStep(kind: .click)),
               "an open step needs an app or a usable link, and a click always has something to do")
        let futureClick = """
            [{"id":"\(macro.id.uuidString)","repeatCount":3,"apps":["com.apple.Safari"],"steps":[
              {"id":"\(UUID().uuidString)","kind":"click","click":"triple"},
              {"id":"\(UUID().uuidString)","kind":"click","click":"right"},
              {"id":"\(UUID().uuidString)","kind":"open","app":"com.apple.Notes"}]}]
            """
        let future = MacroSupport.decode(Data(futureClick.utf8)).first
        expect(future?.steps.map(\.click) == [.left, .right, .left] && future?.steps.last?.app == "com.apple.Notes"
               && future?.repeatCount == 3 && future?.apps == ["com.apple.Safari"],
               "a click of an unknown kind is still a click, and repeat and apps are read back")
        expect(tolerant.first?.repeatCount == 1 && tolerant.first?.apps == [],
               "a macro saved before repeat and app limits plays once, everywhere")
        let wild = MacroSupport.sanitized(Macro(steps: [typeHello], repeatCount: 5000,
                                                apps: ["a.b", "", "a.b", "c.d"]))
        expect(wild.repeatCount == MacroSupport.repeatRange.upperBound && wild.apps == ["a.b", "c.d"]
               && MacroSupport.sanitized(Macro(steps: [typeHello], repeatCount: -4)).repeatCount == 1,
               "saving bounds the repeat count and keeps each app once")
        expect(MacroSupport.usesVariables("Today is {{date}}") && !MacroSupport.usesVariables("plain {text}"),
               "only text with a variable marker is expanded before typing")

        // App limits
        var inSafari = macro
        inSafari.id = UUID()
        inSafari.apps = ["com.apple.Safari"]
        var inNotes = macro
        inNotes.id = UUID()
        inNotes.apps = ["com.apple.Notes"]
        expect(MacroSupport.applies(macro, inApp: nil) && MacroSupport.applies(macro, inApp: "any.app")
               && MacroSupport.applies(inSafari, inApp: "com.apple.Safari")
               && !MacroSupport.applies(inSafari, inApp: "com.apple.Notes")
               && !MacroSupport.applies(inSafari, inApp: nil),
               "a macro without apps works everywhere and a limited one only in its apps")
        expect(MacroSupport.registrations([macro, inSafari], frontmostBundleID: "com.apple.Safari").map(\.macro.id)
                   == [inSafari.id]
               && MacroSupport.registrations([macro, inSafari], frontmostBundleID: "com.apple.Notes").map(\.macro.id)
                   == [macro.id]
               && MacroSupport.registrations([inSafari, inNotes], frontmostBundleID: "com.apple.Mail").isEmpty,
               "in its own app a limited macro takes the combination from one that works everywhere")
        expect(MacroSupport.followsFrontmostApp([macro, inSafari]) && !MacroSupport.followsFrontmostApp([macro]),
               "the app in front is only followed while a macro is limited to apps")
        expect(MacroSupport.macro(using: trigger, apps: [], in: [macro, inSafari], excluding: UUID())?.id == macro.id
               && MacroSupport.macro(using: trigger, apps: ["com.apple.Mail"], in: [macro, inSafari],
                                     excluding: UUID()) == nil
               && MacroSupport.macro(using: trigger, apps: ["com.apple.Safari", "com.apple.Mail"],
                                     in: [macro, inSafari], excluding: UUID())?.id == inSafari.id
               && MacroSupport.macro(using: trigger, apps: ["com.apple.Notes"], in: [inSafari],
                                     excluding: UUID()) == nil,
               "two macros clash on a combination only where both would answer")

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
            defaults.set(MacroSupport.encode([inSafari, disabled, empty]), forKey: DefaultsKey.macros)
            expect(MacroSupport.triggers(defaults: defaults) == [trigger]
                   && MacroSupport.owner(of: trigger, defaults: defaults)?.id == inSafari.id
                   && MacroSupport.ownerTitle(of: trigger, defaults: defaults) == "Greeting"
                   && MacroSupport.owner(of: otherTrigger, defaults: defaults) == nil,
                   "another shortcut field sees a combination as taken by any macro that can answer to it")
            expect(MacroSupport.runnableMacros(defaults: defaults).map(\.id) == [inSafari.id]
                   && MacroSupport.runnableMacro(withID: disabled.id, defaults: defaults) == nil,
                   "only macros that are switched on and have steps are offered to the bar and the wheel")
            defaults.set(false, forKey: DefaultsKey.macrosEnabled)
            expect(MacroSupport.owner(of: trigger, defaults: defaults) == nil
                   && MacroSupport.runnableMacros(defaults: defaults).isEmpty,
                   "with macros switched off nothing is taken and nothing is offered")
            defaults.removePersistentDomain(forName: suiteName)
        }

        // On the radial menu
        let slice = RadialMenuItem(kind: .macro, payload: macro.id.uuidString)
        expect(RadialMenuSupport.isValidPayload(slice) && slice.macroID == macro.id
               && !RadialMenuSupport.isValidPayload(RadialMenuItem(kind: .macro, payload: "not an id"))
               && RadialMenuSupport.sanitized([slice, RadialMenuItem(kind: .macro, payload: "")]).map(\.id) == [slice.id],
               "a wheel slice can run a macro by its id, and one without an id is dropped")
        expect(RadialMenuSupport.needsAccessibility([slice]),
               "a wheel that runs a macro needs Accessibility")
        expect(RadialMenuSupport.decode(RadialMenuSupport.encode([slice])).first?.kind == .macro,
               "a macro slice survives being saved and read back")

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
            expect(Set(MacroStep.Click.allCases.map(strings.title)).count == MacroStep.Click.allCases.count,
                   "each kind of click reads differently (\(language.rawValue))")
            expect(Set(MacroStep.Kind.allCases.map(strings.title)).count == MacroStep.Kind.allCases.count
                   && Set(MacroSupport.TypingSpeed.allCases.map(strings.title)).count
                       == MacroSupport.TypingSpeed.allCases.count,
                   "step kinds and typing speeds each read differently (\(language.rawValue))")
        }
    }
}
