// widgets/paywall.dart - the one place the app asks to be paid.
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see https://www.gnu.org/licenses/.
//
// Copyright (C) 2026 Andrew Newbury.
//
// CONTEXTUAL, never interstitial. This opens when someone taps a control that would CREATE or
// CHANGE something, and at no other time - not on launch, not on entering a screen. An on-entry
// prompt fires at exactly the people the read-only view exists to welcome, and that is the
// placement that earns one-star reviews from people who were only looking.
//
// A page rather than a dialog. The content grows - it always does - and a long form in an unbounded
// card is the bug this project shipped four times, with SAVE below a fold that would not scroll.
// A page has a bounded viewport by construction. See `.claude/plans/plan_revenuecat-implementation.md`.

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../session_controller.dart';
import 'app_scaffold.dart';

/// What the store is offering, and how to buy it.
///
/// The seam RevenueCat fills. Null until the SDK lands, and null is a legitimate runtime state -
/// the store can be unreachable - so the page has to read correctly without it.
class PaywallOffer {
  const PaywallOffer({required this.price, required this.purchase, required this.restore});

  /// The store's OWN localised string, `package.storeProduct.priceString`. Never a hardcoded
  /// number: the wrong currency destroys trust instantly and silently.
  final String price;

  /// Both return true when the entitlement is held afterwards.
  final Future<bool> Function() purchase, restore;
}

/// The current offer, or null when purchasing is not available.
///
/// Replace the source when RevenueCat lands; do not reach for the SDK from the widget.
abstract class Paywall {
  static PaywallOffer? offer;

  /// Opens the paywall for [pitch] - one sentence about the action the user just tried to take.
  /// Returns true when they came back entitled.
  static Future<bool> show(BuildContext context, SessionController c, {required String pitch}) async {
    final unlocked = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => _PaywallScreen(pitch: pitch, controller: c)),
        ) ??
        false;
    return unlocked;
  }
}

/// The sentence at the top of the paywall, one per gated action.
///
/// Says what THIS action would have done, because a feature grid converts worse than a sentence
/// about the button just pressed. The watchdog one carries the most weight: a locked user opening
/// WATCHDOG sees a screen with nothing on it, so unlike the other two it cannot demonstrate itself.
abstract class Pitch {
  static const create = 'Creating a VPN writes a fresh PIA configuration straight into a router slot, '
      'picking the fastest server in your region. No computer, no scripts.';
  static const enable = 'Enabling brings the tunnel up and then checks that traffic is really flowing '
      'through it, rather than assuming.';
  static const edit = "Editing writes the slot's settings back to your router.";
  static const watchdog = 'A watchdog is the whole point of this app. It lives on your router and checks '
      'this tunnel every few minutes; when PIA rotates the key and the tunnel dies, it fetches a new one, '
      'rebuilds the connection and emails you to say it did. You find out from the email, not from a '
      'week of wondering why the VPN was off.';
  static const watchdogEnable = "Enabling puts the watchdog's schedule back on the router.";
  static const assign = 'Assigning sends this device out through a VPN while everything else on your '
      'network carries on as it was. One tap per device, no slot numbers to work out.';
}

class _PaywallScreen extends StatefulWidget {
  const _PaywallScreen({required this.pitch, required this.controller});
  final String pitch;
  final SessionController controller;

  @override
  State<_PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<_PaywallScreen> {
  bool _busy = false;

  SessionController get _c => widget.controller;

  Future<void> _run(Future<bool> Function() action, String failure) async {
    setState(() => _busy = true);
    var ok = false;
    String? error;
    try {
      ok = await action();
    } catch (e) {
      error = e.toString().replaceAll('Exception: ', '');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _c.setUnlocked(true);
      Navigator.of(context).pop(true);
      return;
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$failure $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = Paywall.offer;
    return AppScaffold(
      showClose: false, // CLOSE is below, and has to be the obvious way out
      maxContentWidth: kFormMaxWidth,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        Text(widget.pitch, style: const TextStyle(color: kText, fontSize: 15, height: 1.45)),
        const SizedBox(height: 24),

        // The three claims a technical buyer scans for, and no more. The rest is below the fold on
        // purpose: whoever is still reading at that point wants detail, and whoever is not has
        // already decided.
        for (final line in const [
          'One payment. No subscription, ever.',
          'Works offline once bought, and keeps working.',
          'Nothing is tracked. No analytics, no advertising id.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check, size: 15, color: kHighlight),
              const SizedBox(width: 8),
              Expanded(child: Text(line, style: const TextStyle(color: kText, fontSize: 13))),
            ]),
          ),
        const SizedBox(height: 20),

        if (_busy)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: kHighlight)))
        else ...[
          ElevatedButton(
            key: const Key('paywall_buy'),
            onPressed: offer == null ? null : () => _run(offer.purchase, 'Purchase failed:'),
            // The store's own string, so the currency is always the buyer's.
            child: Text(offer == null ? 'Not available right now' : 'UNLOCK - ${offer.price}'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('paywall_restore'),
            onPressed: offer == null ? null : () => _run(offer.restore, 'Restore failed:'),
            child: const Text('Already purchased? Restore', style: TextStyle(color: kHighlight, fontSize: 13)),
          ),
          TextButton(
            key: const Key('paywall_close'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('NOT NOW', style: TextStyle(color: kMuted)),
          ),
        ],

        const SizedBox(height: 28),
        const Divider(color: kBorder),
        const SizedBox(height: 12),
        const Text('What stays free', style: TextStyle(color: kHighlight, fontSize: 12, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text(
          'Generating standalone PIA WireGuard configurations is free for everyone, forever, with or '
          'without a router.\n\n'
          'You can always look at your router - slots, devices, status and logs - and you can always '
          'remove things, including taking this app back off the router entirely.\n\n'
          'The source is on GitHub and the build instructions are good enough to follow. What you are '
          'paying for is not having to.',
          style: TextStyle(color: kMuted, fontSize: 12, height: 1.5),
        ),
      ]),
    );
  }
}
