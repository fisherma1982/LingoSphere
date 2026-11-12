//
//  SquirrelInputController.swift
//  Squirrel
//
//  Created by Leo Liu on 5/7/24.
//

import InputMethodKit

final class SquirrelInputController: IMKInputController {
  private static let keyRollOver = 50
  private static var unknownAppCnt: UInt = 0

  private enum CandidateTranslationMenuTag {
    static let english = 41_001
    static let japanese = 41_002
    static let korean = 41_003
    static let german = 41_004
    static let spanish = 41_005
    static let portuguese = 41_006
    static let french = 41_007
    static let commitTranslation = 41_097
    static let disable = 41_098
    static let manage = 41_099
  }

  private weak var client: IMKTextInput?
  private let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
  private var preedit: String = ""
  private var selRange: NSRange = .empty
  private var caretPos: Int = 0
  private var lastModifiers: NSEvent.ModifierFlags = .init()
  private var session: RimeSessionId = 0
  private var schemaId: String = ""
  private var inlinePreedit = false
  private var inlineCandidate = false
  private var chordKeyCodes: [UInt32] = .init(repeating: 0, count: SquirrelInputController.keyRollOver)
  private var chordModifiers: [UInt32] = .init(repeating: 0, count: SquirrelInputController.keyRollOver)
  private var chordKeyCount: Int = 0
  private var chordTimer: Timer?
  private var chordDuration: TimeInterval = 0
  private var currentApp: String = ""
  // Candidates the user chose to insert as their translation. A choice that
  // only covers part of the input stays here until Rime commits the whole
  // composition, at which point each source text is replaced in order.
  private var pendingTranslationSubstitutions: [(source: String, translation: String)] = []
  private var lastCommitEndedWithTranslatedWord = false
  // Shown in place of the candidate list while the user chooses which of a
  // candidate's several translations to insert.
  private var sensePicker: (candidateIndex: Int, source: String, senses: [String], highlighted: Int)?

  // swiftlint:disable:next cyclomatic_complexity
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard let event = event else { return false }
    let modifiers = event.modifierFlags
    let changes = lastModifiers.symmetricDifference(modifiers)

    // Return true to consume the key event; return false to pass it to the client app.
    var handled = false

    if session == 0 || !rimeAPI.find_session(session) {
      createSession()
      if session == 0 {
        return false
      }
    }

    self.client ?= sender as? IMKTextInput
    if let app = client?.bundleIdentifier(), currentApp != app {
      currentApp = app
      updateAppOptions()
    }

    switch event.type {
    case .flagsChanged:
      if lastModifiers == modifiers {
        handled = true
        break
      }
      var rimeModifiers: UInt32 = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
      // Some remote desktop tools send flagsChanged with keyCode 0; infer the real modifier key when needed.
      var keyCode = event.keyCode
      if !SquirrelKeycode.modifierKeycodes.contains(keyCode) {
        guard let inferred = SquirrelKeycode.inferModifierKeycode(from: changes) else {
          lastModifiers = modifiers
          rimeUpdate()
          handled = true
          break
        }
        keyCode = inferred
      }
      let rimeKeycode: UInt32 = SquirrelKeycode.osxKeycodeToRime(keycode: keyCode, keychar: nil, shift: false, caps: false)

      if changes.contains(.capsLock) {
        // Rime expects XK_Caps_Lock before the lock mask changes; NSFlagsChanged has already applied it.
        rimeModifiers ^= kLockMask.rawValue
        _ = processKey(rimeKeycode, modifiers: rimeModifiers)
      }

      // Process releases first because some modifier releases arrive with the next keydown.
      var buffer = [(keycode: UInt32, modifier: UInt32)]()
      for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] where changes.contains(flag) {
        if modifiers.contains(flag) {
          buffer.append((keycode: rimeKeycode, modifier: rimeModifiers))
        } else {
          buffer.insert((keycode: rimeKeycode, modifier: rimeModifiers | kReleaseMask.rawValue), at: 0)
        }
      }
      for (keycode, modifier) in buffer {
        _ = processKey(keycode, modifiers: modifier)
      }

      lastModifiers = modifiers
      rimeUpdate()

    case .keyDown:
      if sensePicker != nil && handleSensePickerKey(event) {
        handled = true
        break
      }
      // Let client apps handle Command shortcuts.
      if modifiers.contains(.command) {
        break
      }

      let keyCode = event.keyCode
      // Editing the composition invalidates earlier translation choices.
      if keyCode == 51 || keyCode == 53 {  // delete, escape
        pendingTranslationSubstitutions.removeAll()
      }
      var modifiers = modifiers
      if let selection = translationSelection(for: event, modifiers: modifiers) {
        if selection.wantsTranslation && commitTranslation(ofCandidateAt: selection.index) {
          handled = true
          break
        }
        // Either the Chinese text was asked for, or no translation is known
        // yet: let Rime select the candidate as if Option were not held.
        modifiers.remove(.option)
      }
      var keyChars = event.charactersIgnoringModifiers
      let capitalModifiers = modifiers.isSubset(of: [.shift, .capsLock])
      if let code = keyChars?.first,
         (capitalModifiers && !code.isLetter) || (!capitalModifiers && !code.isASCII) {
        keyChars = event.characters
      }
      if let char = keyChars?.first {
        let rimeKeycode = SquirrelKeycode.osxKeycodeToRime(keycode: keyCode, keychar: char,
                                                           shift: modifiers.contains(.shift),
                                                           caps: modifiers.contains(.capsLock))
        if rimeKeycode != 0 {
          let rimeModifiers = SquirrelKeycode.osxModifiersToRime(modifiers: modifiers)
          handled = processKey(rimeKeycode, modifiers: rimeModifiers)
          rimeUpdate()
        }
      }
      if !handled {
        // The key goes to the application (a space, an arrow, …), so the next
        // translated word no longer directly follows the previous one.
        lastCommitEndedWithTranslatedWord = false
      }

