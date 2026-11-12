//
//  AppleCandidateTranslator.swift
//  Squirrel
//

import AppKit
import SwiftUI
import Translation

@available(macOS 15.0, *)
enum CandidateTranslationLanguage: String, CaseIterable, Identifiable, Sendable {
  case english = "en"
  case japanese = "ja"
  case korean = "ko"
  case german = "de"
  case french = "fr"
  case spanish = "es-ES"
  case portuguese = "pt-BR"

  var id: String { rawValue }

  var chineseName: String {
    switch self {
    case .english: "英语"
    case .japanese: "日语"
    case .korean: "韩语"
    case .german: "德语"
    case .french: "法语"
    case .spanish: "西班牙语"
    case .portuguese: "葡萄牙语（巴西）"
    }
  }

  var nativeName: String {
    switch self {
    case .english: "English"
    case .japanese: "日本語"
    case .korean: "한국어"
    case .german: "Deutsch"
    case .french: "Français"
    case .spanish: "Español"
    case .portuguese: "Português"
    }
  }

  var shortCode: String {
    switch self {
    case .english: "EN"
    case .japanese: "日"
    case .korean: "한"
    case .german: "DE"
    case .french: "FR"
    case .spanish: "ES"
    case .portuguese: "PT"
    }
  }

  var menuTitle: String {
    "\(chineseName) · \(nativeName)"
  }

  var localeLanguage: Locale.Language {
    Locale.Language(identifier: rawValue)
  }

  static func resolve(identifier: String) -> CandidateTranslationLanguage? {
    if let exact = Self(rawValue: identifier) {
      return exact
    }
    let normalized = identifier.lowercased()
    return allCases.first { language in
      normalized == language.rawValue.lowercased()
        || normalized.hasPrefix(language.rawValue.lowercased() + "-")
        || language.rawValue.lowercased().hasPrefix(normalized + "-")
    }
  }
}

@available(macOS 15.0, *)
@MainActor
final class AppleCandidateTranslator: NSObject, NSWindowDelegate {
  private static let defaultSourceLanguage = "zh-Hans"
  private static let defaultTargetLanguage = "en"
  private static let defaultOptionName = "candidate_translation"
  private static let defaultRequiresOption = false
  private static let defaultDebounceMilliseconds = 220
  private static let defaultMaxCommentCharacters = 38
  private static let retryDelay: TimeInterval = 60
  // Words the engine could not translate are not asked again for this long.
  private static let untranslatableRetryDelay: TimeInterval = 600
  private static let retryTableLimit = 5_000
  private static let noticeDuration: Duration = .seconds(4)
  private static let preparationSample = "你好"
  private static let selectedLanguageDefaultsKey = "AppleCandidateTranslation.selectedLanguage"
  private static let enabledDefaultsKey = "AppleCandidateTranslation.enabled"
  private static let onboardingDefaultsKey = "AppleCandidateTranslation.didCompleteLanguageSetup"
  private static let commitsTranslationDefaultsKey = "AppleCandidateTranslation.commitsTranslation"

  private let hostState = AppleTranslationHostState()
  private var requestContinuation: AsyncStream<[String]>.Continuation?
  private var cache = [String: String]()
  private var localDictionaryBuckets: [Int: [String: String]] = [:]
  private var missingDictionaryBuckets = Set<Int>()
  private var hostWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var settingsWindowIsOnboarding = false
  private var settingsModel: TranslationLanguageSettingsModel?
  private var debounceTask: Task<Void, Never>?
  private var persistTask: Task<Void, Never>?
  private var onboardingTask: Task<Void, Never>?
  private var noticeHideTask: Task<Void, Never>?
  private var desiredWords = Set<String>()
  private var queuedWords = Set<String>()
  private var inFlightWords = Set<String>()
  private var retryAfter: [String: Date] = [:]
  private var refreshAction: (() -> Void)?
  private var hasStarted = false
  private var hasScheduledOnboarding = false
  private var isPrepared = false
  // Set when the language model could not be prepared (for example the user
  // declined the download). No further requests are sent until the user picks
  // a language again, so macOS does not re-prompt while they keep typing.
  private var preparationSuspended = false
  private var activeHostGeneration = UUID()

