// Demo stage for the LingoSphere intro video: a clean 3:4 window that types
// into a real text view through the active input method, and shows captions
// and key hints in sync. Screen recording is done by the caller.
//
// usage: stage <log-file> <rect-file>
import AppKit
import Carbon

let k: CGFloat = 2.0 / 3.0
let design = NSSize(width: 660, height: 880)
let stageSize = NSSize(width: 440, height: 587)
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
  NSRect(x: x * k, y: y * k, width: w * k, height: h * k)
}
let green = NSColor(srgbRed: 0.20, green: 0.53, blue: 0.34, alpha: 1)
let paleGreen = NSColor(srgbRed: 0.90, green: 0.96, blue: 0.92, alpha: 1)
let ink = NSColor(srgbRed: 0.10, green: 0.13, blue: 0.12, alpha: 1)
let backgroundColor = NSColor(srgbRed: 0.965, green: 0.975, blue: 0.965, alpha: 1)

let logPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/dev/null"
let rectPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/dev/null"

func log(_ message: String) {
  let line = message + "\n"
  if let handle = FileHandle(forWritingAtPath: logPath) {
    handle.seekToEndOfFile()
    handle.write(line.data(using: .utf8)!)
    handle.closeFile()
  } else {
    try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
  }
}

final class StageWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
           alignment: NSTextAlignment = .left) -> NSTextField {
  let field = NSTextField(labelWithString: text)
  field.font = NSFont.systemFont(ofSize: size * k, weight: weight)
  field.textColor = color
  field.alignment = alignment
  field.maximumNumberOfLines = 2
  field.lineBreakMode = .byWordWrapping
  return field
}

/// A key cap that lights up while the key is "pressed".
final class KeyCap: NSView {
  private let title: NSTextField
  var lit = false { didSet { refresh() } }

  init(_ text: String, width: CGFloat) {
    title = label(text, size: 24, weight: .semibold, color: ink, alignment: .center)
    super.init(frame: R(0, 0, width, 64))
    wantsLayer = true
    layer?.cornerRadius = 14 * k
    layer?.borderWidth = 1.5
    title.frame = R(0, 16, width, 32)
    addSubview(title)
    refresh()
  }

  required init?(coder: NSCoder) { fatalError() }

  private func refresh() {
    layer?.backgroundColor = (lit ? green : NSColor.white).cgColor
    layer?.borderColor = (lit ? green : NSColor(white: 0.80, alpha: 1)).cgColor
    title.textColor = lit ? .white : ink
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = lit ? 0 : 0.10
    layer?.shadowOffset = CGSize(width: 0, height: -2)
    layer?.shadowRadius = 3
    layer?.setAffineTransform(lit ? CGAffineTransform(translationX: 0, y: -3) : .identity)
  }
}

@MainActor
final class Stage: NSObject, NSApplicationDelegate {
  var window: StageWindow!
  let root = FlippedView()
  let captionTitle = label("", size: 44, weight: .bold, color: ink)
  let captionDetail = label("", size: 23, weight: .regular, color: NSColor(white: 0.36, alpha: 1))
  let stepBadge = label("", size: 17, weight: .semibold, color: green)
  let editorCard = FlippedView()
  var textView: NSTextView!
  let keyRow = FlippedView()
  let card = FlippedView()
  let cardTitle = label("", size: 60, weight: .bold, color: .white, alignment: .center)
  let cardDetail = label("", size: 27, weight: .medium, color: NSColor(white: 1, alpha: 0.92), alignment: .center)
  let cardFoot = label("", size: 19, weight: .regular, color: NSColor(white: 1, alpha: 0.80), alignment: .center)