    default:
      break
    }

    return handled
  }

  func selectCandidate(_ index: Int) -> Bool {
    if sensePicker != nil {
      // A click in the translation list chooses that translation.
      commitSense(at: index)
      return true
    }
    if #available(macOS 15.0, *),
       let translator = NSApp.squirrelAppDelegate.appleCandidateTranslator,
       MainActor.assumeIsolated({ translator.isEnabled && translator.commitsTranslation }),
       commitTranslation(ofCandidateAt: index) {
      return true
    }
    let success = rimeAPI.select_candidate_on_current_page(session, index)
    if success {
      rimeUpdate()
    }
    return success
  }

  // swiftlint:disable:next identifier_name
  func page(up: Bool) -> Bool {
    sensePicker = nil
    var handled = false
    handled = rimeAPI.change_page(session, up)
    if handled {
      rimeUpdate()
    }
    return handled
  }

  func moveCaret(forward: Bool) -> Bool {
    let currentCaretPos = rimeAPI.get_caret_pos(session)
    guard let input = rimeAPI.get_input(session) else { return false }
    if forward {
      if currentCaretPos <= 0 {
        return false
      }
      rimeAPI.set_caret_pos(session, currentCaretPos - 1)
    } else {
      let inputStr = String(cString: input)
      if currentCaretPos >= inputStr.utf8.count {
        return false
      }
      rimeAPI.set_caret_pos(session, currentCaretPos + 1)
    }
    rimeUpdate()
    return true
  }

  override func recognizedEvents(_ sender: Any!) -> Int {
    return Int(NSEvent.EventTypeMask.Element(arrayLiteral: .keyDown, .flagsChanged).rawValue)
  }

  override func activateServer(_ sender: Any!) {
    self.client ?= sender as? IMKTextInput
    var keyboardLayout = NSApp.squirrelAppDelegate.config?.getString("keyboard_layout") ?? ""
    if keyboardLayout == "last" || keyboardLayout == "" {
      keyboardLayout = ""
    } else if keyboardLayout == "default" {
      keyboardLayout = "com.apple.keylayout.ABC"
    } else if !keyboardLayout.hasPrefix("com.apple.keylayout.") {
      keyboardLayout = "com.apple.keylayout.\(keyboardLayout)"
    }
    if keyboardLayout != "" {
      client?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
    }
    // Activation delivers no flagsChanged event, and NSEvent.modifierFlags
    // only reflects this process's own event stream, so lastModifiers may
    // disagree with the actual Caps Lock state by now. Seed it from the
    // session-wide hardware state; otherwise the next Caps Lock press can
    // compare equal to the stale lastModifiers and be dropped by the
    // early-return in handle().
    if CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) {
      lastModifiers.insert(.capsLock)
    } else {
      lastModifiers.remove(.capsLock)
    }
    preedit = ""
    if session != 0 {
      let state = rimeAPI.get_option(session, "ascii_mode")
      let label = rimeAPI.get_state_label_abbreviated(session, "ascii_mode", state, true).asString
      NSApp.squirrelAppDelegate.updateStatusIcon(asciiMode: state, schemaLabel: label)
    }
  }

  override init!(server: IMKServer!, delegate: Any!, client: Any!) {
    self.client = client as? IMKTextInput
    super.init(server: server, delegate: delegate, client: client)
    createSession()

    NotificationCenter.default.addObserver(
      forName: LingoSphereIdentity.setASCIIModeNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.handleASCIIModeToggle(notification)
    }

    NotificationCenter.default.addObserver(
      forName: LingoSphereIdentity.requestASCIIModeReportNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.reportASCIIMode(notification)
    }
  }

  override func deactivateServer(_ sender: Any!) {
    hidePalettes()
    commitComposition(sender)
    client = nil
  }

  override func hidePalettes() {
    NSApp.squirrelAppDelegate.panel?.hide()
    super.hidePalettes()
  }

  override func commitComposition(_ sender: Any!) {
    self.client ?= sender as? IMKTextInput
    if session != 0 {
      if let input = rimeAPI.get_input(session) {
        pendingTranslationSubstitutions.removeAll()
        sensePicker = nil
        commit(string: String(cString: input))
        rimeAPI.clear_composition(session)
      }
    }
  }

  override func menu() -> NSMenu! {
    let menu = NSMenu()

    let productSettings = NSMenuItem(
      title: "语界设置…",
      action: #selector(showLingoSphereSettings(_:)),
      keyEquivalent: ","
    )
    productSettings.target = self
    productSettings.keyEquivalentModifierMask = [.command]
    menu.addItem(productSettings)
    menu.addItem(.separator())

    if #available(macOS 15.0, *), let translator = NSApp.squirrelAppDelegate.appleCandidateTranslator {
      let translationState = MainActor.assumeIsolated {
        (enabled: translator.isEnabled, language: translator.activeLanguage,
         commitsTranslation: translator.commitsTranslation)
      }
      let translationItem = NSMenuItem(
        title: translationState.enabled
          ? "候选翻译 · \(translationState.language.nativeName)"
          : "候选翻译 · 已关闭",
        action: nil,
        keyEquivalent: ""
      )
      // IMK's remote menu can display nested items without delivering their
      // commands. Keep translation commands in the returned root menu.
      translationItem.isEnabled = false
      menu.addItem(translationItem)
      for language in CandidateTranslationLanguage.allCases {
        let languageItem = NSMenuItem(
          title: language.menuTitle,
          action: candidateTranslationMenuAction(for: language),
          keyEquivalent: ""
        )
        languageItem.tag = candidateTranslationMenuTag(for: language)
        languageItem.target = self
        languageItem.isEnabled = true
        languageItem.state = translationState.enabled && translationState.language == language ? .on : .off
        menu.addItem(languageItem)
      }
      menu.addItem(.separator())
      let commitTranslation = NSMenuItem(
        title: "选词时上屏译文（按住 Option 则相反）",
        action: #selector(toggleTranslationCommit(_:)),
        keyEquivalent: ""
      )
      commitTranslation.tag = CandidateTranslationMenuTag.commitTranslation
      commitTranslation.target = self
      commitTranslation.isEnabled = translationState.enabled
      commitTranslation.state = translationState.commitsTranslation ? .on : .off
      menu.addItem(commitTranslation)
      let disableTranslation = NSMenuItem(
        title: "关闭候选翻译",
        action: #selector(disableCandidateTranslation(_:)),
        keyEquivalent: ""
      )
      disableTranslation.tag = CandidateTranslationMenuTag.disable
      disableTranslation.target = self
      disableTranslation.isEnabled = true
      disableTranslation.state = translationState.enabled ? .off : .on
      menu.addItem(disableTranslation)
      let manageTranslation = NSMenuItem(
        title: "管理翻译语言…",
        action: #selector(manageCandidateTranslation(_:)),
        keyEquivalent: ""
      )
      manageTranslation.tag = CandidateTranslationMenuTag.manage
      manageTranslation.target = self
      manageTranslation.isEnabled = true
      menu.addItem(manageTranslation)
    }

    return menu
  }

  override func doCommand(
    by aSelector: Selector!,
    command infoDictionary: [AnyHashable: Any]!
  ) {
    let selectorName = aSelector.map(NSStringFromSelector) ?? "<nil>"
    let selectedItem = infoDictionary?[kIMKCommandMenuItemName] as? NSMenuItem
    NSLog(
      "LingoSphere input-menu command selector=%@ tag=%ld title=%@ mainThread=%d",
      selectorName,
      selectedItem?.tag ?? 0,
      selectedItem?.title ?? "<none>",
      Thread.isMainThread
    )

    if #available(macOS 15.0, *) {
      // Recent macOS versions may preserve either the selector or the menu
      // item's tag when TextInputMenuAgent proxies a submenu. Accept both so
      // language switching is not dependent on one private serialization path.
      if let selectedItem, handleCandidateTranslationMenuTag(selectedItem.tag) {
        return
      }
      if let aSelector, handleCandidateTranslationSelector(aSelector) {
        return
      }
    }

    super.doCommand(by: aSelector, command: infoDictionary)
  }

  @objc func deploy() {
    NSApp.squirrelAppDelegate.deploy()
  }

  @objc func syncUserData() {
    NSApp.squirrelAppDelegate.syncUserData()
  }

  @objc func openLogFolder() {
    NSApp.squirrelAppDelegate.openLogFolder()
  }

  @objc func openRimeFolder() {
    NSApp.squirrelAppDelegate.openRimeFolder()
  }

  @objc func showLingoSphereSettings(_ sender: Any?) {
    NSApp.squirrelAppDelegate.showLingoSphereSettings()
  }

  @objc func openWiki() {
    NSApp.squirrelAppDelegate.openWiki()
  }

  @available(macOS 15.0, *)
  private func candidateTranslationMenuAction(for language: CandidateTranslationLanguage) -> Selector {
    switch language {
    case .english: #selector(selectEnglishCandidateTranslation(_:))
    case .japanese: #selector(selectJapaneseCandidateTranslation(_:))
    case .korean: #selector(selectKoreanCandidateTranslation(_:))
    case .german: #selector(selectGermanCandidateTranslation(_:))
    case .french: #selector(selectFrenchCandidateTranslation(_:))
    case .spanish: #selector(selectSpanishCandidateTranslation(_:))
    case .portuguese: #selector(selectPortugueseCandidateTranslation(_:))
    }
  }

  @available(macOS 15.0, *)
  private func candidateTranslationMenuTag(for language: CandidateTranslationLanguage) -> Int {
    switch language {
    case .english: CandidateTranslationMenuTag.english
    case .japanese: CandidateTranslationMenuTag.japanese
    case .korean: CandidateTranslationMenuTag.korean
    case .german: CandidateTranslationMenuTag.german
    case .french: CandidateTranslationMenuTag.french
    case .spanish: CandidateTranslationMenuTag.spanish
    case .portuguese: CandidateTranslationMenuTag.portuguese
    }
  }

  @available(macOS 15.0, *)
  private func handleCandidateTranslationMenuTag(_ tag: Int) -> Bool {
    let language: CandidateTranslationLanguage?
    switch tag {
    case CandidateTranslationMenuTag.english: language = .english
    case CandidateTranslationMenuTag.japanese: language = .japanese
    case CandidateTranslationMenuTag.korean: language = .korean
    case CandidateTranslationMenuTag.german: language = .german
    case CandidateTranslationMenuTag.french: language = .french
    case CandidateTranslationMenuTag.spanish: language = .spanish
    case CandidateTranslationMenuTag.portuguese: language = .portuguese
    case CandidateTranslationMenuTag.commitTranslation:
      toggleTranslationCommit(nil)
      return true
    case CandidateTranslationMenuTag.disable:
      disableCandidateTranslation(nil)
      return true
    case CandidateTranslationMenuTag.manage:
      manageCandidateTranslation(nil)
      return true
    default:
      return false
    }

    guard let language else { return false }
    selectCandidateTranslation(language)
    return true
  }

  @available(macOS 15.0, *)
  private func handleCandidateTranslationSelector(_ selector: Selector) -> Bool {
    switch selector {
    case #selector(selectEnglishCandidateTranslation(_:)):
      selectCandidateTranslation(.english)
    case #selector(selectJapaneseCandidateTranslation(_:)):
      selectCandidateTranslation(.japanese)
    case #selector(selectKoreanCandidateTranslation(_:)):
      selectCandidateTranslation(.korean)
    case #selector(selectGermanCandidateTranslation(_:)):
      selectCandidateTranslation(.german)
    case #selector(selectFrenchCandidateTranslation(_:)):
      selectCandidateTranslation(.french)
    case #selector(selectSpanishCandidateTranslation(_:)):
      selectCandidateTranslation(.spanish)
    case #selector(selectPortugueseCandidateTranslation(_:)):
      selectCandidateTranslation(.portuguese)
    case #selector(toggleTranslationCommit(_:)):
      toggleTranslationCommit(nil)
    case #selector(disableCandidateTranslation(_:)):
      disableCandidateTranslation(nil)
    case #selector(manageCandidateTranslation(_:)):
      manageCandidateTranslation(nil)
    default:
      return false
    }
    return true
  }

  @objc func selectEnglishCandidateTranslation(_ sender: Any?) {
    selectCandidateTranslation(.english)
  }

  @objc func selectJapaneseCandidateTranslation(_ sender: Any?) {
    selectCandidateTranslation(.japanese)
  }

  @objc func selectKoreanCandidateTranslation(_ sender: Any?) {
    selectCandidateTranslation(.korean)
  }

  @objc func selectGermanCandidateTranslation(_ sender: Any?) {
    selectCandidateTranslation(.german)
  }

  @objc func selectFrenchCandidateTranslation(_ sender: Any?) {
    selectCandidateTranslation(.french)
  }

  @objc func selectSpanishCandidateTranslation(_ sender: Any?) {
    selectCandidateTranslation(.spanish)
  }

  @objc func selectPortugueseCandidateTranslation(_ sender: Any?) {
    selectCandidateTranslation(.portuguese)
  }

  private func selectCandidateTranslation(_ language: CandidateTranslationLanguage) {
    guard #available(macOS 15.0, *) else { return }
    performCandidateTranslationAction { translator in
      print("Switching candidate translation from input menu to: \(language.rawValue)")
      translator.selectLanguage(language, prepare: true)
    }
  }

  @objc func disableCandidateTranslation(_ sender: Any?) {
    guard #available(macOS 15.0, *) else { return }
    performCandidateTranslationAction { translator in
      translator.setEnabled(false)
    }
  }

  @objc func toggleTranslationCommit(_ sender: Any?) {
    guard #available(macOS 15.0, *) else { return }
    performCandidateTranslationAction { translator in
      translator.setCommitsTranslation(!translator.commitsTranslation)
    }
  }

  @objc func manageCandidateTranslation(_ sender: Any?) {
    guard #available(macOS 15.0, *) else { return }
    performCandidateTranslationAction { translator in
      translator.showLanguageSettings()
    }
  }

  @available(macOS 15.0, *)
  private func performCandidateTranslationAction(
    _ action: @escaping @MainActor (AppleCandidateTranslator) -> Void
  ) {
    if Thread.isMainThread {
      MainActor.assumeIsolated {
        guard let translator = NSApp.squirrelAppDelegate.appleCandidateTranslator else { return }
        action(translator)
      }
      return
    }

    // TextInputMenuAgent may deliver an InputMethodKit command on its
    // connection thread. Run it synchronously on AppKit's main queue: an async
    // hop can remain pending after the remote menu closes and the background
    // input-method process is suspended.
    DispatchQueue.main.sync {
      MainActor.assumeIsolated {
        guard let translator = NSApp.squirrelAppDelegate.appleCandidateTranslator else { return }
        action(translator)
      }
    }
  }

  private(set) var specialCommentIndices: [ReservedPropertyKey: Set<Int>] = [:]

  func handleReservedProperty(key rawKey: String, value rawValue: String, for sessionId: RimeSessionId) throws(ReservedPropertyError) {
    guard session == sessionId, session != 0, rimeAPI.find_session(session) else { return }
    guard let key = ReservedPropertyKey(rawValue: rawKey) else { throw .unknownInput(rawKey) }
    let parsed = try ReservedPropertyValue.parse(rawValue)
    switch key {
    case .commentHighlight:
      specialCommentIndices[.commentHighlight] = try parsed.indices()
    case .commentWarning:
      specialCommentIndices[.commentWarning] = try parsed.indices()
    case .refreshUI:
      rimeUpdate(clearReservedComments: false)
    }
  }

  deinit {
    destroySession()
  }
}