  private(set) var isEnabled = true
  /// When true, choosing a candidate inserts its translation and holding
  /// Option inserts the Chinese text; when false it is the other way round.
  private(set) var commitsTranslation = UserDefaults.standard.bool(
    forKey: AppleCandidateTranslator.commitsTranslationDefaultsKey
  )
  private(set) var optionName = AppleCandidateTranslator.defaultOptionName
  private(set) var requiresOption = AppleCandidateTranslator.defaultRequiresOption
  private(set) var activeLanguage = CandidateTranslationLanguage.english
  private var sourceLanguageIdentifier = AppleCandidateTranslator.defaultSourceLanguage
  private var debounceMilliseconds = AppleCandidateTranslator.defaultDebounceMilliseconds
  private var maxCommentCharacters = AppleCandidateTranslator.defaultMaxCommentCharacters

  func configure(config: SquirrelConfig) {
    let previousSourceLanguageIdentifier = sourceLanguageIdentifier
    let previousLanguage = activeLanguage
    let previousEnabled = isEnabled

    let configuredEnabled = config.getBool("apple_translation/enabled") ?? true
    if let storedEnabled = UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool {
      isEnabled = storedEnabled
    } else {
      isEnabled = configuredEnabled
    }
    optionName = config.getString("apple_translation/option_name") ?? Self.defaultOptionName
    requiresOption = config.getBool("apple_translation/require_option") ?? Self.defaultRequiresOption
    sourceLanguageIdentifier = config.getString("apple_translation/source_language") ?? Self.defaultSourceLanguage
    let configuredTarget = config.getString("apple_translation/target_language") ?? Self.defaultTargetLanguage
    let selectedTarget = UserDefaults.standard.string(forKey: Self.selectedLanguageDefaultsKey) ?? configuredTarget
    let resolvedLanguage = CandidateTranslationLanguage.resolve(identifier: selectedTarget) ?? .english
    if previousLanguage != resolvedLanguage, !cache.isEmpty {
      persistActiveCacheImmediately()
      persistTask?.cancel()
    }
    activeLanguage = resolvedLanguage
    if let value = config.getDouble("apple_translation/debounce_ms") {
      debounceMilliseconds = max(80, min(1_000, Int(value)))
    }
    if let value = config.getDouble("apple_translation/max_comment_chars") {
      maxCommentCharacters = max(12, min(120, Int(value)))
    }

    if cache.isEmpty || previousLanguage != activeLanguage {
      loadActiveLanguageCache()
    }
    if hasStarted && (previousSourceLanguageIdentifier != sourceLanguageIdentifier
      || previousLanguage != activeLanguage || previousEnabled != isEnabled) {
      restartHost()
    }
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    if isEnabled && UserDefaults.standard.bool(forKey: Self.onboardingDefaultsKey) {
      startHost()
    }
    scheduleOnboardingIfNeeded()
  }

  func stop() {
    persistActiveCacheImmediately()
    debounceTask?.cancel()
    persistTask?.cancel()
    onboardingTask?.cancel()
    noticeHideTask?.cancel()
    requestContinuation?.finish()
    requestContinuation = nil
    hostWindow?.close()
    hostWindow = nil
    settingsWindowIsOnboarding = false
    settingsWindow?.delegate = nil
    settingsWindow?.close()
    settingsWindow = nil
    settingsModel = nil
    refreshAction = nil
    hasStarted = false
  }

  func selectLanguage(_ language: CandidateTranslationLanguage, prepare: Bool = true) {
    let languageChanged = activeLanguage != language
    let wasEnabled = isEnabled
    if languageChanged {
      persistActiveCacheImmediately()
      persistTask?.cancel()
    }
    activeLanguage = language
    isEnabled = true
    UserDefaults.standard.set(language.rawValue, forKey: Self.selectedLanguageDefaultsKey)
    UserDefaults.standard.set(true, forKey: Self.enabledDefaultsKey)
    UserDefaults.standard.set(true, forKey: Self.onboardingDefaultsKey)

    if languageChanged {
      loadActiveLanguageCache()
    }
    if languageChanged || !wasEnabled || hostWindow == nil || preparationSuspended {
      restartHost()
    }
    refreshAction?()
    if prepare {
      requestLanguagePreparation()
    }
  }

