//
//  LingoSphereIdentity.swift
//  Squirrel
//

import Foundation

enum LingoSphereIdentity {
  static let chineseName = "语界"
  static let englishName = "LingoSphere"
  static let bundleIdentifier = "com.lingosphere.inputmethod.LingoSphere"
  static let inputSourceIdentifierPrefix = bundleIdentifier
  static let simplifiedInputSourceIdentifier = "\(bundleIdentifier).Hans"
  static let traditionalInputSourceIdentifier = "\(bundleIdentifier).Hant"
  static let installedAppPath = "/Library/Input Methods/LingoSphere.app"

  static let reloadNotification = Notification.Name("LingoSphereReloadNotification")
  static let syncNotification = Notification.Name("LingoSphereSyncNotification")
  static let toggleASCIINotification = Notification.Name("LingoSphereToggleASCIIModeNotification")
  static let getASCIINotification = Notification.Name("LingoSphereGetASCIIModeNotification")
  static let setASCIIModeNotification = Notification.Name("LingoSphereSetASCIIModeNotification")
  static let requestASCIIModeReportNotification = Notification.Name("LingoSphereRequestASCIIModeReportNotification")
  static let asciiModeResponseNotification = Notification.Name("LingoSphereASCIIModeResponse")

  private static let migrationDefaultsKey = "LingoSphere.didMigrateSquirrelPreferences"
  private static let legacyBundleIdentifier = "im.rime.inputmethod.Squirrel"
  private static let migratableDefaultsKeys = [
    "AppleCandidateTranslation.selectedLanguage",
    "AppleCandidateTranslation.enabled",
    "AppleCandidateTranslation.didCompleteLanguageSetup"
  ]

  /// The first independent-brand build keeps the user's previously selected
  /// translation language even though macOS now gives the app a new defaults domain.
  static func migrateLegacyPreferencesIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: migrationDefaultsKey) else { return }
    if let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier) {
      for key in migratableDefaultsKeys where defaults.object(forKey: key) == nil {
        if let value = legacyDefaults.object(forKey: key) {
          defaults.set(value, forKey: key)
        }
      }
    }
    defaults.set(true, forKey: migrationDefaultsKey)
  }
}
