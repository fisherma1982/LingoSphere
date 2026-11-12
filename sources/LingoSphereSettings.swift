//
//  LingoSphereSettings.swift
//  Squirrel
//

import AppKit
import SwiftUI

enum LingoSphereCandidateLayout: String, CaseIterable, Identifiable {
  case stacked
  case linear

  var id: String { rawValue }
  var title: String { self == .stacked ? "纵向列表" : "横向排列" }
}

enum LingoSphereTextOrientation: String, CaseIterable, Identifiable {
  case horizontal
  case vertical

  var id: String { rawValue }
  var title: String { self == .horizontal ? "横排文字" : "竖排文字" }
}

enum LingoSphereThemePreset: String, CaseIterable, Identifiable {
  case brand
  case system
  case graphite

  var id: String { rawValue }

  var title: String {
    switch self {
    case .brand: "语界清新"
    case .system: "系统原生"
    case .graphite: "石墨深色"
    }
  }

  var lightColorScheme: String {
    switch self {
    case .brand: "lingosphere_light"
    case .system: "native"
    case .graphite: "lingosphere_graphite"
    }
  }

  var darkColorScheme: String {
    switch self {
    case .brand: "lingosphere_dark"
    case .system: "native"
    case .graphite: "lingosphere_graphite"
    }
  }
}

enum LingoSphereFontPreset: String, CaseIterable, Identifiable {
  case system
  case pingFang
  case hiragino
  case helvetica

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "系统默认"
    case .pingFang: "苹方"
    case .hiragino: "冬青黑体"
    case .helvetica: "Helvetica Neue"
    }
  }

  var configValue: String {
    switch self {
    case .system: ""
    case .pingFang: "PingFang SC"
    case .hiragino: "Hiragino Sans GB"
    case .helvetica: "Helvetica Neue"
    }
  }

  static func resolve(_ value: String?) -> Self {
    let value = value?.lowercased() ?? ""
    if value.contains("pingfang") { return .pingFang }
    if value.contains("hiragino") { return .hiragino }
    if value.contains("helvetica") { return .helvetica }
    return .system
  }
}

struct LingoSphereAppearanceSettings: Equatable {
  private static let keyPrefix = "LingoSphere.Appearance."

  var theme: LingoSphereThemePreset
  var layout: LingoSphereCandidateLayout
  var orientation: LingoSphereTextOrientation
  var font: LingoSphereFontPreset
  var inlinePreedit: Bool
  var showPaging: Bool
  var translucency: Bool
  var fontSize: Double
  var commentFontSize: Double
  var lineSpacing: Double
  var cornerRadius: Double
  var highlightedCornerRadius: Double
  var horizontalPadding: Double
  var verticalPadding: Double
  var opacity: Double

  static let recommended = Self(
    theme: .brand,
    layout: .stacked,
    orientation: .horizontal,
    font: .system,
    inlinePreedit: true,
    showPaging: false,
    translucency: false,
    fontSize: 17,
    commentFontSize: 13,
    lineSpacing: 4,
    cornerRadius: 12,
    highlightedCornerRadius: 7,
    horizontalPadding: 10,
    verticalPadding: 8,
    opacity: 0.98
  )