  func setEnabled(_ enabled: Bool) {
    guard isEnabled != enabled else { return }
    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
    UserDefaults.standard.set(true, forKey: Self.onboardingDefaultsKey)
    if enabled {
      restartHost()
    } else {
      tearDownHost()
    }
    refreshAction?()
  }

  func setCommitsTranslation(_ value: Bool) {
    commitsTranslation = value
    UserDefaults.standard.set(value, forKey: Self.commitsTranslationDefaultsKey)
  }

  /// The texts the user can insert in place of `candidate`, best first. Empty
  /// when no translation is known yet. English dictionary entries list
  /// several senses ("small; tiny; few"); each usable one is offered.
  func committableTranslations(for candidate: String) -> [String] {
    guard isEnabled,
          UserDefaults.standard.bool(forKey: Self.onboardingDefaultsKey),
          Self.containsHan(candidate) else { return [] }

    var senses = [String]()
    if activeLanguage == .english, let gloss = rawLocalTranslation(for: candidate) {
      for part in gloss.split(separator: ";") {
        guard let sense = Self.insertableSense(String(part)), !senses.contains(sense) else { continue }
        senses.append(sense)
      }
    }
    if senses.isEmpty, let cached = cache[candidate], let sense = Self.insertableSense(cached) {
      senses.append(sense)
    }
    return senses
  }

  /// Dictionary notes that describe the character rather than translate it.
  private static let nonInsertablePrefixes = [
    "variant of", "old variant of", "archaic variant of", "erhua variant of", "erhua form of",
    "see ", "see also ", "same as ", "surname ", "used in ", "abbr. for ", "taiwan pr.",
    "also pr.", "also written", "cl:", "classifier for ", "question particle", "particle "
  ]

