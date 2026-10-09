// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MacroFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let emptyList: String
    let addButton: String
    let manageButton: String
    let newTitle: String
    let editTitle: String
    let nameLabel: String
    let namePlaceholder: String
    let untitled: String
    let shortcutLabel: String
    let noShortcutNote: String
    let typingSpeedLabel: String
    let speedInstant: String
    let speedFast: String
    let speedNatural: String
    let speedSlow: String
    let typingSpeedCaption: String
    let stepsTitle: String
    let addStepButton: String
    let stepText: String
    let stepKeys: String
    let stepWait: String
    let textPlaceholder: String
    let recordKeys: String
    let specialKeyMenu: String
    let secondsUnit: String
    let moveUp: String
    let moveDown: String
    let removeStep: String

    func title(_ kind: MacroStep.Kind) -> String {
        switch kind {
        case .text: return stepText
        case .keys: return stepKeys
        case .wait: return stepWait
        }
    }

    func title(_ speed: MacroSupport.TypingSpeed) -> String {
        switch speed {
        case .instant: return speedInstant
        case .fast: return speedFast
        case .natural: return speedNatural
        case .slow: return speedSlow
        }
    }
}

extension FeatureStrings {
    static func macros(_ language: AppLanguage) -> MacroFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension MacroFeatureStrings {
    static let enUS = MacroFeatureStrings(
        pageTitle: "Macros",
        hubDescription: "One shortcut types text, presses keys and waits, in order",
        enable: "Run macros from shortcuts",
        enableCaption: "A macro plays its steps in order in the app in front. Press any macro shortcut while one is running to stop it.",
        emptyList: "No macros yet. Add the first one.",
        addButton: "Add macro",
        manageButton: "Manage macros",
        newTitle: "New macro",
        editTitle: "Edit macro",
        nameLabel: "Name",
        namePlaceholder: "Sign-off",
        untitled: "Untitled macro",
        shortcutLabel: "Shortcut",
        noShortcutNote: "Add a shortcut to run this macro.",
        typingSpeedLabel: "Typing speed",
        speedInstant: "All at once",
        speedFast: "Fast",
        speedNatural: "Natural",
        speedSlow: "Slow",
        typingSpeedCaption: "Any speed other than All at once types one character at a time and presses Return at each line break.",
        stepsTitle: "Steps",
        addStepButton: "Add step",
        stepText: "Type text",
        stepKeys: "Press keys",
        stepWait: "Wait",
        textPlaceholder: "Text to type",
        recordKeys: "Record keys",
        specialKeyMenu: "Special key",
        secondsUnit: "seconds",
        moveUp: "Move up",
        moveDown: "Move down",
        removeStep: "Remove step"
    )

    static let ptBR = MacroFeatureStrings(
        pageTitle: "Macros",
        hubDescription: "Um atalho digita texto, pressiona teclas e espera, em ordem",
        enable: "Executar macros por atalhos",
        enableCaption: "Uma macro executa seus passos em ordem no app em primeiro plano. Pressione qualquer atalho de macro durante a execução para interrompê-la.",
        emptyList: "Nenhuma macro ainda. Adicione a primeira.",
        addButton: "Adicionar macro",
        manageButton: "Gerenciar macros",
        newTitle: "Nova macro",
        editTitle: "Editar macro",
        nameLabel: "Nome",
        namePlaceholder: "Assinatura",
        untitled: "Macro sem título",
        shortcutLabel: "Atalho",
        noShortcutNote: "Adicione um atalho para executar esta macro.",
        typingSpeedLabel: "Velocidade de digitação",
        speedInstant: "Tudo de uma vez",
        speedFast: "Rápida",
        speedNatural: "Natural",
        speedSlow: "Lenta",
        typingSpeedCaption: "Qualquer velocidade além de Tudo de uma vez digita um caractere por vez e pressiona Return a cada quebra de linha.",
        stepsTitle: "Passos",
        addStepButton: "Adicionar passo",
        stepText: "Digitar texto",
        stepKeys: "Pressionar teclas",
        stepWait: "Esperar",
        textPlaceholder: "Texto a digitar",
        recordKeys: "Gravar teclas",
        specialKeyMenu: "Tecla especial",
        secondsUnit: "segundos",
        moveUp: "Mover para cima",
        moveDown: "Mover para baixo",
        removeStep: "Remover passo"
    )

    static let tr = MacroFeatureStrings(
        pageTitle: "Makrolar",
        hubDescription: "Tek kısayol sırayla metin yazar, tuşlara basar ve bekler",
        enable: "Makroları kısayollarla çalıştır",
        enableCaption: "Makro, adımlarını öndeki uygulamada sırayla oynatır. Biri çalışırken durdurmak için herhangi bir makro kısayoluna basın.",
        emptyList: "Henüz makro yok. İlkini ekleyin.",
        addButton: "Makro ekle",
        manageButton: "Makroları yönet",
        newTitle: "Yeni makro",
        editTitle: "Makroyu düzenle",
        nameLabel: "Ad",
        namePlaceholder: "İmza",
        untitled: "Adsız makro",
        shortcutLabel: "Kısayol",
        noShortcutNote: "Bu makroyu çalıştırmak için bir kısayol ekleyin.",
        typingSpeedLabel: "Yazma hızı",
        speedInstant: "Hepsi birden",
        speedFast: "Hızlı",
        speedNatural: "Doğal",
        speedSlow: "Yavaş",
        typingSpeedCaption: "Hepsi birden dışındaki hızlar karakterleri tek tek yazar ve her satır sonunda Return tuşuna basar.",
        stepsTitle: "Adımlar",
        addStepButton: "Adım ekle",
        stepText: "Metin yaz",
        stepKeys: "Tuşlara bas",
        stepWait: "Bekle",
        textPlaceholder: "Yazılacak metin",
        recordKeys: "Tuşları kaydet",
        specialKeyMenu: "Özel tuş",
        secondsUnit: "saniye",
        moveUp: "Yukarı taşı",
        moveDown: "Aşağı taşı",
        removeStep: "Adımı kaldır"
    )

    static let ru = MacroFeatureStrings(
        pageTitle: "Макросы",
        hubDescription: "Одно сочетание по порядку печатает текст, нажимает клавиши и ждёт",
        enable: "Запускать макросы сочетаниями клавиш",
        enableCaption: "Макрос выполняет шаги по порядку в активном приложении. Чтобы остановить его, нажмите сочетание любого макроса во время выполнения.",
        emptyList: "Макросов пока нет. Добавьте первый.",
        addButton: "Добавить макрос",
        manageButton: "Управление макросами",
        newTitle: "Новый макрос",
        editTitle: "Изменить макрос",
        nameLabel: "Название",
        namePlaceholder: "Подпись",
        untitled: "Макрос без названия",
        shortcutLabel: "Сочетание клавиш",
        noShortcutNote: "Добавьте сочетание клавиш, чтобы запускать этот макрос.",
        typingSpeedLabel: "Скорость печати",
        speedInstant: "Всё сразу",
        speedFast: "Быстро",
        speedNatural: "Естественно",
        speedSlow: "Медленно",
        typingSpeedCaption: "Любая скорость, кроме «Всё сразу», печатает по одному символу и нажимает Return на каждом переносе строки.",
        stepsTitle: "Шаги",
        addStepButton: "Добавить шаг",
        stepText: "Напечатать текст",
        stepKeys: "Нажать клавиши",
        stepWait: "Подождать",
        textPlaceholder: "Текст для печати",
        recordKeys: "Записать клавиши",
        specialKeyMenu: "Особая клавиша",
        secondsUnit: "сек.",
        moveUp: "Переместить вверх",
        moveDown: "Переместить вниз",
        removeStep: "Удалить шаг"
    )

    static let es = MacroFeatureStrings(
        pageTitle: "Macros",
        hubDescription: "Un atajo escribe texto, pulsa teclas y espera, en orden",
        enable: "Ejecutar macros con atajos",
        enableCaption: "Una macro reproduce sus pasos en orden en la app que está en primer plano. Pulsa cualquier atajo de macro mientras se ejecuta una para detenerla.",
        emptyList: "Aún no hay macros. Añade la primera.",
        addButton: "Añadir macro",
        manageButton: "Gestionar macros",
        newTitle: "Nueva macro",
        editTitle: "Editar macro",
        nameLabel: "Nombre",
        namePlaceholder: "Firma",
        untitled: "Macro sin título",
        shortcutLabel: "Atajo",
        noShortcutNote: "Añade un atajo para ejecutar esta macro.",
        typingSpeedLabel: "Velocidad de escritura",
        speedInstant: "Todo de una vez",
        speedFast: "Rápida",
        speedNatural: "Natural",
        speedSlow: "Lenta",
        typingSpeedCaption: "Cualquier velocidad distinta de Todo de una vez escribe un carácter cada vez y pulsa Retorno en cada salto de línea.",
        stepsTitle: "Pasos",
        addStepButton: "Añadir paso",
        stepText: "Escribir texto",
        stepKeys: "Pulsar teclas",
        stepWait: "Esperar",
        textPlaceholder: "Texto que escribir",
        recordKeys: "Grabar teclas",
        specialKeyMenu: "Tecla especial",
        secondsUnit: "segundos",
        moveUp: "Subir",
        moveDown: "Bajar",
        removeStep: "Eliminar paso"
    )

    static let sk = MacroFeatureStrings(
        pageTitle: "Makrá",
        hubDescription: "Jedna skratka postupne píše text, stláča klávesy a čaká",
        enable: "Spúšťať makrá skratkami",
        enableCaption: "Makro prehrá svoje kroky v poradí v aplikácii v popredí. Ak chcete bežiace makro zastaviť, stlačte skratku ľubovoľného makra.",
        emptyList: "Zatiaľ žiadne makrá. Pridajte prvé.",
        addButton: "Pridať makro",
        manageButton: "Spravovať makrá",
        newTitle: "Nové makro",
        editTitle: "Upraviť makro",
        nameLabel: "Názov",
        namePlaceholder: "Podpis",
        untitled: "Makro bez názvu",
        shortcutLabel: "Skratka",
        noShortcutNote: "Pridajte skratku, ktorou sa toto makro spustí.",
        typingSpeedLabel: "Rýchlosť písania",
        speedInstant: "Všetko naraz",
        speedFast: "Rýchlo",
        speedNatural: "Prirodzene",
        speedSlow: "Pomaly",
        typingSpeedCaption: "Každá rýchlosť okrem Všetko naraz píše po jednom znaku a pri každom zalomení riadka stlačí Return.",
        stepsTitle: "Kroky",
        addStepButton: "Pridať krok",
        stepText: "Napísať text",
        stepKeys: "Stlačiť klávesy",
        stepWait: "Počkať",
        textPlaceholder: "Text na napísanie",
        recordKeys: "Nahrať klávesy",
        specialKeyMenu: "Špeciálny kláves",
        secondsUnit: "sekúnd",
        moveUp: "Posunúť nahor",
        moveDown: "Posunúť nadol",
        removeStep: "Odstrániť krok"
    )

    static let de = MacroFeatureStrings(
        pageTitle: "Makros",
        hubDescription: "Ein Kurzbefehl tippt Text, drückt Tasten und wartet, der Reihe nach",
        enable: "Makros per Kurzbefehl ausführen",
        enableCaption: "Ein Makro spielt seine Schritte der Reihe nach in der vorderen App ab. Drücke während der Ausführung einen beliebigen Makro-Kurzbefehl, um es zu stoppen.",
        emptyList: "Noch keine Makros. Füge das erste hinzu.",
        addButton: "Makro hinzufügen",
        manageButton: "Makros verwalten",
        newTitle: "Neues Makro",
        editTitle: "Makro bearbeiten",
        nameLabel: "Name",
        namePlaceholder: "Grußformel",
        untitled: "Unbenanntes Makro",
        shortcutLabel: "Kurzbefehl",
        noShortcutNote: "Füge einen Kurzbefehl hinzu, um dieses Makro auszuführen.",
        typingSpeedLabel: "Tippgeschwindigkeit",
        speedInstant: "Alles auf einmal",
        speedFast: "Schnell",
        speedNatural: "Natürlich",
        speedSlow: "Langsam",
        typingSpeedCaption: "Jede Geschwindigkeit außer „Alles auf einmal“ tippt Zeichen für Zeichen und drückt bei jedem Zeilenumbruch den Zeilenschalter.",
        stepsTitle: "Schritte",
        addStepButton: "Schritt hinzufügen",
        stepText: "Text tippen",
        stepKeys: "Tasten drücken",
        stepWait: "Warten",
        textPlaceholder: "Zu tippender Text",
        recordKeys: "Tasten aufnehmen",
        specialKeyMenu: "Sondertaste",
        secondsUnit: "Sekunden",
        moveUp: "Nach oben",
        moveDown: "Nach unten",
        removeStep: "Schritt entfernen"
    )

    static let fr = MacroFeatureStrings(
        pageTitle: "Macros",
        hubDescription: "Un raccourci saisit du texte, appuie sur des touches et attend, dans l’ordre",
        enable: "Lancer des macros avec des raccourcis",
        enableCaption: "Une macro joue ses étapes dans l’ordre dans l’app au premier plan. Appuyez sur n’importe quel raccourci de macro pendant l’exécution pour l’arrêter.",
        emptyList: "Aucune macro pour l’instant. Ajoutez la première.",
        addButton: "Ajouter une macro",
        manageButton: "Gérer les macros",
        newTitle: "Nouvelle macro",
        editTitle: "Modifier la macro",
        nameLabel: "Nom",
        namePlaceholder: "Signature",
        untitled: "Macro sans titre",
        shortcutLabel: "Raccourci",
        noShortcutNote: "Ajoutez un raccourci pour lancer cette macro.",
        typingSpeedLabel: "Vitesse de saisie",
        speedInstant: "Tout d’un coup",
        speedFast: "Rapide",
        speedNatural: "Naturelle",
        speedSlow: "Lente",
        typingSpeedCaption: "Toute vitesse autre que Tout d’un coup saisit un caractère à la fois et appuie sur Retour à chaque saut de ligne.",
        stepsTitle: "Étapes",
        addStepButton: "Ajouter une étape",
        stepText: "Saisir du texte",
        stepKeys: "Appuyer sur des touches",
        stepWait: "Attendre",
        textPlaceholder: "Texte à saisir",
        recordKeys: "Enregistrer les touches",
        specialKeyMenu: "Touche spéciale",
        secondsUnit: "secondes",
        moveUp: "Monter",
        moveDown: "Descendre",
        removeStep: "Supprimer l’étape"
    )

    static let it = MacroFeatureStrings(
        pageTitle: "Macro",
        hubDescription: "Una scorciatoia digita testo, preme tasti e attende, in ordine",
        enable: "Esegui le macro con le scorciatoie",
        enableCaption: "Una macro esegue i suoi passaggi in ordine nell’app in primo piano. Premi una qualsiasi scorciatoia di macro durante l’esecuzione per fermarla.",
        emptyList: "Ancora nessuna macro. Aggiungi la prima.",
        addButton: "Aggiungi macro",
        manageButton: "Gestisci macro",
        newTitle: "Nuova macro",
        editTitle: "Modifica macro",
        nameLabel: "Nome",
        namePlaceholder: "Firma",
        untitled: "Macro senza titolo",
        shortcutLabel: "Scorciatoia",
        noShortcutNote: "Aggiungi una scorciatoia per eseguire questa macro.",
        typingSpeedLabel: "Velocità di digitazione",
        speedInstant: "Tutto insieme",
        speedFast: "Veloce",
        speedNatural: "Naturale",
        speedSlow: "Lenta",
        typingSpeedCaption: "Ogni velocità diversa da Tutto insieme digita un carattere alla volta e preme Invio a ogni interruzione di riga.",
        stepsTitle: "Passaggi",
        addStepButton: "Aggiungi passaggio",
        stepText: "Digita testo",
        stepKeys: "Premi tasti",
        stepWait: "Attendi",
        textPlaceholder: "Testo da digitare",
        recordKeys: "Registra tasti",
        specialKeyMenu: "Tasto speciale",
        secondsUnit: "secondi",
        moveUp: "Sposta su",
        moveDown: "Sposta giù",
        removeStep: "Rimuovi passaggio"
    )

    static let ja = MacroFeatureStrings(
        pageTitle: "マクロ",
        hubDescription: "1つのショートカットで、文字入力・キー操作・待機を順番に実行",
        enable: "ショートカットでマクロを実行",
        enableCaption: "マクロは最前面のアプリでステップを順番に実行します。実行中にいずれかのマクロのショートカットを押すと停止します。",
        emptyList: "マクロはまだありません。最初の1つを追加してください。",
        addButton: "マクロを追加",
        manageButton: "マクロを管理",
        newTitle: "新規マクロ",
        editTitle: "マクロを編集",
        nameLabel: "名前",
        namePlaceholder: "署名",
        untitled: "名称未設定のマクロ",
        shortcutLabel: "ショートカット",
        noShortcutNote: "このマクロを実行するショートカットを追加してください。",
        typingSpeedLabel: "入力速度",
        speedInstant: "一度に入力",
        speedFast: "速い",
        speedNatural: "自然",
        speedSlow: "遅い",
        typingSpeedCaption: "「一度に入力」以外の速度では1文字ずつ入力し、改行のたびにReturnキーを押します。",
        stepsTitle: "ステップ",
        addStepButton: "ステップを追加",
        stepText: "テキストを入力",
        stepKeys: "キーを押す",
        stepWait: "待機",
        textPlaceholder: "入力するテキスト",
        recordKeys: "キーを記録",
        specialKeyMenu: "特殊キー",
        secondsUnit: "秒",
        moveUp: "上へ移動",
        moveDown: "下へ移動",
        removeStep: "ステップを削除"
    )

    static let ko = MacroFeatureStrings(
        pageTitle: "매크로",
        hubDescription: "단축키 하나로 텍스트 입력, 키 누르기, 대기를 순서대로 실행",
        enable: "단축키로 매크로 실행",
        enableCaption: "매크로는 맨 앞의 앱에서 단계를 순서대로 실행합니다. 실행 중에 아무 매크로 단축키나 누르면 중단됩니다.",
        emptyList: "아직 매크로가 없습니다. 첫 번째 매크로를 추가하세요.",
        addButton: "매크로 추가",
        manageButton: "매크로 관리",
        newTitle: "새로운 매크로",
        editTitle: "매크로 편집",
        nameLabel: "이름",
        namePlaceholder: "서명",
        untitled: "제목 없는 매크로",
        shortcutLabel: "단축키",
        noShortcutNote: "이 매크로를 실행할 단축키를 추가하세요.",
        typingSpeedLabel: "입력 속도",
        speedInstant: "한 번에",
        speedFast: "빠르게",
        speedNatural: "자연스럽게",
        speedSlow: "느리게",
        typingSpeedCaption: "‘한 번에’가 아닌 속도에서는 한 글자씩 입력하고 줄바꿈마다 Return 키를 누릅니다.",
        stepsTitle: "단계",
        addStepButton: "단계 추가",
        stepText: "텍스트 입력",
        stepKeys: "키 누르기",
        stepWait: "대기",
        textPlaceholder: "입력할 텍스트",
        recordKeys: "키 기록",
        specialKeyMenu: "특수 키",
        secondsUnit: "초",
        moveUp: "위로 이동",
        moveDown: "아래로 이동",
        removeStep: "단계 제거"
    )

    static let zhHans = MacroFeatureStrings(
        pageTitle: "宏",
        hubDescription: "一个快捷键按顺序输入文本、按键和等待",
        enable: "用快捷键运行宏",
        enableCaption: "宏会在最前面的 App 中按顺序执行各个步骤。运行期间按下任意宏的快捷键即可停止。",
        emptyList: "还没有宏。添加第一个吧。",
        addButton: "添加宏",
        manageButton: "管理宏",
        newTitle: "新建宏",
        editTitle: "编辑宏",
        nameLabel: "名称",
        namePlaceholder: "落款",
        untitled: "未命名宏",
        shortcutLabel: "快捷键",
        noShortcutNote: "添加快捷键才能运行此宏。",
        typingSpeedLabel: "输入速度",
        speedInstant: "一次输入",
        speedFast: "快",
        speedNatural: "自然",
        speedSlow: "慢",
        typingSpeedCaption: "除“一次输入”外，其他速度会逐个字符输入，并在每个换行处按下 Return 键。",
        stepsTitle: "步骤",
        addStepButton: "添加步骤",
        stepText: "输入文本",
        stepKeys: "按下按键",
        stepWait: "等待",
        textPlaceholder: "要输入的文本",
        recordKeys: "录制按键",
        specialKeyMenu: "特殊键",
        secondsUnit: "秒",
        moveUp: "上移",
        moveDown: "下移",
        removeStep: "移除步骤"
    )

    static let zhTW = MacroFeatureStrings(
        pageTitle: "巨集",
        hubDescription: "一組快速鍵依序輸入文字、按下按鍵與等待",
        enable: "以快速鍵執行巨集",
        enableCaption: "巨集會在最前方的 App 中依序執行各個步驟。執行期間按下任一巨集的快速鍵即可停止。",
        emptyList: "尚無巨集。加入第一個吧。",
        addButton: "加入巨集",
        manageButton: "管理巨集",
        newTitle: "新增巨集",
        editTitle: "編輯巨集",
        nameLabel: "名稱",
        namePlaceholder: "署名",
        untitled: "未命名巨集",
        shortcutLabel: "快速鍵",
        noShortcutNote: "加入快速鍵才能執行此巨集。",
        typingSpeedLabel: "輸入速度",
        speedInstant: "一次輸入",
        speedFast: "快",
        speedNatural: "自然",
        speedSlow: "慢",
        typingSpeedCaption: "除「一次輸入」外，其他速度會逐字輸入，並在每個換行處按下 Return 鍵。",
        stepsTitle: "步驟",
        addStepButton: "加入步驟",
        stepText: "輸入文字",
        stepKeys: "按下按鍵",
        stepWait: "等待",
        textPlaceholder: "要輸入的文字",
        recordKeys: "錄製按鍵",
        specialKeyMenu: "特殊鍵",
        secondsUnit: "秒",
        moveUp: "上移",
        moveDown: "下移",
        removeStep: "移除步驟"
    )

    static let zhHK = MacroFeatureStrings(
        pageTitle: "巨集",
        hubDescription: "一組快捷鍵依次輸入文字、按下按鍵與等待",
        enable: "以快捷鍵執行巨集",
        enableCaption: "巨集會在最前方的 App 中依次執行各個步驟。執行期間按下任何巨集的快捷鍵即可停止。",
        emptyList: "尚未有巨集。加入第一個吧。",
        addButton: "加入巨集",
        manageButton: "管理巨集",
        newTitle: "新增巨集",
        editTitle: "編輯巨集",
        nameLabel: "名稱",
        namePlaceholder: "署名",
        untitled: "未命名巨集",
        shortcutLabel: "快捷鍵",
        noShortcutNote: "加入快捷鍵才能執行此巨集。",
        typingSpeedLabel: "輸入速度",
        speedInstant: "一次輸入",
        speedFast: "快",
        speedNatural: "自然",
        speedSlow: "慢",
        typingSpeedCaption: "除「一次輸入」外，其他速度會逐字輸入，並在每個換行處按下 Return 鍵。",
        stepsTitle: "步驟",
        addStepButton: "加入步驟",
        stepText: "輸入文字",
        stepKeys: "按下按鍵",
        stepWait: "等待",
        textPlaceholder: "要輸入的文字",
        recordKeys: "錄製按鍵",
        specialKeyMenu: "特殊鍵",
        secondsUnit: "秒",
        moveUp: "上移",
        moveDown: "下移",
        removeStep: "移除步驟"
    )

    static let uk = MacroFeatureStrings(
        pageTitle: "Макроси",
        hubDescription: "Одне поєднання по черзі друкує текст, натискає клавіші й чекає",
        enable: "Запускати макроси поєднаннями клавіш",
        enableCaption: "Макрос виконує кроки по черзі в активній програмі. Щоб зупинити його, натисніть поєднання будь-якого макроса під час виконання.",
        emptyList: "Макросів ще немає. Додайте перший.",
        addButton: "Додати макрос",
        manageButton: "Керувати макросами",
        newTitle: "Новий макрос",
        editTitle: "Змінити макрос",
        nameLabel: "Назва",
        namePlaceholder: "Підпис",
        untitled: "Макрос без назви",
        shortcutLabel: "Поєднання клавіш",
        noShortcutNote: "Додайте поєднання клавіш, щоб запускати цей макрос.",
        typingSpeedLabel: "Швидкість друку",
        speedInstant: "Усе одразу",
        speedFast: "Швидко",
        speedNatural: "Природно",
        speedSlow: "Повільно",
        typingSpeedCaption: "Будь-яка швидкість, крім «Усе одразу», друкує по одному символу й натискає Return на кожному розриві рядка.",
        stepsTitle: "Кроки",
        addStepButton: "Додати крок",
        stepText: "Надрукувати текст",
        stepKeys: "Натиснути клавіші",
        stepWait: "Зачекати",
        textPlaceholder: "Текст для друку",
        recordKeys: "Записати клавіші",
        specialKeyMenu: "Особлива клавіша",
        secondsUnit: "с",
        moveUp: "Перемістити вгору",
        moveDown: "Перемістити вниз",
        removeStep: "Вилучити крок"
    )
}