private extension SquirrelInputController {

  func onChordTimer(_: Timer) {
    var processedKeys = false
    if chordKeyCount > 0 && session != 0 {
      // Chord typing releases are synthesized after the configured timeout.
      for i in 0..<chordKeyCount {
        let handled = rimeAPI.process_key(session, Int32(chordKeyCodes[i]), Int32(chordModifiers[i] | kReleaseMask.rawValue))
        if handled {
          processedKeys = true
        }
      }
    }
    clearChord()
    if processedKeys {
      rimeUpdate()
    }
  }

  func updateChord(keycode: UInt32, modifiers: UInt32) {
    for i in 0..<chordKeyCount where chordKeyCodes[i] == keycode {
      return
    }
    if chordKeyCount >= Self.keyRollOver {
      return
    }
    chordKeyCodes[chordKeyCount] = keycode
    chordModifiers[chordKeyCount] = modifiers
    chordKeyCount += 1
    if let timer = chordTimer, timer.isValid {
      timer.invalidate()
    }
    chordDuration = 0.1
    if let duration = NSApp.squirrelAppDelegate.config?.getDouble("chord_duration"), duration > 0 {
      chordDuration = duration
    }
    chordTimer = Timer.scheduledTimer(withTimeInterval: chordDuration, repeats: false, block: onChordTimer)
  }