  private static func insertableSense(_ raw: String) -> String? {
    var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // A sense cut off for display is incomplete and must not be inserted.
    guard !result.hasSuffix("…") else { return nil }
    // Drop usage notes such as "(bound form) row" that are not part of the word.
    while result.hasPrefix("("), let close = result.firstIndex(of: ")") {
      result = String(result[result.index(after: close)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let lowered = result.lowercased()
    guard !result.isEmpty,
          !result.contains("["),
          !nonInsertablePrefixes.contains(where: { lowered.hasPrefix($0) }) else { return nil }
    return result
  }

  func showLanguageSettings(isOnboarding: Bool = false) {
    if let window = settingsWindow {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let model = TranslationLanguageSettingsModel(
      sourceLanguage: sourceLanguage,
      selectedLanguage: activeLanguage,
      isEnabled: isEnabled
    )
    let view = TranslationLanguageSettingsView(
      model: model,
      isOnboarding: isOnboarding,
      onCancel: { [weak self] in
        guard let self else { return }
        if isOnboarding {
          UserDefaults.standard.set(true, forKey: Self.onboardingDefaultsKey)
          self.setEnabled(false)
        }
        self.closeLanguageSettings()
      },
      onSave: { [weak self] language, enabled in
        guard let self else { return }
        UserDefaults.standard.set(true, forKey: Self.onboardingDefaultsKey)
        self.closeLanguageSettings()
        if enabled {
          self.selectLanguage(language, prepare: true)
        } else {
          self.setEnabled(false)
        }
      }
    )
    let hostingView = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 670),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = isOnboarding ? "语界 · 设置候选翻译" : "语界 · 候选翻译语言"
    window.contentView = hostingView
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.center()
    settingsModel = model
    settingsWindow = window
    settingsWindowIsOnboarding = isOnboarding
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
    if settingsWindowIsOnboarding {
      UserDefaults.standard.set(true, forKey: Self.onboardingDefaultsKey)
      setEnabled(false)
    }
    settingsWindowIsOnboarding = false
    settingsWindow = nil
    settingsModel = nil
  }

  func translatedComments(
    candidates: [String],
    comments: [String],
    refresh: @escaping () -> Void
  ) -> [String] {
    guard isEnabled,
          UserDefaults.standard.bool(forKey: Self.onboardingDefaultsKey) else { return comments }

    var result = comments
    var missingWords = Set<String>()
    for index in candidates.indices where index < result.count {
      let candidate = candidates[index]
      guard Self.containsHan(candidate) else { continue }

      if activeLanguage == .english {
        // Preserve useful comments supplied by the active Rime schema. English
        // fallback is needed only for empty or explicitly approximate comments.
        guard Self.shouldReplace(comment: result[index]) else { continue }
        if let translated = localTranslation(for: candidate) {
          result[index] = translated
        } else if let translated = cache[candidate], !translated.isEmpty {
          result[index] = translated
        } else if retryAfter[candidate, default: .distantPast] <= .now {
          missingWords.insert(candidate)
        }
      } else if let translated = cache[candidate], !translated.isEmpty {
        // A selected non-English language is authoritative. This deliberately
        // replaces schema comments and legacy English Lua-filter output so one
        // candidate page can never mix target languages.
        result[index] = translated
      } else {
        // Clear a stale English/schema comment while the selected-language
        // translation is pending instead of briefly presenting the wrong language.
        result[index] = ""
        if retryAfter[candidate, default: .distantPast] <= .now {
          missingWords.insert(candidate)
        }
      }
    }

    if preparationSuspended {
      missingWords.removeAll()
    }
    desiredWords = missingWords
    refreshAction = refresh
    schedule(words: missingWords)
    return result
  }
}

@available(macOS 15.0, *)
private extension AppleCandidateTranslator {
  func startHost() {
    guard isEnabled,
          hasStarted,
          UserDefaults.standard.bool(forKey: Self.onboardingDefaultsKey),
          hostWindow == nil else { return }

    let channel = Self.makeRequestChannel()
    requestContinuation = channel.continuation
    let generation = UUID()
    activeHostGeneration = generation

    let host = AppleTranslationHost(
      state: hostState,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage
    ) { [weak self] session in
      await self?.run(session: session, stream: channel.stream, generation: generation)
    }
    let hostingView = NSHostingView(rootView: host)
    let window = AppleTranslationHostWindow(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    window.contentView = hostingView
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderFront(nil)
    hostWindow = window
  }

  func tearDownHost() {
    debounceTask?.cancel()
    requestContinuation?.finish()
    requestContinuation = nil
    hostWindow?.close()
    hostWindow = nil
    activeHostGeneration = UUID()
    desiredWords.removeAll()
    queuedWords.removeAll()
    inFlightWords.removeAll()
    retryAfter.removeAll()
    isPrepared = false
    preparationSuspended = false
    noticeHideTask?.cancel()
    noticeHideTask = nil
  }

  func restartHost() {
    tearDownHost()
    if isEnabled {
      startHost()
    }
  }

  func requestLanguagePreparation() {
    guard isEnabled else { return }
    if hostWindow == nil {
      startHost()
    }
    let word = Self.preparationSample
    guard !queuedWords.contains(word), !inFlightWords.contains(word) else { return }
    queuedWords.insert(word)
    requestContinuation?.yield([word])
  }

  func scheduleOnboardingIfNeeded() {
    guard !UserDefaults.standard.bool(forKey: Self.onboardingDefaultsKey),
          !hasScheduledOnboarding else { return }
    hasScheduledOnboarding = true
    onboardingTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(700))
      } catch {
        return
      }
      guard let self, self.settingsWindow == nil else { return }
      self.showLanguageSettings(isOnboarding: true)
    }
  }

  func closeLanguageSettings() {
    settingsWindowIsOnboarding = false
    settingsWindow?.orderOut(nil)
    settingsWindow?.close()
    settingsWindow = nil
    settingsModel = nil
  }

  var sourceLanguage: Locale.Language {
    Locale.Language(identifier: sourceLanguageIdentifier)
  }

  var targetLanguage: Locale.Language {
    activeLanguage.localeLanguage
  }

  static func makeRequestChannel() -> (
    stream: AsyncStream<[String]>,
    continuation: AsyncStream<[String]>.Continuation
  ) {
    var continuation: AsyncStream<[String]>.Continuation?
    let stream = AsyncStream<[String]> { continuation = $0 }
    return (stream, continuation!)
  }

  static func loadCache(from url: URL) -> [String: String] {
    guard let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
      return [:]
    }
    return decoded
  }