  static func load(config: SquirrelConfig?) -> Self {
    let defaults = UserDefaults.standard
    let fallbackTheme = resolveTheme(config?.getString("style/color_scheme"))
    let fallbackLayout = LingoSphereCandidateLayout(
      rawValue: config?.getString("style/candidate_list_layout") ?? ""
    ) ?? recommended.layout
    let fallbackOrientation = LingoSphereTextOrientation(
      rawValue: config?.getString("style/text_orientation") ?? ""
    ) ?? recommended.orientation
    let fallbackFont = LingoSphereFontPreset.resolve(config?.getString("style/font_face"))

    return Self(
      theme: storedEnum("theme", defaults: defaults) ?? fallbackTheme,
      layout: storedEnum("layout", defaults: defaults) ?? fallbackLayout,
      orientation: storedEnum("orientation", defaults: defaults) ?? fallbackOrientation,
      font: storedEnum("font", defaults: defaults) ?? fallbackFont,
      inlinePreedit: storedBool("inlinePreedit", defaults: defaults)
        ?? config?.getBool("style/inline_preedit") ?? recommended.inlinePreedit,
      showPaging: storedBool("showPaging", defaults: defaults)
        ?? config?.getBool("style/show_paging") ?? recommended.showPaging,
      translucency: storedBool("translucency", defaults: defaults)
        ?? config?.getBool("style/translucency") ?? recommended.translucency,
      fontSize: storedDouble("fontSize", defaults: defaults)
        ?? config?.getDouble("style/font_point").map(Double.init) ?? recommended.fontSize,
      commentFontSize: storedDouble("commentFontSize", defaults: defaults)
        ?? config?.getDouble("style/comment_font_point").map(Double.init) ?? recommended.commentFontSize,
      lineSpacing: storedDouble("lineSpacing", defaults: defaults)
        ?? config?.getDouble("style/line_spacing").map(Double.init) ?? recommended.lineSpacing,
      cornerRadius: storedDouble("cornerRadius", defaults: defaults)
        ?? config?.getDouble("style/corner_radius").map(Double.init) ?? recommended.cornerRadius,
      highlightedCornerRadius: storedDouble("highlightedCornerRadius", defaults: defaults)
        ?? config?.getDouble("style/hilited_corner_radius").map(Double.init) ?? recommended.highlightedCornerRadius,
      horizontalPadding: storedDouble("horizontalPadding", defaults: defaults)
        ?? config?.getDouble("style/border_width").map(Double.init) ?? recommended.horizontalPadding,
      verticalPadding: storedDouble("verticalPadding", defaults: defaults)
        ?? config?.getDouble("style/border_height").map(Double.init) ?? recommended.verticalPadding,
      opacity: storedDouble("opacity", defaults: defaults) ?? recommended.opacity
    )
  }

  func save() {
    let defaults = UserDefaults.standard
    defaults.set(theme.rawValue, forKey: Self.keyPrefix + "theme")
    defaults.set(layout.rawValue, forKey: Self.keyPrefix + "layout")
    defaults.set(orientation.rawValue, forKey: Self.keyPrefix + "orientation")
    defaults.set(font.rawValue, forKey: Self.keyPrefix + "font")
    defaults.set(inlinePreedit, forKey: Self.keyPrefix + "inlinePreedit")
    defaults.set(showPaging, forKey: Self.keyPrefix + "showPaging")
    defaults.set(translucency, forKey: Self.keyPrefix + "translucency")
    defaults.set(fontSize, forKey: Self.keyPrefix + "fontSize")
    defaults.set(commentFontSize, forKey: Self.keyPrefix + "commentFontSize")
    defaults.set(lineSpacing, forKey: Self.keyPrefix + "lineSpacing")
    defaults.set(cornerRadius, forKey: Self.keyPrefix + "cornerRadius")
    defaults.set(highlightedCornerRadius, forKey: Self.keyPrefix + "highlightedCornerRadius")
    defaults.set(horizontalPadding, forKey: Self.keyPrefix + "horizontalPadding")
    defaults.set(verticalPadding, forKey: Self.keyPrefix + "verticalPadding")
    defaults.set(opacity, forKey: Self.keyPrefix + "opacity")
  }
}

private extension LingoSphereAppearanceSettings {
  static func storedEnum<T: RawRepresentable>(
    _ key: String,
    defaults: UserDefaults
  ) -> T? where T.RawValue == String {
    guard let value = defaults.string(forKey: keyPrefix + key) else { return nil }
    return T(rawValue: value)
  }

  static func storedBool(_ key: String, defaults: UserDefaults) -> Bool? {
    guard defaults.object(forKey: keyPrefix + key) != nil else { return nil }
    return defaults.bool(forKey: keyPrefix + key)
  }

  static func storedDouble(_ key: String, defaults: UserDefaults) -> Double? {
    (defaults.object(forKey: keyPrefix + key) as? NSNumber)?.doubleValue
  }

  static func resolveTheme(_ value: String?) -> LingoSphereThemePreset {
    switch value {
    case "native": .system
    case "lingosphere_graphite": .graphite
    default: .brand
    }
  }
}

enum LingoSphereKeyboardLayout: String, CaseIterable, Identifiable {
  case last
  case systemDefault = "default"

  var id: String { rawValue }
  var title: String { self == .last ? "沿用上次键盘布局" : "始终使用 ABC" }
}

struct LingoSphereGeneralSettings {
  private static let keyPrefix = "LingoSphere.General."

  var keyboardLayout: LingoSphereKeyboardLayout
  var pageSize: Int
  var showStatusIcon: Bool
  var showNotifications: Bool