  func applicationDidFinishLaunching(_ notification: Notification) {
    let visible = NSScreen.main!.visibleFrame
    let full = NSScreen.main!.frame
    let origin = NSPoint(x: visible.midX - stageSize.width / 2,
                         y: visible.maxY - stageSize.height - 8)
    window = StageWindow(contentRect: NSRect(origin: origin, size: stageSize),
                         styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = backgroundColor
    window.hasShadow = false
    window.level = .floating
    root.frame = NSRect(origin: .zero, size: stageSize)
    window.contentView = root

    // screencapture -R uses a top-left origin in points.
    let top = full.maxY - (origin.y + stageSize.height)
    try? "\(Int(origin.x)),\(Int(top)),\(Int(stageSize.width)),\(Int(stageSize.height))"
      .write(toFile: rectPath, atomically: true, encoding: .utf8)

    let brand = label("语界 LingoSphere", size: 17, weight: .semibold, color: green)
    brand.frame = R(44, 52, 300, 24)
    root.addSubview(brand)
    stepBadge.alignment = .right
    stepBadge.frame = R(416, 52, 200, 24)
    root.addSubview(stepBadge)

    captionTitle.frame = R(44, 112, 572, 60)
    root.addSubview(captionTitle)
    captionDetail.frame = R(44, 180, 572, 34)
    root.addSubview(captionDetail)

    editorCard.frame = R(40, 256, 580, 104)
    editorCard.wantsLayer = true
    editorCard.layer?.backgroundColor = NSColor.white.cgColor
    editorCard.layer?.cornerRadius = 18 * k
    editorCard.layer?.borderWidth = 1
    editorCard.layer?.borderColor = NSColor(white: 0.86, alpha: 1).cgColor
    root.addSubview(editorCard)

    textView = NSTextView(frame: R(22, 24, 536, 60))
    textView.font = NSFont.systemFont(ofSize: 40 * k, weight: .medium)
    textView.textColor = ink
    textView.insertionPointColor = green
    textView.drawsBackground = false
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.isAutomaticTextCompletionEnabled = false
    textView.textContainerInset = .zero
    textView.textContainer?.maximumNumberOfLines = 1
    textView.markedTextAttributes = [
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .underlineColor: green,
      .foregroundColor: ink
    ]
    editorCard.addSubview(textView)

    keyRow.frame = R(0, 690, design.width, 72)
    root.addSubview(keyRow)

    card.frame = root.bounds
    card.wantsLayer = true
    card.layer?.backgroundColor = green.cgColor
    cardTitle.frame = R(30, 300, 600, 80)
    cardDetail.frame = R(30, 400, 600, 40)
    cardFoot.frame = R(30, 790, 600, 30)
    card.addSubview(cardTitle)
    card.addSubview(cardDetail)
    card.addSubview(cardFoot)
    root.addSubview(card)

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(textView)
    selectInputSource()

    Task { @MainActor in
      await self.pause(0.6)
      NSApp.activate(ignoringOtherApps: true)
      self.window.makeKeyAndOrderFront(nil)
      self.window.makeFirstResponder(self.textView)
      self.selectInputSource()
      let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
      let currentID = TISGetInputSourceProperty(current, kTISPropertyInputSourceID)
        .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?"
      log("active=\(NSApp.isActive) key=\(self.window.isKeyWindow) source=\(currentID)")
      await self.run()
      NSApp.terminate(nil)
    }
  }

  func selectInputSource() {
    let wanted = "com.lingosphere.inputmethod.LingoSphere.Hans"
    let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    for source in list {
      guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
      let identifier = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
      if identifier == wanted {
        let status = TISSelectInputSource(source)
        log("select input source \(identifier): \(status)")
        return
      }
    }
    log("input source not found: \(wanted)")
  }

  // MARK: timeline helpers

  var t0 = Date()
  let env = ProcessInfo.processInfo.environment

  func pause(_ seconds: Double) async {
    try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
  }

  /// Waits until `t` seconds after the take's start mark, so that every
  /// action lands on the beat grid regardless of how long earlier steps took.
  func at(_ t: Double) async {
    let delay = t0.addingTimeInterval(t).timeIntervalSinceNow
    if delay > 0 { await pause(delay) }
  }

  func ev(_ name: String) {
    log(String(format: "EV %.3f %@", Date().timeIntervalSince(t0), name))
  }

  static let keyCodes: [Character: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
    "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
    "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35,
    "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, " ": 49
  ]

  /// Sends a key with a real CGEvent behind it; the input method framework
  /// needs that in order to forward the key to the input method.
  func pressCode(_ code: UInt16, option: Bool = false) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
      guard let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
      cgEvent.flags = option ? [.maskAlternate] : []
      if let event = NSEvent(cgEvent: cgEvent) {
        NSApp.postEvent(event, atStart: false)
      }
    }
  }

  func press(_ char: Character, option: Bool = false) {
    guard let code = Self.keyCodes[char] else { return }
    pressCode(code, option: option)
  }

  func type(_ text: String, from start: Double, interval: Double) async {
    for (index, char) in text.enumerated() {
      await at(start + Double(index) * interval)
      press(char)
      ev("key")
    }
  }

  func caption(step: String, _ title: String, _ detail: String) {
    stepBadge.stringValue = step
    captionTitle.stringValue = title
    captionDetail.stringValue = detail
    for view in [captionTitle, captionDetail] {
      view.alphaValue = 0
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.22
        view.animator().alphaValue = 1
      }
    }
  }

  @discardableResult
  func showKeys(_ names: [String]) -> [KeyCap] {
    keyRow.subviews.forEach { $0.removeFromSuperview() }
    var caps = [KeyCap]()
    var plusLabels = [NSTextField]()
    var total: CGFloat = 0
    for (index, name) in names.enumerated() {
      let width: CGFloat = name.count > 2 ? 168 : 76
      caps.append(KeyCap(name, width: width))
      total += width
      if index > 0 {
        plusLabels.append(label("+", size: 26, weight: .medium, color: NSColor(white: 0.5, alpha: 1), alignment: .center))
        total += 44
      }
    }
    var x = (design.width - total) / 2
    for (index, cap) in caps.enumerated() {
      if index > 0 {
        let plus = plusLabels[index - 1]
        plus.frame = R(x, 16, 44, 32)
        keyRow.addSubview(plus)
        x += 44
      }
      cap.frame.origin = NSPoint(x: x * k, y: 4 * k)
      keyRow.addSubview(cap)
      x += cap.frame.width / k
    }
    return caps
  }

  func showCard(_ title: String, _ detail: String, foot: String = "") {
    cardTitle.stringValue = title
    cardDetail.stringValue = detail
    cardFoot.stringValue = foot
    card.isHidden = false
  }

  /// The language pill shown in place of the step badge.
  func showChip(_ text: String) {
    let chip = FlippedView(frame: R(396, 40, 220, 46))
    chip.wantsLayer = true
    chip.layer?.backgroundColor = green.cgColor
    chip.layer?.cornerRadius = 23 * k
    let title = label(text, size: 22, weight: .bold, color: .white, alignment: .center)
    title.frame = R(0, 9, 220, 30)
    chip.addSubview(title)
    root.addSubview(chip, positioned: .below, relativeTo: card)
    stepBadge.isHidden = true
  }

  /// Marks the take's start: the pre-roll card disappears and the clock starts.
  func startTake() {
    card.isHidden = true
    t0 = Date()
    log("T0")
  }

  // MARK: takes

  func run() async {
    switch env["STAGE_SEGMENT"] ?? "en" {
    case "warm": await runWarm()
    case "lang": await runLanguage()
    default: await runEnglish()
    }
  }

  /// Types words once, off camera, so their translations are cached.
  func runWarm() async {
    card.isHidden = true
    for word in (env["STAGE_WORD"] ?? "xiexie").split(separator: ",") {
      t0 = Date()
      await type(String(word), from: 0.2, interval: 0.08)
      await pause(3.0)
      pressCode(53)  // escape: discard the composition
      await pause(0.5)
      textView.string = ""
    }
    log("done")
  }

  func runEnglish() async {
    showCard("语界输入法", "边打字，边翻译", foot: "LingoSphere · macOS")
    caption(step: "", "打字，译文同步出现", "候选词旁边就是翻译")
    showKeys([])
    await pause(3.4)  // pre-roll: covers the recorder's start-up and the title

    // 1. the basics, briefly
    startTake()
    await type("nihao", from: 0.30, interval: 0.07)
    await at(1.75)
    press(" ")
    ev("commit")
    await at(2.30)
    pressCode(124)  // right arrow: ends the "previous word" for auto spacing
    log("scene1: \(textView.string)")

    // 2. Option + Space
    await at(2.50)
    textView.string = ""
    caption(step: "独特功能 1", "⌥ + 空格", "直接上屏译文，不用切换输入法")
    var caps = showKeys(["⌥ Option", "空格"])
    ev("scene")
    await type("pingguo", from: 2.90, interval: 0.07)
    await at(4.50)
    caps.forEach { $0.lit = true }
    await at(4.75)
    press(" ", option: true)
    ev("commit")
    await at(5.05)
    caps.forEach { $0.lit = false }
    await at(5.80)
    pressCode(124)
    log("scene2: \(textView.string)")

    // 3. several translations
    await at(6.00)
    textView.string = ""
    caption(step: "独特功能 2", "一词多译，随你挑", "⌥ + 数字 展开译法，再按数字选择")
    caps = showKeys(["⌥ Option", "1"])
    ev("scene")
    await type("xiao", from: 6.40, interval: 0.08)
    await at(7.50)
    caps.forEach { $0.lit = true }
    await at(7.75)
    press("1", option: true)
    ev("open")
    await at(8.05)
    caps.forEach { $0.lit = false }
    await at(8.75)
    caps = showKeys(["2"])
    await at(9.00)
    caps.forEach { $0.lit = true }
    await at(9.25)
    press("2")
    ev("commit")
    await at(9.55)
    caps.forEach { $0.lit = false }
    await at(10.50)
    ev("end")
    log("scene3: \(textView.string)")
    await pause(0.7)
    log("done")
  }

  func runLanguage() async {
    let word = env["STAGE_WORD"] ?? "xiexie"
    showCard("", "")
    caption(step: "", "7 种语言，随手切换", "同一个词，换个语言再上屏")
    showChip(env["STAGE_CHIP"] ?? "")
    let caps = showKeys(["⌥ Option", "空格"])
    await pause(3.0)

    startTake()
    ev("scene")
    await type(word, from: 0.25, interval: 0.07)
    await at(1.25)
    caps.forEach { $0.lit = true }
    await at(1.50)
    press(" ", option: true)
    ev("commit")
    await at(1.80)
    caps.forEach { $0.lit = false }
    await at(2.50)
    ev("end")
    log("lang: \(textView.string)")
    if env["STAGE_END"] != nil {
      showCard("7 种语言", "英 · 日 · 韩 · 德 · 法 · 西 · 葡", foot: "本机翻译 · 无需联网 · 语界 LingoSphere")
      await at(5.20)
    } else {
      await pause(0.7)
    }
    log("done")
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let stage = MainActor.assumeIsolated { Stage() }
app.delegate = stage
app.run()