  static func cacheURL(for language: CandidateTranslationLanguage) -> URL {
    SquirrelApp.userDir
      .appendingPathComponent("candidate_translator", isDirectory: true)
      .appendingPathComponent("apple_translation_cache_\(language.rawValue).json", isDirectory: false)
  }

  static var legacyEnglishCacheURL: URL {
    SquirrelApp.userDir
      .appendingPathComponent("candidate_translator", isDirectory: true)
      .appendingPathComponent("apple_translation_cache.json", isDirectory: false)
  }

  var activeCacheURL: URL {
    Self.cacheURL(for: activeLanguage)
  }

  func loadActiveLanguageCache() {
    let url = activeCacheURL
    if FileManager.default.fileExists(atPath: url.path()) {
      cache = Self.loadCache(from: url)
    } else if activeLanguage == .english {
      cache = Self.loadCache(from: Self.legacyEnglishCacheURL)
    } else {
      cache = [:]
    }
  }

  func persistActiveCacheImmediately() {
    guard !cache.isEmpty else { return }
    do {
      let url = activeCacheURL
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try JSONEncoder().encode(cache).write(to: url, options: .atomic)
    } catch {
      print("Error saving Apple translation cache: \(error.localizedDescription)")
    }
  }

  static func shouldReplace(comment: String) -> Bool {
    let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.hasPrefix("≈") || trimmed.contains("≈ no dictionary entry")
  }