  static func load(config: SquirrelConfig?) -> Self {
    let defaults = UserDefaults.standard
    return Self(
      keyboardLayout: LingoSphereKeyboardLayout(
        rawValue: defaults.string(forKey: keyPrefix + "keyboardLayout")
          ?? config?.getString("keyboard_layout") ?? ""
      ) ?? .last,
      pageSize: max(3, min(10, storedInt("pageSize", defaults: defaults)
        ?? config?.getInt("menu/page_size") ?? 5)),
      showStatusIcon: storedBool("showStatusIcon", defaults: defaults)
        ?? config?.getBool("status_icon/show") ?? true,
      showNotifications: storedBool("showNotifications", defaults: defaults)
        ?? (config?.getString("show_notifications_when") != "never")
    )
  }

  func save() {
    let defaults = UserDefaults.standard
    defaults.set(keyboardLayout.rawValue, forKey: Self.keyPrefix + "keyboardLayout")
    defaults.set(pageSize, forKey: Self.keyPrefix + "pageSize")
    defaults.set(showStatusIcon, forKey: Self.keyPrefix + "showStatusIcon")
    defaults.set(showNotifications, forKey: Self.keyPrefix + "showNotifications")
  }

  private static func storedBool(_ key: String, defaults: UserDefaults) -> Bool? {
    guard defaults.object(forKey: keyPrefix + key) != nil else { return nil }
    return defaults.bool(forKey: keyPrefix + key)
  }

  private static func storedInt(_ key: String, defaults: UserDefaults) -> Int? {
    (defaults.object(forKey: keyPrefix + key) as? NSNumber)?.intValue
  }
}

private enum LingoSphereRimeSettingValue {
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
}

private enum LingoSphereSettingsError: LocalizedError {
  case leversUnavailable
  case cannotCreateSettings(String)
  case cannotCustomize(String)
  case cannotSave(String)

  var errorDescription: String? {
    switch self {
    case .leversUnavailable: "Rime 配置服务暂时不可用，请重新启动语界后再试。"
    case .cannotCreateSettings(let name): "无法读取 \(name) 配置。"
    case .cannotCustomize(let key): "无法修改设置：\(key)"
    case .cannotSave(let name): "无法保存 \(name) 配置。"
    }
  }
}

private final class LingoSphereRimeSettingsWriter {
  static let backupRoot = SquirrelApp.userDir
    .appendingPathComponent("lingosphere", isDirectory: true)
    .appendingPathComponent("settings-backups", isDirectory: true)

  private let rimeAPI = rime_get_api_stdbool().pointee
  private let fileManager = FileManager.default

  func save(
    general: LingoSphereGeneralSettings,
    appearance: LingoSphereAppearanceSettings,
    translationEnabled: Bool,
    translationLanguage: CandidateTranslationLanguage,
    translationDelay: Int,
    translationLength: Int
  ) throws {
    let snapshots = try createBackups(configIDs: ["squirrel", "default"])
    do {
      try customize(
        configID: "squirrel",
        values: [
          "keyboard_layout": .string(general.keyboardLayout.rawValue),
          "show_notifications_when": .string(general.showNotifications ? "appropriate" : "never"),
          "status_icon/show": .bool(general.showStatusIcon),
          "apple_translation/enabled": .bool(translationEnabled),
          "apple_translation/target_language": .string(translationLanguage.rawValue),
          "apple_translation/debounce_ms": .int(translationDelay),
          "apple_translation/max_comment_chars": .int(translationLength),
          "style/color_scheme": .string(appearance.theme.lightColorScheme),
          "style/color_scheme_dark": .string(appearance.theme.darkColorScheme),
          "style/candidate_list_layout": .string(appearance.layout.rawValue),
          "style/text_orientation": .string(appearance.orientation.rawValue),
          "style/inline_preedit": .bool(appearance.inlinePreedit),
          "style/show_paging": .bool(appearance.showPaging),
          "style/translucency": .bool(appearance.translucency),
          "style/memorize_size": .bool(false),
          "style/mutual_exclusive": .bool(true),
          "style/font_face": .string(appearance.font.configValue),
          "style/font_point": .double(appearance.fontSize),
          "style/label_font_face": .string(appearance.font.configValue),
          "style/comment_font_face": .string(appearance.font.configValue),
          "style/comment_font_point": .double(appearance.commentFontSize),
          "style/line_spacing": .double(appearance.lineSpacing),
          "style/corner_radius": .double(appearance.cornerRadius),
          "style/hilited_corner_radius": .double(appearance.highlightedCornerRadius),
          "style/border_width": .double(appearance.horizontalPadding),
          "style/border_height": .double(appearance.verticalPadding),
          "style/alpha": .double(appearance.opacity)
        ]
      )
      try customize(configID: "default", values: ["menu/page_size": .int(general.pageSize)])
    } catch {
      restore(snapshots)
      throw error
    }
  }
}

