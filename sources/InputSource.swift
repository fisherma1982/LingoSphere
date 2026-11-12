//
//  InputSource.swift
//  Squirrel
//
//  Created by Leo Liu on 5/10/24.
//

import Foundation
import InputMethodKit

final class SquirrelInstaller {
  enum InputMode: String, CaseIterable {
    static let primary = Self.hans
    case hans = "com.lingosphere.inputmethod.LingoSphere.Hans"
    case hant = "com.lingosphere.inputmethod.LingoSphere.Hant"
  }

  private static let parentInputSourceID = LingoSphereIdentity.bundleIdentifier
  private var inputSources = [String: TISInputSource]()

  init() {
    reloadInputSources()
  }

  private func reloadInputSources() {
    var inputSources = [String: TISInputSource]()
    let sourceList = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
    for inputSource in sourceList {
      let sourceIDRef = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
      guard let sourceID = unsafeBitCast(sourceIDRef, to: CFString?.self) as String? else { continue }
      inputSources[sourceID] = inputSource
    }
    self.inputSources = inputSources
  }

  func enabledModes() -> [InputMode] {
    reloadInputSources()
    guard isEnabled(sourceID: Self.parentInputSourceID) else {
      // An input mode can report its plist default state as enabled even while
      // its mode-enabled parent is disabled. Such a mode is not selectable.
      return []
    }
    var enabledModes = Set<InputMode>()
    for (mode, inputSource) in getInputSource(modes: InputMode.allCases) {
      if let enabled = getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled), enabled {
        enabledModes.insert(mode)
      }
      if enabledModes.count == InputMode.allCases.count {
        break
      }
    }
    return Array(enabledModes)
  }

  func register() {
    let error = TISRegisterInputSource(SquirrelApp.appDir as CFURL)
    reloadInputSources()
    let registered = inputSources[Self.parentInputSourceID] != nil
      && InputMode.allCases.allSatisfy { inputSources[$0.rawValue] != nil }
    if error == noErr && registered {
      print("Registered LingoSphere parent and input modes from \(SquirrelApp.appDir)")
    } else {
      print("Failed to register all LingoSphere input sources (status: \(error))")
    }
  }

  func enable(modes: [InputMode] = []) {
    reloadInputSources()
    guard let parent = inputSources[Self.parentInputSourceID] else {
      print("LingoSphere parent input source is not registered")
      return
    }

    if getBool(for: parent, key: kTISPropertyInputSourceIsEnabled) != true {
      let error = TISEnableInputSource(parent)
      print("Enable \(error == noErr ? "succeeds" : "fails") for LingoSphere parent input source")
      guard error == noErr else { return }
      reloadInputSources()
    }

    // Enabling a mode-enabled parent may automatically enable the mode marked
    // as default in Info.plist. Preserve that result unless specific modes were
    // requested; otherwise enable the Simplified Chinese mode explicitly.
    let enabledAfterParent = enabledModes()
    if modes.isEmpty && !enabledAfterParent.isEmpty {
      print("Enabled LingoSphere method(s): \(enabledAfterParent.map { $0.rawValue })")
      return
    }
    let modesToEnable = modes.isEmpty ? [InputMode.primary] : modes
    reloadInputSources()
    for (mode, inputSource) in getInputSource(modes: modesToEnable) {
      if let enabled = getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled), !enabled {
        let error = TISEnableInputSource(inputSource)
        print("Enable \(error == noErr ? "succeeds" : "fails") for input source: \(mode.rawValue)")
      }
    }
  }

  func select(mode: InputMode? = nil) {
    let modeToSelect = mode ?? .primary
    if !enabledModes().contains(modeToSelect) {
      enable(modes: [modeToSelect])
    }
    guard enabledModes().contains(modeToSelect) else {
      print("Input source is not fully enabled yet: \(modeToSelect.rawValue)")
      return
    }
    reloadInputSources()
    for (mode, inputSource) in getInputSource(modes: [modeToSelect]) {
      if let enabled = getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled),
         let selectable = getBool(for: inputSource, key: kTISPropertyInputSourceIsSelectCapable),
         let selected = getBool(for: inputSource, key: kTISPropertyInputSourceIsSelected),
         enabled && selectable && !selected {
        let error = TISSelectInputSource(inputSource)
        print("Selection \(error == noErr ? "succeeds" : "fails") for input source: \(mode.rawValue)")
      } else {
        print("Failed to select \(mode.rawValue)")
      }
    }
  }

  static func currentInputSourceID() -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let idRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
    return unsafeBitCast(idRef, to: CFString?.self) as String?
  }

  func disable(modes: [InputMode] = []) {
    reloadInputSources()
    let modesToDisable = modes.isEmpty ? InputMode.allCases : modes
    for (mode, inputSource) in getInputSource(modes: modesToDisable) {
      if let enabled = getBool(for: inputSource, key: kTISPropertyInputSourceIsEnabled), enabled {
        let error = TISDisableInputSource(inputSource)
        print("Disable \(error == noErr ? "succeeds" : "fails") for input source: \(mode.rawValue)")
      }
    }

    reloadInputSources()
    let shouldDisableParent = modes.isEmpty || InputMode.allCases.allSatisfy {
      !isEnabled(sourceID: $0.rawValue)
    }
    if shouldDisableParent,
       let parent = inputSources[Self.parentInputSourceID],
       getBool(for: parent, key: kTISPropertyInputSourceIsEnabled) == true {
      let error = TISDisableInputSource(parent)
      print("Disable \(error == noErr ? "succeeds" : "fails") for LingoSphere parent input source")
    }
  }

  private func getInputSource(modes: [InputMode]) -> [InputMode: TISInputSource] {
    var matchingSources = [InputMode: TISInputSource]()
    for mode in modes {
      if let inputSource = inputSources[mode.rawValue] {
        matchingSources[mode] = inputSource
      }
    }
    return matchingSources
  }

  private func getBool(for inputSource: TISInputSource, key: CFString!) -> Bool? {
    let enabledRef = TISGetInputSourceProperty(inputSource, key)
    guard let enabled = unsafeBitCast(enabledRef, to: CFBoolean?.self) else { return nil }
    return CFBooleanGetValue(enabled)
  }

  private func isEnabled(sourceID: String) -> Bool {
    guard let source = inputSources[sourceID] else { return false }
    return getBool(for: source, key: kTISPropertyInputSourceIsEnabled) == true
  }
}