  func clearChord() {
    chordKeyCount = 0
    if let timer = chordTimer {
      if timer.isValid {
        timer.invalidate()
      }
      chordTimer = nil
    }
  }

  func createSession() {
    let app = client?.bundleIdentifier() ?? {
      SquirrelInputController.unknownAppCnt &+= 1
      return "UnknownApp\(SquirrelInputController.unknownAppCnt)"
    }()
    print("createSession: \(app)")
    currentApp = app
    session = rimeAPI.create_session()
    schemaId = ""

    if session != 0 {
      updateAppOptions()
    }
  }

  func updateAppOptions() {
    if currentApp == "" {
      return
    }
    if let appOptions = NSApp.squirrelAppDelegate.config?.getAppOptions(currentApp) {
      for (key, value) in appOptions {
        print("set app option: \(key) = \(value)")
        rimeAPI.set_option(session, key, value)
      }
    }
    if let reportBundleID = NSApp.squirrelAppDelegate.config?.getBool("unsafe/report_bundleid"), reportBundleID {
      currentApp.withCString { name in
        rimeAPI.set_property(session, "client_app", name)
      }
    }
  }

  func destroySession() {
    if session != 0 {
      _ = rimeAPI.destroy_session(session)
      session = 0
    }
    clearChord()
  }