private extension LingoSphereRimeSettingsWriter {
  struct ConfigSnapshot {
    let destination: URL
    let backup: URL?
  }

  func leversAPI() throws -> RimeLeversApi_stdbool {
    guard let module = rimeAPI.find_module("levers"),
          let getAPI = module.pointee.get_api,
          let rawAPI = getAPI() else {
      throw LingoSphereSettingsError.leversUnavailable
    }
    return UnsafeRawPointer(rawAPI)
      .assumingMemoryBound(to: RimeLeversApi_stdbool.self)
      .pointee
  }

  func customize(configID: String, values: [String: LingoSphereRimeSettingValue]) throws {
    let api = try leversAPI()
    guard let initialize = api.custom_settings_init,
          let destroy = api.custom_settings_destroy,
          let load = api.load_settings,
          let save = api.save_settings else {
      throw LingoSphereSettingsError.leversUnavailable
    }
    let generatorID = "lingosphere.settings"
    let settings = configID.withCString { configIDPointer in
      generatorID.withCString { generatorPointer in
        initialize(configIDPointer, generatorPointer)
      }
    }
    guard let settings else {
      throw LingoSphereSettingsError.cannotCreateSettings(configID)
    }
    defer { destroy(settings) }
    let customConfig = SquirrelApp.userDir
      .appendingPathComponent("\(configID).custom.yaml", isDirectory: false)
    let loaded = load(settings)
    if fileManager.fileExists(atPath: customConfig.path()) && !loaded {
      // Never replace a malformed or otherwise unreadable user file. The
      // visual editor only proceeds when librime can preserve its contents.
      throw LingoSphereSettingsError.cannotCreateSettings(configID)
    }

    for (key, value) in values {
      let success: Bool
      switch value {
      case .bool(let value):
        guard let customize = api.customize_bool else {
          throw LingoSphereSettingsError.leversUnavailable
        }
        success = key.withCString { customize(settings, $0, value) }
      case .int(let value):
        guard let customize = api.customize_int else {
          throw LingoSphereSettingsError.leversUnavailable
        }
        success = key.withCString { customize(settings, $0, Int32(value)) }
      case .double(let value):
        guard let customize = api.customize_double else {
          throw LingoSphereSettingsError.leversUnavailable
        }
        success = key.withCString { customize(settings, $0, value) }
      case .string(let value):
        guard let customize = api.customize_string else {
          throw LingoSphereSettingsError.leversUnavailable
        }
        success = key.withCString { keyPointer in
          value.withCString { customize(settings, keyPointer, $0) }
        }
      }
      if !success {
        throw LingoSphereSettingsError.cannotCustomize(key)
      }
    }
    guard save(settings) else {
      throw LingoSphereSettingsError.cannotSave(configID)
    }
  }

  func createBackups(configIDs: [String]) throws -> [ConfigSnapshot] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    let directory = Self.backupRoot.appendingPathComponent(
      formatter.string(from: .now),
      isDirectory: true
    )
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    return try configIDs.map { configID in
      let destination = SquirrelApp.userDir
        .appendingPathComponent("\(configID).custom.yaml", isDirectory: false)
      guard fileManager.fileExists(atPath: destination.path()) else {
        return ConfigSnapshot(destination: destination, backup: nil)
      }
      let backup = directory.appendingPathComponent(destination.lastPathComponent, isDirectory: false)
      try fileManager.copyItem(at: destination, to: backup)
      return ConfigSnapshot(destination: destination, backup: backup)
    }
  }

  func restore(_ snapshots: [ConfigSnapshot]) {
    for snapshot in snapshots {
      try? fileManager.removeItem(at: snapshot.destination)
      if let backup = snapshot.backup {
        try? fileManager.copyItem(at: backup, to: snapshot.destination)
      }
    }
  }
}

@available(macOS 15.0, *)
@MainActor
final class LingoSphereSettingsViewModel: ObservableObject {
  enum Section: String, CaseIterable, Identifiable {
    case general
    case appearance
    case translation
    case data

    var id: String { rawValue }