  static func containsHan(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      switch scalar.value {
      case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF:
        true
      default:
        false
      }
    }
  }

  func localTranslation(for text: String) -> String? {
    rawLocalTranslation(for: text).map { compact($0) }
  }

  func rawLocalTranslation(for text: String) -> String? {
    guard let scalar = text.unicodeScalars.first else { return nil }
    let bucketID = Int(scalar.value % 128)
    if missingDictionaryBuckets.contains(bucketID) {
      return nil
    }
    if localDictionaryBuckets[bucketID] == nil {
      localDictionaryBuckets[bucketID] = loadDictionaryBucket(id: bucketID)
    }
    return localDictionaryBuckets[bucketID]?[text]
  }

  func loadDictionaryBucket(id: Int) -> [String: String] {
    guard let sharedSupportURL = Bundle.main.sharedSupportURL else {
      missingDictionaryBuckets.insert(id)
      return [:]
    }
    let fileURL = sharedSupportURL
      .appendingPathComponent("candidate_translator", isDirectory: true)
      .appendingPathComponent("dictionary", isDirectory: true)
      .appendingPathComponent(String(format: "%03d.tsv", id), isDirectory: false)
    guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
      missingDictionaryBuckets.insert(id)
      return [:]
    }

    var entries = [String: String]()
    contents.enumerateLines { line, _ in
      guard let separator = line.firstIndex(of: "\t"), separator != line.startIndex else { return }
      let word = String(line[..<separator])
      let translationStart = line.index(after: separator)
      guard translationStart < line.endIndex else { return }
      entries[word] = String(line[translationStart...])
    }
    return entries
  }

  func schedule(words: Set<String>) {
    let waiting = words.subtracting(queuedWords).subtracting(inFlightWords)
    debounceTask?.cancel()
    guard !waiting.isEmpty else { return }

    debounceTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      do {
        try await Task.sleep(for: .milliseconds(self.debounceMilliseconds))
      } catch {
        return
      }
      let latest = self.desiredWords
        .subtracting(self.queuedWords)
        .subtracting(self.inFlightWords)
        .filter { self.retryAfter[$0, default: .distantPast] <= .now }
      guard !latest.isEmpty else { return }
      let batch = latest.sorted()
      self.queuedWords.formUnion(batch)
      self.requestContinuation?.yield(batch)
    }
  }

  func run(
    session: TranslationSession,
    stream: AsyncStream<[String]>,
    generation: UUID
  ) async {
    for await batch in stream {
      guard !Task.isCancelled, generation == activeHostGeneration else { return }
      queuedWords.subtract(batch)
      guard !preparationSuspended else { continue }
      inFlightWords.formUnion(batch)
      do {
        try await prepareIfNeeded(session: session, generation: generation)
        let requests = batch.map {
          TranslationSession.Request(sourceText: $0, clientIdentifier: $0)
        }
        let responses = try await session.translations(from: requests)
        guard generation == activeHostGeneration else { return }
        let translatedWords = store(responses: responses)
        inFlightWords.subtract(batch)
        // Anything the engine returned empty or untranslated would otherwise
        // be requested again on every keystroke that shows the candidate.
        postpone(Set(batch).subtracting(translatedWords), by: Self.untranslatableRetryDelay)
        if !desiredWords.isDisjoint(with: translatedWords) {
          refreshAction?()
        }
      } catch is CancellationError {
        if generation == activeHostGeneration {
          inFlightWords.subtract(batch)
        }
        return
      } catch {
        guard generation == activeHostGeneration else { return }
        inFlightWords.subtract(batch)
        print("Apple translation failed: \(error.localizedDescription)")
        if isPrepared {
          // A transient failure after the model is ready: retry later without
          // interrupting the application the user is typing in.
          postpone(Set(batch), by: Self.retryDelay)
        } else {
          preparationSuspended = true
          desiredWords.removeAll()
          debounceTask?.cancel()
          showNotice(
            message: "未能准备中文与\(activeLanguage.chineseName)的本机翻译\n可在语界菜单“管理翻译语言…”中重新选择。"
          )
        }
      }
    }
  }

  func postpone(_ words: Set<String>, by delay: TimeInterval) {
    guard !words.isEmpty else { return }
    if retryAfter.count > Self.retryTableLimit {
      let now = Date.now
      retryAfter = retryAfter.filter { $0.value > now }
    }
    let retryDate = Date.now.addingTimeInterval(delay)
    for word in words {
      retryAfter[word] = retryDate
    }
  }

  func prepareIfNeeded(session: TranslationSession, generation: UUID) async throws {
    guard generation == activeHostGeneration else { throw CancellationError() }
    guard !isPrepared else { return }
    let availability = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
    guard generation == activeHostGeneration else { throw CancellationError() }
    switch availability {
    case .installed:
      break
    case .supported:
      showPreparationWindow(message: "正在准备中文与\(activeLanguage.chineseName)离线翻译模型…\n首次使用时，macOS 会询问是否下载语言。")
    case .unsupported:
      throw TranslationError.unsupportedLanguagePairing
    @unknown default:
      throw TranslationError.unsupportedLanguagePairing
    }
    try await session.prepareTranslation()
    guard generation == activeHostGeneration else { throw CancellationError() }
    isPrepared = true
    hidePreparationWindow()
  }

  func store(responses: [TranslationSession.Response]) -> Set<String> {
    var translatedWords = Set<String>()
    for response in responses {
      let source = response.clientIdentifier ?? response.sourceText
      let translated = compact(response.targetText)
      guard !translated.isEmpty else { continue }
      // Japanese naturally contains Han characters and shares many written
      // forms with Chinese (学生 → 学生), so an identical result is valid there.
      // For the other targets, a response that still contains Han characters
      // means the source was returned untranslated.
      if activeLanguage != .japanese {
        guard translated != source, !Self.containsHan(translated) else { continue }
      }
      cache[source] = translated
      retryAfter[source] = nil
      translatedWords.insert(source)
    }
    if !translatedWords.isEmpty {
      scheduleCacheWrite()
    }
    return translatedWords
  }

  func compact(_ text: String) -> String {
    let compacted = text
      .replacingOccurrences(of: "\n", with: " ")
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard compacted.count > maxCommentCharacters else { return compacted }

    let clipped = String(compacted.prefix(maxCommentCharacters))
    if let boundary = clipped.lastIndex(of: " "),
       clipped.distance(from: clipped.startIndex, to: boundary) >= maxCommentCharacters * 3 / 5 {
      return String(clipped[..<boundary]) + "…"
    }
    return clipped + "…"
  }

  func scheduleCacheWrite() {
    persistTask?.cancel()
    let snapshot = cache
    let url = activeCacheURL
    persistTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .milliseconds(500))
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
      } catch is CancellationError {
        return
      } catch {
        print("Error saving Apple translation cache: \(error.localizedDescription)")
      }
    }
  }

  /// Shows the host window as a key window. Only used while macOS needs a key
  /// window to attach its language-download sheet to.
  func showPreparationWindow(message: String) {
    noticeHideTask?.cancel()
    hostState.message = message
    guard let window = hostWindow else { return }
    window.center()
    window.alphaValue = 1
    window.ignoresMouseEvents = false
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  /// Shows a short message without taking focus from the application the user
  /// is typing in, and removes it again after a few seconds.
  func showNotice(message: String) {
    noticeHideTask?.cancel()
    hostState.message = message
    guard let window = hostWindow else { return }
    window.center()
    window.alphaValue = 1
    window.ignoresMouseEvents = true
    window.orderFrontRegardless()
    noticeHideTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: Self.noticeDuration)
      } catch {
        return
      }
      self?.hidePreparationWindow()
    }
  }

  func hidePreparationWindow() {
    noticeHideTask?.cancel()
    noticeHideTask = nil
    guard let window = hostWindow else { return }
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderFront(nil)
  }
}

