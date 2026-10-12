package com.exponentiallydigital.pia_wireguard_cfga.widget

/**
 * The SharedPreferences keys `home_widget` reads on the Kotlin side - written from Dart by
 * lib/widget_bridge.dart, whose `kWidgetKey*` constants must read exactly these strings back.
 * Kept in one place so a typo on either side fails loudly rather than drawing a blank widget
 * (ID-376).
 */
object WidgetKeys {
    const val BADGE = "badge" // "protected" | "down" | "unchecked"
    const val DOWN_COUNT = "down_count" // int, for "N tunnel(s) down"
    const val TUNNEL_COUNT = "tunnel_count" // int, how many rows are populated (0..5)

    const val T1_REGION = "tunnel1_region"
    const val T1_DETAIL = "tunnel1_detail"
    const val T1_GUARD = "tunnel1_guard" // empty when nobody is held offline by this tunnel
    const val T1_STATE = "tunnel1_state" // "answering" | "down" | "unchecked"

    const val T2_REGION = "tunnel2_region"
    const val T2_DETAIL = "tunnel2_detail"
    const val T2_GUARD = "tunnel2_guard"
    const val T2_STATE = "tunnel2_state"

    const val OVERFLOW_TEXT = "overflow_text" // e.g. "+1 more tunnel"; empty when there is none
    const val LAST_CHECKED_TEXT = "last_checked_text"
    const val CAN_REFRESH = "can_refresh" // bool: a key is installed, so the button can act

    const val COMPACT_BADGE_TEXT = "compact_badge_text"
    const val COMPACT_DETAIL_TEXT = "compact_detail_text"
}