  func processKey(_ rimeKeycode: UInt32, modifiers rimeModifiers: UInt32) -> Bool {
    if let panel = NSApp.squirrelAppDelegate.panel {
      if panel.linear != rimeAPI.get_option(session, "_linear") {
        rimeAPI.set_option(session, "_linear", panel.linear)
      }
      if panel.vertical != rimeAPI.get_option(session, "_vertical") {
        rimeAPI.set_option(session, "_vertical", panel.vertical)
      }
    }

    let handled = rimeAPI.process_key(session, Int32(rimeKeycode), Int32(rimeModifiers))

    if !handled {
      let isVimBackInCommandMode = rimeKeycode == XK_Escape || ((rimeModifiers & kControlMask.rawValue != 0) && (rimeKeycode == XK_c || rimeKeycode == XK_C || rimeKeycode == XK_bracketleft))
      if isVimBackInCommandMode && rimeAPI.get_option(session, "vim_mode") &&
          !rimeAPI.get_option(session, "ascii_mode") {
        rimeAPI.set_option(session, "ascii_mode", true)
      }
    } else {
      let isChordingKey = switch Int32(rimeKeycode) {
      case XK_space...XK_asciitilde, XK_Control_L, XK_Control_R, XK_Alt_L, XK_Alt_R, XK_Shift_L, XK_Shift_R:
        true
      default:
        false
      }
      if isChordingKey && rimeAPI.get_option(session, "_chord_typing") {
        updateChord(keycode: rimeKeycode, modifiers: rimeModifiers)
      } else if (rimeModifiers & kReleaseMask.rawValue) == 0 {
        clearChord()
      }
    }

    return handled
  }

  /// Which candidate a key press selects, and whether its translation rather
  /// than the candidate itself should be inserted. Nil for every key that is
  /// not a plain or Option-modified selection key while candidates are shown.
  func translationSelection(
    for event: NSEvent,
    modifiers: NSEvent.ModifierFlags
  ) -> (index: Int, wantsTranslation: Bool)? {
    guard #available(macOS 15.0, *),
          let translator = NSApp.squirrelAppDelegate.appleCandidateTranslator else { return nil }
    let state = MainActor.assumeIsolated {
      (enabled: translator.isEnabled, swapped: translator.commitsTranslation)
    }
    let optionDown = modifiers.contains(.option)
    guard state.enabled, optionDown || state.swapped,
          modifiers.intersection([.control, .command, .shift]).isEmpty,
          let char = event.charactersIgnoringModifiers?.first else { return nil }

    var ctx = RimeContext_stdbool.rimeStructInit()
    guard rimeAPI.get_context(session, &ctx) else { return nil }
    defer { _ = rimeAPI.free_context(&ctx) }
    let count = Int(ctx.menu.num_candidates)
    guard count > 0 else { return nil }

    let index: Int?
    if char == " " {
      index = Int(ctx.menu.highlighted_candidate_index)
    } else if let selectKeys = ctx.menu.select_keys {
      let keys = Array(String(cString: selectKeys))
      index = keys.firstIndex(of: char)
    } else if let digit = char.wholeNumberValue, char.isASCII {
      index = digit == 0 ? 9 : digit - 1
    } else {
      index = nil
    }
    guard let index, index >= 0, index < count else { return nil }
    return (index, optionDown != state.swapped)
  }