@available(macOS 15.0, *)
@MainActor
private enum TranslationLanguageDownloadStatus: Equatable {
  case checking
  case installed
  case downloadRequired
  case unsupported

  var title: String {
    switch self {
    case .checking: "检查中…"
    case .installed: "已下载"
    case .downloadRequired: "需要下载"
    case .unsupported: "此设备不支持"
    }
  }

  var color: Color {
    switch self {
    case .installed: Color(red: 0.18, green: 0.55, blue: 0.32)
    case .downloadRequired: Color(red: 0.78, green: 0.45, blue: 0.08)
    case .checking, .unsupported: Color(nsColor: .secondaryLabelColor)
    }
  }
}

@available(macOS 15.0, *)
@MainActor
private final class TranslationLanguageSettingsModel: ObservableObject {
  let sourceLanguage: Locale.Language
  @Published var selectedLanguage: CandidateTranslationLanguage
  @Published var isEnabled: Bool
  @Published private(set) var statuses: [CandidateTranslationLanguage: TranslationLanguageDownloadStatus]

  init(
    sourceLanguage: Locale.Language,
    selectedLanguage: CandidateTranslationLanguage,
    isEnabled: Bool
  ) {
    self.sourceLanguage = sourceLanguage
    self.selectedLanguage = selectedLanguage
    self.isEnabled = isEnabled
    statuses = Dictionary(
      uniqueKeysWithValues: CandidateTranslationLanguage.allCases.map { ($0, .checking) }
    )
  }

  func status(for language: CandidateTranslationLanguage) -> TranslationLanguageDownloadStatus {
    statuses[language] ?? .checking
  }

  func refreshAvailability() async {
    let availability = LanguageAvailability()
    for language in CandidateTranslationLanguage.allCases {
      guard !Task.isCancelled else { return }
      let status = await availability.status(from: sourceLanguage, to: language.localeLanguage)
      guard !Task.isCancelled else { return }
      switch status {
      case .installed:
        statuses[language] = .installed
      case .supported:
        statuses[language] = .downloadRequired
      case .unsupported:
        statuses[language] = .unsupported
      @unknown default:
        statuses[language] = .unsupported
      }
    }
  }
}