    var title: String {
      switch self {
      case .general: "常规"
      case .appearance: "候选窗"
      case .translation: "翻译"
      case .data: "数据与高级"
      }
    }

    var icon: String {
      switch self {
      case .general: "switch.2"
      case .appearance: "rectangle.3.group"
      case .translation: "character.book.closed"
      case .data: "externaldrive"
      }
    }
  }

  @Published var selectedSection = Section.general
  @Published var keyboardLayout: LingoSphereKeyboardLayout
  @Published var pageSize: Int
  @Published var showStatusIcon: Bool
  @Published var showNotifications: Bool
  @Published var appearance: LingoSphereAppearanceSettings
  @Published var translationEnabled: Bool
  @Published var translationLanguage: CandidateTranslationLanguage
  @Published var translationDelay: Int
  @Published var translationLength: Int
  @Published var isApplying = false
  @Published var feedback = ""
  @Published var feedbackIsError = false

  private weak var appDelegate: SquirrelApplicationDelegate?

  init(appDelegate: SquirrelApplicationDelegate) {
    self.appDelegate = appDelegate
    let general = LingoSphereGeneralSettings.load(config: appDelegate.config)
    keyboardLayout = general.keyboardLayout
    pageSize = general.pageSize
    showStatusIcon = general.showStatusIcon
    showNotifications = general.showNotifications
    appearance = LingoSphereAppearanceSettings.load(config: appDelegate.config)
    translationEnabled = appDelegate.appleCandidateTranslator?.isEnabled ?? true
    translationLanguage = appDelegate.appleCandidateTranslator?.activeLanguage ?? .english
    translationDelay = max(80, min(1_000, appDelegate.config?.getInt("apple_translation/debounce_ms") ?? 220))
    translationLength = max(12, min(120, appDelegate.config?.getInt("apple_translation/max_comment_chars") ?? 38))
  }

  func apply() {
    guard let appDelegate else { return }
    isApplying = true
    feedback = ""
    defer { isApplying = false }

    let general = LingoSphereGeneralSettings(
      keyboardLayout: keyboardLayout,
      pageSize: pageSize,
      showStatusIcon: showStatusIcon,
      showNotifications: showNotifications
    )
    do {
      try LingoSphereRimeSettingsWriter().save(
        general: general,
        appearance: appearance,
        translationEnabled: translationEnabled,
        translationLanguage: translationLanguage,
        translationDelay: translationDelay,
        translationLength: translationLength
      )
      general.save()
      appearance.save()
      if translationEnabled {
        appDelegate.appleCandidateTranslator?.selectLanguage(translationLanguage, prepare: true)
      } else {
        appDelegate.appleCandidateTranslator?.setEnabled(false)
      }
      appDelegate.deploy()
      feedbackIsError = false
      feedback = "设置已保存并生效。"
    } catch {
      feedbackIsError = true
      feedback = error.localizedDescription
    }
  }

  func restoreRecommendedValues() {
    keyboardLayout = .last
    pageSize = 6
    showStatusIcon = true
    showNotifications = true
    appearance = .recommended
    translationEnabled = true
    translationLanguage = .english
    translationDelay = 220
    translationLength = 38
    feedback = "已载入推荐值，点击“应用设置”后生效。"
    feedbackIsError = false
  }

  func manageTranslationLanguages() {
    appDelegate?.appleCandidateTranslator?.showLanguageSettings()
  }

  func redeploy() {
    appDelegate?.deploy()
    feedback = "重新部署已完成。"
    feedbackIsError = false
  }

  func sync() {
    appDelegate?.syncUserData()
    feedback = "用户数据同步已启动。"
    feedbackIsError = false
  }

  func openUserFolder() {
    appDelegate?.openRimeFolder()
  }

  func openLogFolder() {
    appDelegate?.openLogFolder()
  }

  func openBackupFolder() {
    try? FileManager.default.createDirectory(
      at: LingoSphereRimeSettingsWriter.backupRoot,
      withIntermediateDirectories: true
    )
    NSWorkspace.shared.open(LingoSphereRimeSettingsWriter.backupRoot)
  }
}

@available(macOS 15.0, *)
@MainActor
final class LingoSphereSettingsWindowController: NSObject, NSWindowDelegate {
  private weak var appDelegate: SquirrelApplicationDelegate?
  private var window: NSWindow?

  init(appDelegate: SquirrelApplicationDelegate) {
    self.appDelegate = appDelegate
  }