  /// Selects the candidate in Rime and arranges for its translation to be
  /// inserted in its place. Returns false, changing nothing, when the
  /// candidate has no translation yet.
  func commitTranslation(ofCandidateAt index: Int) -> Bool {
    guard #available(macOS 15.0, *),
          let translator = NSApp.squirrelAppDelegate.appleCandidateTranslator else { return false }
    var ctx = RimeContext_stdbool.rimeStructInit()
    guard rimeAPI.get_context(session, &ctx) else { return false }
    var candidateText: String?
    if index >= 0, index < Int(ctx.menu.num_candidates) {
      candidateText = ctx.menu.candidates[index].text.map { String(cString: $0) }
    }
    _ = rimeAPI.free_context(&ctx)

    guard let candidateText else { return false }
    let senses = MainActor.assumeIsolated {
      translator.committableTranslations(for: candidateText)
    }
    guard !senses.isEmpty else { return false }

    sensePicker = (candidateIndex: index, source: candidateText, senses: senses, highlighted: 0)
    if senses.count == 1 {
      commitSense(at: 0)
    } else {
      showSensePicker()
    }
    return true
  }

  func showSensePicker() {
    guard let picker = sensePicker else { return }
    let header = "\(picker.source) →"
    showPanel(preedit: header, selRange: NSRange(location: 0, length: 0), caretPos: header.utf16.count,
              candidates: picker.senses, comments: picker.senses.map { _ in "" },
              labels: picker.senses.indices.map { String(($0 + 1) % 10) },
              highlighted: picker.highlighted, page: 0, lastPage: true)
  }

  /// Inserts the chosen translation in place of the candidate the picker was
  /// opened for.
  func commitSense(at senseIndex: Int) {
    guard let picker = sensePicker else { return }
    sensePicker = nil
    guard picker.senses.indices.contains(senseIndex) else {
      rimeUpdate()
      return
    }
    pendingTranslationSubstitutions.append((source: picker.source, translation: picker.senses[senseIndex]))
    if !rimeAPI.select_candidate_on_current_page(session, picker.candidateIndex) {
      pendingTranslationSubstitutions.removeLast()
    }
    rimeUpdate()
  }

  /// Returns true when the key was used by the translation list. Returns
  /// false after closing the list so the key is processed normally.
  func handleSensePickerKey(_ event: NSEvent) -> Bool {
    guard var picker = sensePicker else { return false }
    guard !event.modifierFlags.contains(.command) else {
      sensePicker = nil
      rimeUpdate()
      return false
    }
    switch event.keyCode {
    case 53, 51:  // escape, delete: back to the candidate list
      sensePicker = nil
      rimeUpdate()
      return true
    case 49, 36, 76:  // space, return, keypad enter
      commitSense(at: picker.highlighted)
      return true
    case 125, 124:  // down, right
      picker.highlighted = min(picker.senses.count - 1, picker.highlighted + 1)
      sensePicker = picker
      showSensePicker()
      return true
    case 126, 123:  // up, left
      picker.highlighted = max(0, picker.highlighted - 1)
      sensePicker = picker
      showSensePicker()
      return true
    default:
      break
    }
    if let char = event.charactersIgnoringModifiers?.first, char.isASCII,
       let digit = char.wholeNumberValue, digit >= 1, digit <= picker.senses.count {
      commitSense(at: digit - 1)
      return true
    }
    sensePicker = nil
    return false
  }

  func applyPendingTranslations(to committed: String) -> String {
    let substitutions = pendingTranslationSubstitutions
    pendingTranslationSubstitutions.removeAll()
    guard !substitutions.isEmpty else {
      lastCommitEndedWithTranslatedWord = false
      return committed
    }

    var result = ""
    var rest = Substring(committed)
    var endsWithTranslation = false
    // Words written with spaces (English, Korean, …) need one between two
    // consecutive translations, including one from the previous commit.
    var previousWasTranslatedWord = lastCommitEndedWithTranslatedWord
    for (source, translation) in substitutions {
      guard let range = rest.range(of: source) else { continue }
      if range.lowerBound != rest.startIndex {
        result += rest[..<range.lowerBound]
        previousWasTranslatedWord = false
      }
      if previousWasTranslatedWord,
         let first = translation.first, Self.usesWordSpacing(first) {
        result += " "
      }
      result += translation
      rest = rest[range.upperBound...]
      previousWasTranslatedWord = translation.last.map(Self.usesWordSpacing) ?? false
      endsWithTranslation = true
    }
    if !rest.isEmpty {
      result += rest
      endsWithTranslation = false
    }
    lastCommitEndedWithTranslatedWord = endsWithTranslation && previousWasTranslatedWord
    return result
  }