@available(macOS 15.0, *)
@MainActor
private struct TranslationLanguageSettingsView: View {
  @ObservedObject var model: TranslationLanguageSettingsModel
  let isOnboarding: Bool
  let onCancel: () -> Void
  let onSave: (CandidateTranslationLanguage, Bool) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "character.book.closed.fill")
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(Color(red: 0.20, green: 0.53, blue: 0.34))
          .frame(width: 42, height: 42)
          .background(Color(red: 0.87, green: 0.95, blue: 0.89), in: RoundedRectangle(cornerRadius: 11))
        VStack(alignment: .leading, spacing: 5) {
          Text(isOnboarding ? "选择你的候选翻译语言" : "候选翻译语言")
            .font(.system(size: 22, weight: .bold))
          Text("候选窗一次显示一种译文，之后可从语界菜单随时切换。")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
      }

      Toggle("启用候选词实时翻译", isOn: $model.isEnabled)
        .toggleStyle(.switch)
        .font(.system(size: 14, weight: .medium))

      VStack(spacing: 7) {
        ForEach(CandidateTranslationLanguage.allCases) { language in
          languageRow(language)
        }
      }
      .opacity(model.isEnabled ? 1 : 0.48)

      Spacer(minLength: 0)
      Divider()
      Text(footerText)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Button(isOnboarding ? "暂不开启" : "取消", action: onCancel)
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button(applyButtonTitle) {
          onSave(model.selectedLanguage, model.isEnabled)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.20, green: 0.53, blue: 0.34))
        .keyboardShortcut(.defaultAction)
        .disabled(!canApply)
      }
    }
    .padding(24)
    .frame(width: 540, height: 670)
    .task {
      await model.refreshAvailability()
    }
  }

  private func languageRow(_ language: CandidateTranslationLanguage) -> some View {
    let selected = model.selectedLanguage == language
    let status = model.status(for: language)
    return Button {
      model.selectedLanguage = language
    } label: {
      HStack(spacing: 12) {
        Text(language.shortCode)
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .foregroundStyle(selected ? Color.white : Color(nsColor: .labelColor))
          .frame(width: 42, height: 30)
          .background(
            selected ? Color(red: 0.20, green: 0.53, blue: 0.34) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
          )
        VStack(alignment: .leading, spacing: 2) {
          Text(language.chineseName)
            .font(.system(size: 14, weight: .semibold))
          Text(language.nativeName)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text(status.title)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(status.color)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(selected ? Color(red: 0.20, green: 0.53, blue: 0.34) : Color(nsColor: .tertiaryLabelColor))
      }
      .padding(.horizontal, 12)
      .frame(height: 48)
      .background(
        selected ? Color(red: 0.89, green: 0.96, blue: 0.91) : Color.clear,
        in: RoundedRectangle(cornerRadius: 11)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 11)
          .stroke(selected ? Color(red: 0.63, green: 0.80, blue: 0.68) : Color(nsColor: .separatorColor), lineWidth: 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!model.isEnabled || status == .unsupported)
  }

  private var selectedStatus: TranslationLanguageDownloadStatus {
    model.status(for: model.selectedLanguage)
  }

  private var canApply: Bool {
    !model.isEnabled || (selectedStatus != .checking && selectedStatus != .unsupported)
  }

  private var applyButtonTitle: String {
    guard model.isEnabled else { return "保存" }
    return selectedStatus == .installed ? "使用此语言" : "下载并使用"
  }

  private var footerText: String {
    if !model.isEnabled {
      return "关闭后，候选窗将恢复为普通语界样式。"
    }
    if selectedStatus == .installed {
      return "该语言已由 macOS 准备完成，可以直接使用。"
    }
    return "所选语言尚未下载时，macOS 会显示官方语言下载面板；模型由系统统一管理。"
  }
}

@available(macOS 15.0, *)
@MainActor
private final class AppleTranslationHostWindow: NSWindow {
  // Borderless windows are not key by default. The Translation framework
  // needs a key host window in order to attach its language-download sheet.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

@available(macOS 15.0, *)
@MainActor
private final class AppleTranslationHostState: ObservableObject {
  @Published var message = "Apple 本机翻译正在待命。"
}

@available(macOS 15.0, *)
private struct AppleTranslationHost: View {
  @ObservedObject var state: AppleTranslationHostState
  let sourceLanguage: Locale.Language
  let targetLanguage: Locale.Language
  let onSession: (TranslationSession) async -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "translate")
        .font(.system(size: 25, weight: .medium))
        .foregroundStyle(.green)
      Text(state.message)
        .multilineTextAlignment(.center)
        .lineLimit(3)
    }
    .padding(22)
    .frame(width: 380, height: 150)
    .translationTask(source: sourceLanguage, target: targetLanguage) { session in
      await onSession(session)
    }
  }
}
