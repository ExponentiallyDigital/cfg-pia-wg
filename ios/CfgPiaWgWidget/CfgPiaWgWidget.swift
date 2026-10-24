// CfgPiaWgWidget.swift - the iOS home screen widgets (ID-438), the counterparts of Android's
// TunnelsWidgetProvider.kt and CompactWidgetProvider.kt, and like them they decide nothing. Every
// string and state is read from what lib/widget_bridge.dart wrote through home_widget, into the app
// group the app and this extension share. test/unit/widget_ios_test.dart holds the keys, the kinds,
// the app group and the colours here to the Dart side and to Android's.
//
// Redrawn only when the app writes (home_widget asks WidgetCenter to reload), never on a clock: the
// footer is a clock time, not an age, so it stays true however old the reading gets (ARCHITECTURE 10.4).

import SwiftUI
import WidgetKit

/// lib/widget_bridge.dart's kWidgetAppGroup, and both targets' entitlements.
let appGroup = "group.com.exponentiallydigital.cfgpiawg"

/// The keys lib/widget_bridge.dart writes, as WidgetKeys.kt reads them on Android.
enum WidgetKeys {
  static let badge = "badge"
  static let downCount = "down_count"
  static let tunnelCount = "tunnel_count"
  static let t1Region = "tunnel1_region"
  static let t1Detail = "tunnel1_detail"
  static let t1Guard = "tunnel1_guard"
  static let t1State = "tunnel1_state"
  static let t2Region = "tunnel2_region"
  static let t2Detail = "tunnel2_detail"
  static let t2Guard = "tunnel2_guard"
  static let t2State = "tunnel2_state"
  static let overflowText = "overflow_text"
  static let lastCheckedText = "last_checked_text"
  static let canRefresh = "can_refresh"
  static let compactBadgeText = "compact_badge_text"
  static let compactDetailText = "compact_detail_text"
}

/// Android's widget palette, android/app/src/main/res/values/colors.xml, colour for colour.
enum Palette {
  static let cardBg = Color(hex: 0x1A1D23) // widget_card_bg
  static let textPrimary = Color(hex: 0xE8EAF0) // widget_text_primary
  static let textSecondary = Color(hex: 0xA0AABA) // widget_text_secondary
  static let dimDot = Color(hex: 0x5B6475) // widget_dim_dot
  static let teal = Color(hex: 0x00D4AA) // widget_teal
  static let tealBg = Color(hex: 0x0F3D2E) // widget_teal_bg
  static let amber = Color(hex: 0xEF9F27) // widget_amber
  static let amberBg = Color(hex: 0x2A1F0E) // widget_amber_bg
  static let grey = Color(hex: 0xC3CAD6) // widget_grey
  static let greyBorder = Color(hex: 0x8892A4) // widget_grey_border
  static let greyBg = Color(hex: 0x1F242D) // widget_grey_bg
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}

/// One tunnel row, as Android's populateRow draws it.
struct TunnelRow {
  let region: String
  let detail: String
  let guardLine: String
  let state: String
}

/// Everything the widgets show, read once from the app group. Missing values read as Android's
/// defaults: "unchecked", no rows, empty text.
struct WidgetData {
  let badge: String
  let downCount: Int
  let rows: [TunnelRow]
  let overflow: String
  let lastChecked: String
  let canRefresh: Bool
  let compactBadge: String
  let compactDetail: String

  static func read(_ d: UserDefaults?) -> WidgetData {
    func text(_ key: String) -> String { d?.string(forKey: key) ?? "" }
    let count = d?.integer(forKey: WidgetKeys.tunnelCount) ?? 0
    var rows: [TunnelRow] = []
    if count >= 1 {
      rows.append(
        TunnelRow(
          region: text(WidgetKeys.t1Region), detail: text(WidgetKeys.t1Detail),
          guardLine: text(WidgetKeys.t1Guard), state: d?.string(forKey: WidgetKeys.t1State) ?? "unchecked"))
    }
    if count >= 2 {
      rows.append(
        TunnelRow(
          region: text(WidgetKeys.t2Region), detail: text(WidgetKeys.t2Detail),
          guardLine: text(WidgetKeys.t2Guard), state: d?.string(forKey: WidgetKeys.t2State) ?? "unchecked"))
    }
    let down = d?.object(forKey: WidgetKeys.downCount) as? Int ?? 1
    return WidgetData(
      badge: d?.string(forKey: WidgetKeys.badge) ?? "unchecked", downCount: down, rows: rows,
      overflow: text(WidgetKeys.overflowText), lastChecked: text(WidgetKeys.lastCheckedText),
      canRefresh: d?.bool(forKey: WidgetKeys.canRefresh) ?? false,
      compactBadge: text(WidgetKeys.compactBadgeText), compactDetail: text(WidgetKeys.compactDetailText))
  }
}