  func show() {
    if let window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }
    guard let appDelegate else { return }
    let model = LingoSphereSettingsViewModel(appDelegate: appDelegate)
    let view = LingoSphereSettingsView(model: model) { [weak self] in
      self?.window?.close()
    }
    let hostingView = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "语界设置"
    window.contentMinSize = NSSize(width: 820, height: 590)
    window.contentView = hostingView
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.center()
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard let closingWindow = notification.object as? NSWindow,
          closingWindow === window else { return }
    window = nil
  }
}

@available(macOS 15.0, *)
private struct LingoSphereSettingsView: View {
  @ObservedObject var model: LingoSphereSettingsViewModel
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        sidebar
        Divider()
        sectionContent
      }
      Divider()
      bottomBar
    }
    .frame(minWidth: 820, minHeight: 590)
  }
}

@available(macOS 15.0, *)
private extension LingoSphereSettingsView {
  var sidebar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 11) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .scaledToFit()
          .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 1) {
          Text("语界")
            .font(.system(size: 18, weight: .bold))
          Text("LingoSphere")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 12)

      ForEach(LingoSphereSettingsViewModel.Section.allCases) { section in
        Button {
          model.selectedSection = section
        } label: {
          Label(section.title, systemImage: section.icon)
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
              model.selectedSection == section
                ? Color.accentColor.opacity(0.14) : Color.clear,
              in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
      }

      Spacer()
      Text("基于 Rime 开源输入法引擎")
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
    }
    .padding(.vertical, 18)
    .padding(.horizontal, 10)
    .frame(width: 200)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.58))
  }

  var sectionContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.selectedSection.title)
            .font(.system(size: 24, weight: .bold))
          Text(sectionSubtitle)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }
        sectionBody
      }
      .padding(26)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  var sectionSubtitle: String {
    switch model.selectedSection {
    case .general: "调整日常输入行为，保存后由语界自动部署。"
    case .appearance: "候选窗样式会覆盖输入方案自带样式，所见即所得。"
    case .translation: "选择候选翻译语言，并管理 Apple 本机语言模型。"
    case .data: "管理配置、词库与诊断数据。"
    }
  }

  @ViewBuilder
  var sectionBody: some View {
    switch model.selectedSection {
    case .general: generalSection
    case .appearance: appearanceSection
    case .translation: translationSection
    case .data: dataSection
    }
  }

  var generalSection: some View {
    VStack(spacing: 16) {
      settingsCard("候选与键盘", icon: "keyboard") {
        LabeledContent("每页候选数量") {
          Stepper("\(model.pageSize) 个", value: $model.pageSize, in: 3...10)
            .frame(width: 150)
        }
        Divider()
        LabeledContent("英文键盘布局") {
          Picker("", selection: $model.keyboardLayout) {
            ForEach(LingoSphereKeyboardLayout.allCases) { layout in
              Text(layout.title).tag(layout)
            }
          }
          .labelsHidden()
          .frame(width: 190)
        }
      }

      settingsCard("状态提示", icon: "menubar.rectangle") {
        Toggle("在菜单栏显示当前输入状态", isOn: $model.showStatusIcon)
        Divider()
        Toggle("显示部署和模式切换通知", isOn: $model.showNotifications)
      }
    }
  }

  var appearanceSection: some View {
    VStack(spacing: 16) {
      candidatePreview
      settingsCard("布局", icon: "rectangle.split.3x1") {
        LabeledContent("候选排列") {
          Picker("", selection: $model.appearance.layout) {
            ForEach(LingoSphereCandidateLayout.allCases) { layout in
              Text(layout.title).tag(layout)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 220)
        }
        Divider()
        LabeledContent("文字方向") {
          Picker("", selection: $model.appearance.orientation) {
            ForEach(LingoSphereTextOrientation.allCases) { orientation in
              Text(orientation.title).tag(orientation)
            }
          }
          .labelsHidden()
          .frame(width: 170)
        }
        Divider()
        Toggle("将拼音显示在正在输入的位置", isOn: $model.appearance.inlinePreedit)
        Toggle("显示翻页箭头", isOn: $model.appearance.showPaging)
        Toggle("使用半透明候选窗材质", isOn: $model.appearance.translucency)
      }

      settingsCard("字体与尺寸", icon: "textformat.size") {
        LabeledContent("字体") {
          Picker("", selection: $model.appearance.font) {
            ForEach(LingoSphereFontPreset.allCases) { font in
              Text(font.title).tag(font)
            }
          }
          .labelsHidden()
          .frame(width: 170)
        }
        valueSlider("候选字号", value: $model.appearance.fontSize, range: 13...26, suffix: " pt")
        valueSlider("翻译字号", value: $model.appearance.commentFontSize, range: 10...22, suffix: " pt")
        valueSlider("行间距", value: $model.appearance.lineSpacing, range: 0...14, suffix: "")
      }

      settingsCard("外观", icon: "paintpalette") {
        LabeledContent("配色") {
          Picker("", selection: $model.appearance.theme) {
            ForEach(LingoSphereThemePreset.allCases) { theme in
              Text(theme.title).tag(theme)
            }
          }
          .labelsHidden()
          .frame(width: 170)
        }
        valueSlider("窗口圆角", value: $model.appearance.cornerRadius, range: 0...24, suffix: "")
        valueSlider("选中项圆角", value: $model.appearance.highlightedCornerRadius, range: 0...18, suffix: "")
        valueSlider("左右留白", value: $model.appearance.horizontalPadding, range: 2...20, suffix: "")
        valueSlider("上下留白", value: $model.appearance.verticalPadding, range: 2...18, suffix: "")
        valueSlider("不透明度", value: $model.appearance.opacity, range: 0.72...1, suffix: "", decimals: 2)
      }
    }
  }

  var translationSection: some View {
    VStack(spacing: 16) {
      settingsCard("候选翻译", icon: "translate") {
        Toggle("启用候选词实时翻译", isOn: $model.translationEnabled)
        Divider()
        LabeledContent("当前目标语言") {
          Picker("", selection: $model.translationLanguage) {
            ForEach(CandidateTranslationLanguage.allCases) { language in
              Text(language.menuTitle).tag(language)
            }
          }
          .labelsHidden()
          .frame(width: 230)
          .disabled(!model.translationEnabled)
        }
        Button("管理与下载翻译语言…") {
          model.manageTranslationLanguages()
        }
        .disabled(!model.translationEnabled)
      }

      settingsCard("响应速度", icon: "timer") {
        LabeledContent("停止输入后开始翻译") {
          Stepper("\(model.translationDelay) 毫秒", value: $model.translationDelay, in: 80...1_000, step: 20)
            .frame(width: 185)
        }
        Divider()
        LabeledContent("译文最长显示") {
          Stepper("\(model.translationLength) 个字符", value: $model.translationLength, in: 12...120, step: 2)
            .frame(width: 175)
        }
        Text("更短的等待时间会更快发起本机翻译，但快速连续输入时可能增加处理次数。")
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
      }
    }
  }

  var dataSection: some View {
    VStack(spacing: 16) {
      settingsCard("维护", icon: "wrench.and.screwdriver") {
        actionRow(
          title: "重新部署",
          detail: "应用配置并重新生成输入方案",
          buttonTitle: "立即部署",
          action: model.redeploy
        )
        Divider()
        actionRow(
          title: "同步用户数据",
          detail: "同步个人词库和用户数据",
          buttonTitle: "开始同步",
          action: model.sync
        )
      }

      settingsCard("文件与备份", icon: "folder") {
        actionRow(title: "用户数据", detail: "词库和输入方案所在位置", buttonTitle: "打开文件夹", action: model.openUserFolder)
        Divider()
        actionRow(title: "设置备份", detail: "每次可视化保存前自动生成", buttonTitle: "查看备份", action: model.openBackupFolder)
        Divider()
        actionRow(title: "运行日志", detail: "排查输入法异常时使用", buttonTitle: "查看日志", action: model.openLogFolder)
      }

      settingsCard("恢复", icon: "arrow.counterclockwise") {
        actionRow(
          title: "载入语界推荐值",
          detail: "不会立即覆盖，仍需点击下方“应用设置”",
          buttonTitle: "载入推荐值",
          action: model.restoreRecommendedValues
        )
      }

      Text("第三方输入方案可能提供额外变量。语界只修改已验证的通用设置，不会删除未知配置。")
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
    }
  }

  var candidatePreview: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("实时预览")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
      Group {
        if model.appearance.layout == .linear {
          HStack(spacing: 18) {
            previewCandidate(index: 1, word: "语界", comment: "language sphere", highlighted: true)
            previewCandidate(index: 2, word: "世界", comment: "world", highlighted: false)
            previewCandidate(index: 3, word: "语言", comment: "language", highlighted: false)
          }
        } else {
          VStack(alignment: .leading, spacing: model.appearance.lineSpacing) {
            previewCandidate(index: 1, word: "语界", comment: "language sphere", highlighted: true)
            previewCandidate(index: 2, word: "世界", comment: "world", highlighted: false)
            previewCandidate(index: 3, word: "语言", comment: "language", highlighted: false)
          }
        }
      }
      .padding(.horizontal, model.appearance.horizontalPadding)
      .padding(.vertical, model.appearance.verticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(previewBackground.opacity(model.appearance.opacity))
      .clipShape(RoundedRectangle(cornerRadius: model.appearance.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: model.appearance.cornerRadius)
          .stroke(previewBorder, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }
  }

  func previewCandidate(index: Int, word: String, comment: String, highlighted: Bool) -> some View {
    HStack(spacing: 9) {
      Text("\(index)")
        .font(.system(size: 11))
        .foregroundStyle(highlighted ? previewHighlightSecondary : Color.secondary)
      Text(word)
        .font(previewFont(size: model.appearance.fontSize))
        .foregroundStyle(previewText)
      Text(comment)
        .font(previewFont(size: model.appearance.commentFontSize))
        .foregroundStyle(highlighted ? previewHighlightSecondary : previewSecondary)
      if model.appearance.layout == .stacked { Spacer(minLength: 0) }
    }
    .padding(.horizontal, 8)
    .frame(minHeight: model.appearance.fontSize + 14)
    .background(
      highlighted ? previewHighlight : Color.clear,
      in: RoundedRectangle(cornerRadius: model.appearance.highlightedCornerRadius)
    )
  }

  func previewFont(size: Double) -> Font {
    if model.appearance.font.configValue.isEmpty {
      return .system(size: size)
    }
    return .custom(model.appearance.font.configValue, size: size)
  }

  var previewBackground: Color {
    switch model.appearance.theme {
    case .brand: Color(red: 0.97, green: 0.98, blue: 1)
    case .system: Color(nsColor: .windowBackgroundColor)
    case .graphite: Color(red: 0.15, green: 0.16, blue: 0.19)
    }
  }

  var previewBorder: Color {
    model.appearance.theme == .graphite ? .white.opacity(0.13) : .black.opacity(0.12)
  }

  var previewHighlight: Color {
    switch model.appearance.theme {
    case .brand: Color(red: 0.82, green: 0.96, blue: 0.90)
    case .system: Color.accentColor.opacity(0.18)
    case .graphite: Color(red: 0.22, green: 0.38, blue: 0.34)
    }
  }

  var previewText: Color {
    model.appearance.theme == .graphite ? .white : .primary
  }

  var previewSecondary: Color {
    model.appearance.theme == .graphite ? .white.opacity(0.68) : .secondary
  }

  var previewHighlightSecondary: Color {
    model.appearance.theme == .graphite
      ? Color(red: 0.72, green: 0.92, blue: 0.83)
      : Color(red: 0.24, green: 0.42, blue: 0.34)
  }

  func settingsCard<Content: View>(
    _ title: String,
    icon: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      Label(title, systemImage: icon)
        .font(.system(size: 14, weight: .semibold))
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
    }
  }

  func valueSlider(
    _ title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    suffix: String,
    decimals: Int = 0
  ) -> some View {
    LabeledContent(title) {
      HStack(spacing: 10) {
        Slider(value: value, in: range)
          .frame(width: 170)
        Text(value.wrappedValue.formatted(.number.precision(.fractionLength(decimals))) + suffix)
          .monospacedDigit()
          .frame(width: 52, alignment: .trailing)
      }
    }
  }

  func actionRow(
    title: String,
    detail: String,
    buttonTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 13, weight: .medium))
        Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
      }
      Spacer()
      Button(buttonTitle, action: action)
    }
  }

  var bottomBar: some View {
    HStack(spacing: 12) {
      if !model.feedback.isEmpty {
        Label(model.feedback, systemImage: model.feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .font(.system(size: 11.5))
          .foregroundStyle(model.feedbackIsError ? Color.red : Color.secondary)
          .lineLimit(1)
      }
      Spacer()
      Button("关闭", action: onClose)
        .keyboardShortcut(.cancelAction)
      Button("应用设置") {
        model.apply()
      }
      .buttonStyle(.borderedProminent)
      .tint(Color(red: 0.22, green: 0.48, blue: 0.91))
      .keyboardShortcut(.defaultAction)
      .disabled(model.isApplying)
    }
    .padding(.horizontal, 20)
    .frame(height: 54)
    .background(.bar)
  }
}