  static func usesWordSpacing(_ character: Character) -> Bool {
    guard character.isLetter || character.isNumber,
          let scalar = character.unicodeScalars.first else { return false }
    switch scalar.value {
    // CJK ideographs, kana and full-width forms are written without spaces.
    case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x323AF:
      return false
    default:
      return true
    }
  }

  func rimeConsumeCommittedText() {
    var commitText = RimeCommit.rimeStructInit()
    if rimeAPI.get_commit(session, &commitText) {
      if let text = commitText.text {
        commit(string: applyPendingTranslations(to: String(cString: text)))
      }
      _ = rimeAPI.free_commit(&commitText)
    }
  }

  // Preserve reserved comment marks when librime requests a UI-only refresh.
  func rimeUpdate(clearReservedComments: Bool = true) {
    if clearReservedComments {
      specialCommentIndices = [:]
    }
    rimeConsumeCommittedText()

    var status = RimeStatus_stdbool.rimeStructInit()
    if rimeAPI.get_status(session, &status) {
      // swiftlint:disable:next identifier_name
      if let schema_id = status.schema_id, schemaId == "" || schemaId != String(cString: schema_id) {
        schemaId = String(cString: schema_id)
        NSApp.squirrelAppDelegate.loadSettings(for: schemaId)
        if let panel = NSApp.squirrelAppDelegate.panel {
          inlinePreedit = (panel.inlinePreedit && !rimeAPI.get_option(session, "no_inline")) || rimeAPI.get_option(session, "inline")
          inlineCandidate = panel.inlineCandidate && !rimeAPI.get_option(session, "no_inline")
          rimeAPI.set_option(session, "soft_cursor", !inlinePreedit)
        }
      }
      _ = rimeAPI.free_status(&status)
    }

    var ctx = RimeContext_stdbool.rimeStructInit()
    if rimeAPI.get_context(session, &ctx) {
      let preedit = ctx.composition.preedit.map({ String(cString: $0) }) ?? ""

      let start = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_start)), within: preedit) ?? preedit.startIndex
      let end = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.sel_end)), within: preedit) ?? preedit.startIndex
      let caretPos = String.Index(preedit.utf8.index(preedit.utf8.startIndex, offsetBy: Int(ctx.composition.cursor_pos)), within: preedit) ?? preedit.startIndex

      if inlineCandidate {
        var candidatePreview = ctx.commit_text_preview.map { String(cString: $0) } ?? ""
        let endOfCandidatePreview = candidatePreview.endIndex
        if inlinePreedit {
          // 左移光標後的情形：
          // preedit:             ^已選某些字[xiang zuo yi dong]|guangbiao$
          // commit_text_preview: ^已選某些字向左移動$
          // candidate_preview:   ^已選某些字[向左移動]|guangbiao$
          // 繼續翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
          // commit_text_preview: ^已選某些字向左yidong$
          // candidate_preview:   ^已選某些字[向左]yidong|guangbiao$
          // 光標移至當前段落最左端的情形：
          // preedit:             ^已選某些字|[xiang zuo yi dong guang biao]$
          // commit_text_preview: ^已選某些字向左移動光標$
          // candidate_preview:   ^已選某些字|[向左移動光標]$
          // 討論：
          // preedit 與 commit_text_preview 中“已選某些字”部分一致
          // 因此，選中範圍即正在翻譯的碼段“向左移動”中，兩者的 start 值一致
          // 光標位置的範圍是 start ..= endOfCandidatePreview
          if caretPos >= end && caretPos < preedit.endIndex {
            // 從 preedit 截取光標後未翻譯的編碼“guangbiao”
            candidatePreview += preedit[caretPos...]
          }
        } else {
          // 翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字[xiang zuo]yidong|guangbiao$
          // commit_text_preview: ^已選某些字向左yidongguangbiao$
          // candidate_preview:   ^已選某些字[向左???]|$
          // 光標移至當前段落最左端，繼續翻頁至指定更短字詞的情形：
          // preedit:             ^已選某些字|[xiang zuo]yidongguangbiao$
          // commit_text_preview: ^已選某些字向左yidongguangbiao$
          // candidate_preview:   ^已選某些字|[向左]???$
          // FIXME: add librime APIs to support preview candidate without remaining code.
        }
        // preedit can contain additional prompt text before start:
        // ^(prompt)[selection]$
        let start = min(start, candidatePreview.endIndex)
        let caretPos = caretPos <= start ? caretPos : endOfCandidatePreview
        show(preedit: candidatePreview,
             selRange: NSRange(location: start.utf16Offset(in: candidatePreview),
                               length: candidatePreview.utf16.distance(from: start, to: candidatePreview.endIndex)),
             caretPos: caretPos.utf16Offset(in: candidatePreview))
      } else {
        if inlinePreedit {
          show(preedit: preedit, selRange: NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end)), caretPos: caretPos.utf16Offset(in: preedit))
        } else {
          // Use a full-width space placeholder to prevent iTerm2 from echoing raw preedit;
          // half-width placeholders make the Chinese composition baseline unstable.
          show(preedit: preedit.isEmpty ? "" : "　", selRange: NSRange(location: 0, length: 0), caretPos: 0)
        }
      }

      let numCandidates = Int(ctx.menu.num_candidates)
      var candidates = [String]()
      var comments = [String]()
      for i in 0..<numCandidates {
        let candidate = ctx.menu.candidates[i]
        candidates.append(candidate.text.map { String(cString: $0) } ?? "")
        comments.append(candidate.comment.map { String(cString: $0) } ?? "")
      }
      var labels = [String]()
      // swiftlint:disable identifier_name
      if let select_keys = ctx.menu.select_keys {
        labels = String(cString: select_keys).map { String($0) }
      } else if let select_labels = ctx.select_labels {
        let pageSize = Int(ctx.menu.page_size)
        for i in 0..<pageSize {
          labels.append(select_labels[i].map { String(cString: $0) } ?? "")
        }
      }
      // swiftlint:enable identifier_name
      let page = Int(ctx.menu.page_no)
      let lastPage = ctx.menu.is_last_page

      if #available(macOS 15.0, *), let translator = NSApp.squirrelAppDelegate.appleCandidateTranslator {
        let translatedComments = MainActor.assumeIsolated { () -> [String]? in
          guard translator.isEnabled else { return nil }
          if translator.requiresOption && !rimeAPI.get_option(session, translator.optionName) {
            return nil
          }
          return translator.translatedComments(candidates: candidates, comments: comments) { [weak self] in
            guard let self = self, self.session != 0, self.rimeAPI.find_session(self.session) else { return }
            self.rimeUpdate(clearReservedComments: false)
          }
        }
        if let translatedComments = translatedComments {
          comments = translatedComments
        }
      }

      let selRange = NSRange(location: start.utf16Offset(in: preedit), length: preedit.utf16.distance(from: start, to: end))
      if sensePicker != nil && numCandidates > 0 {
        // A modifier release or a late translation refresh must not replace
        // the translation list the user is choosing from.
        showSensePicker()
      } else {
        sensePicker = nil
        showPanel(preedit: inlinePreedit ? "" : preedit, selRange: selRange, caretPos: caretPos.utf16Offset(in: preedit),
                  candidates: candidates, comments: comments, labels: labels, highlighted: Int(ctx.menu.highlighted_candidate_index),
                  page: page, lastPage: lastPage)
      }
      _ = rimeAPI.free_context(&ctx)
    } else {
      sensePicker = nil
      pendingTranslationSubstitutions.removeAll()
      hidePalettes()
    }
  }

  func commit(string: String) {
    guard let client = client else { return }

    let forceMarkedText =
      session != 0 &&
      rimeAPI.get_option(session, "force_marked_text_for_direct_commit")

    // Direct commits such as full-width punctuation do not necessarily have an
    // active marked-text phase. Some NSTextInputClient implementations require
    // one before accepting insertText.
    if forceMarkedText && preedit.isEmpty && !string.isEmpty {
      let markedText = NSMutableAttributedString(string: string)
      client.setMarkedText(
        markedText,
        selectionRange: NSRange(location: markedText.length, length: 0),
        replacementRange: .empty
      )
    }

    client.insertText(string, replacementRange: .empty)
    preedit = ""
    hidePalettes()
  }

  func show(preedit: String, selRange: NSRange, caretPos: Int) {
    guard let client = client else { return }
    if self.preedit == preedit && self.caretPos == caretPos && self.selRange == selRange {
      return
    }

    self.preedit = preedit
    self.caretPos = caretPos
    self.selRange = selRange

    let start = selRange.location
    let attrString = NSMutableAttributedString(string: preedit)
    if start > 0 {
      let attrs = mark(forStyle: kTSMHiliteConvertedText, at: NSRange(location: 0, length: start))! as! [NSAttributedString.Key: Any]
      attrString.setAttributes(attrs, range: NSRange(location: 0, length: start))
    }
    let remainingRange = NSRange(location: start, length: preedit.utf16.count - start)
    let attrs = mark(forStyle: kTSMHiliteSelectedRawText, at: remainingRange)! as! [NSAttributedString.Key: Any]
    attrString.setAttributes(attrs, range: remainingRange)
    client.setMarkedText(attrString, selectionRange: NSRange(location: caretPos, length: 0), replacementRange: .empty)
  }

  // swiftlint:disable:next function_parameter_count
  func showPanel(preedit: String, selRange: NSRange, caretPos: Int, candidates: [String], comments: [String], labels: [String], highlighted: Int, page: Int, lastPage: Bool) {
    guard let client = client else { return }
    var inputPos = NSRect()
    client.attributes(forCharacterIndex: 0, lineHeightRectangle: &inputPos)
    if let panel = NSApp.squirrelAppDelegate.panel {
      panel.position = inputPos
      panel.inputController = self
      panel.update(preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates, comments: comments, labels: labels,
                   highlighted: highlighted, page: page, lastPage: lastPage, update: true)
    }
  }

  private func handleASCIIModeToggle(_ notification: Notification) {
    guard let enableASCII = notification.object as? Bool else { return }
    guard session != 0 && rimeAPI.find_session(session) else { return }

    rimeAPI.set_option(session, "ascii_mode", enableASCII)
    rimeUpdate()
  }

  private func reportASCIIMode(_: Notification) {
    guard client != nil else { return }
    guard session != 0 && rimeAPI.find_session(session) else { return }

    let isASCIIMode = rimeAPI.get_option(session, "ascii_mode")
    let status = isASCIIMode ? "ascii" : "nascii"

    DistributedNotificationCenter.default().postNotificationName(
      LingoSphereIdentity.asciiModeResponseNotification,
      object: status
    )
  }

}