struct DataEntry: TimelineEntry {
  let date: Date
  let data: WidgetData
}

struct Provider: TimelineProvider {
  private func current() -> DataEntry {
    DataEntry(date: Date(), data: WidgetData.read(UserDefaults(suiteName: appGroup)))
  }

  func placeholder(in context: Context) -> DataEntry { current() }

  func getSnapshot(in context: Context, completion: @escaping (DataEntry) -> Void) {
    completion(current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DataEntry>) -> Void) {
    completion(Timeline(entries: [current()], policy: .never))
  }
}

/// The badge pill: exactly one, as Dart decided WidgetStatus.badge is.
struct BadgeView: View {
  let badge: String
  let downCount: Int

  var body: some View {
    let (icon, text, colour, fill, border): (String, String, Color, Color, Color?) =
      switch badge {
      case "protected": ("checkmark.shield.fill", "Protected", Palette.teal, Palette.tealBg, nil)
      case "down":
        (
          "exclamationmark.triangle.fill", downCount == 1 ? "1 tunnel down" : "\(downCount) tunnels down",
          Palette.amber, Palette.amberBg, Palette.amber
        )
      default: ("clock", "Not checked", Palette.grey, Palette.greyBg, Palette.greyBorder)
      }
    HStack(spacing: 6) {
      Image(systemName: icon).font(.system(size: 11))
      Text(text).font(.system(size: 11, weight: .bold))
    }
    .foregroundStyle(colour)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill(fill))
    .overlay { if let border { Capsule().stroke(border, lineWidth: 1) } }
  }
}

/// A row's dot: filled teal when answering, an amber ring when down, dim when not checked.
struct DotView: View {
  let state: String

  var body: some View {
    Group {
      switch state {
      case "answering": Circle().fill(Palette.teal)
      case "down": Circle().stroke(Palette.amber, lineWidth: 2)
      default: Circle().fill(Palette.dimDot)
      }
    }
    .frame(width: 10, height: 10)
  }
}

/// The 4x2 widget's counterpart: each tunnel's state, where it exits, and the guard.
struct TunnelsView: View {
  let data: WidgetData

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("cfg-pia-wg").font(.system(size: 13)).foregroundStyle(Palette.textPrimary)
        Spacer()
        BadgeView(badge: data.badge, downCount: data.downCount)
      }
      ForEach(Array(data.rows.enumerated()), id: \.offset) { _, row in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          DotView(state: row.state)
          VStack(alignment: .leading, spacing: 1) {
            Text(row.region).font(.system(size: 13)).foregroundStyle(Palette.textPrimary)
            Text(row.detail).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            if !row.guardLine.isEmpty {
              Text(row.guardLine).font(.system(size: 11)).foregroundStyle(Palette.teal)
            }
          }
          .lineLimit(1)
        }
      }
      if !data.overflow.isEmpty {
        Text(data.overflow).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
      }
      Spacer(minLength: 0)
      HStack {
        Text(data.lastChecked).font(.system(size: 11)).foregroundStyle(Palette.textSecondary).lineLimit(1)
        Spacer()
        // A tap anywhere opens the app, which reads the router as it opens (ID-438); until the
        // widget refreshes itself (ID-439), the icon is Android's plain one.
        Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
      }
    }
    .containerBackground(for: .widget) { Palette.cardBg }
  }
}

/// The 2x1 widget's counterpart: the badge and one line.
struct CompactView: View {
  let data: WidgetData

  var body: some View {
    let (icon, colour): (String, Color) =
      switch data.badge {
      case "protected": ("checkmark.shield.fill", Palette.teal)
      case "down": ("exclamationmark.triangle.fill", Palette.amber)
      default: ("clock", Palette.grey)
      }
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: icon).font(.system(size: 24)).foregroundStyle(colour)
      Spacer(minLength: 0)
      Text(data.compactBadge).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
      Text(data.compactDetail).font(.system(size: 11)).foregroundStyle(Palette.textSecondary).lineLimit(3)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .containerBackground(for: .widget) { Palette.cardBg }
  }
}

struct TunnelsWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CfgPiaWgTunnelsWidget", provider: Provider()) { entry in
      TunnelsView(data: entry.data)
    }
    .configurationDisplayName("Tunnels")
    .description("Each tunnel's state, where it exits, and the guard")
    .supportedFamilies([.systemMedium])
  }
}

struct CompactWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CfgPiaWgCompactWidget", provider: Provider()) { entry in
      CompactView(data: entry.data)
    }
    .configurationDisplayName("Summary")
    .description("A one-line summary of the tunnels")
    .supportedFamilies([.systemSmall])
  }
}

@main
struct CfgPiaWgWidgets: WidgetBundle {
  var body: some Widget {
    TunnelsWidget()
    CompactWidget()
  }
}
