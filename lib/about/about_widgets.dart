import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openExternal(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Rounded card with an icon tile + title header (Dara Hub section style).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.icon, required this.title, this.subtitle, required this.child});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A Material (not a decorated Container) so ripples of the rows / buttons inside the card are
    // painted on the card itself instead of behind its opaque background.
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, size: 22, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        child,
          ]),
        ),
      ),
    );
  }
}

/// Small pill label (Dara Hub `_Label`).
class AboutChip extends StatelessWidget {
  const AboutChip(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(100)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: cs.onSecondaryContainer), const SizedBox(width: 5)],
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSecondaryContainer)),
      ]),
    );
  }
}

class AboutItem {
  const AboutItem({required this.icon, required this.title, required this.subtitle, this.onTap, this.link = false, this.chevron = true});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  /// Colors the subtitle like a hyperlink.
  final bool link;
  final bool chevron;
}

/// Connected rows: big outer corners, 4 dp gaps between rows (Dara Hub GroupedList).
class AboutGroup extends StatelessWidget {
  const AboutGroup({super.key, required this.items});
  final List<AboutItem> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final linkColor = dark ? const Color(0xFF8AB4F8) : const Color(0xFF1A73E8);
    const big = Radius.circular(20), small = Radius.circular(4);
    final last = items.length - 1;
    return Column(children: [
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
          child: Material(
            color: cs.surfaceContainer,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: i == 0 ? big : small,
                topRight: i == 0 ? big : small,
                bottomLeft: i == last ? big : small,
                bottomRight: i == last ? big : small,
              ),
            ),
            child: InkWell(
              onTap: items[i].onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72, minWidth: double.infinity),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
                      child: Icon(items[i].icon, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(items[i].subtitle,
                            style: TextStyle(fontSize: 12, color: items[i].link ? linkColor : cs.onSurfaceVariant)),
                      ]),
                    ),
                    if (items[i].chevron && items[i].onTap != null) Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// GitHub mark, tinted like any other icon (Material Icons has none).
class GithubIcon extends StatelessWidget {
  const GithubIcon({super.key, this.size = 26, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      ImageIcon(const AssetImage('assets/github.png'), size: size, color: color);
}

class QuickAction {
  const QuickAction({required this.icon, required this.label, required this.onTap});
  final Widget icon;
  final String label;
  final VoidCallback onTap;
}

/// One row of equal tiles: big outer corners on the first / last tile, small inner corners and a
/// thin gap between tiles. Icon above, label below.
class AboutQuickActions extends StatelessWidget {
  const AboutQuickActions({super.key, required this.items});
  final List<QuickAction> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const big = Radius.circular(28), small = Radius.circular(4);
    final last = items.length - 1;
    // Every tile is as tall as the tallest one, whatever icon it holds.
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < items.length; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
            child: Material(
              color: cs.surfaceContainer,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topLeft: i == 0 ? big : small,
                  bottomLeft: i == 0 ? big : small,
                  topRight: i == last ? big : small,
                  bottomRight: i == last ? big : small,
                ),
              ),
              child: InkWell(
                onTap: items[i].onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    // Fixed 28 dp slot: the GitHub mark and the Material icons line up and weigh the same.
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconTheme(
                        data: IconThemeData(size: 28, color: cs.onSurface),
                        child: Center(child: items[i].icon),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: cs.onSurface)),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]),
    );
  }
}

/// Back arrow for a page that runs as its own activity (nothing to pop): closes the activity.
/// Returns null (default back arrow) when the page was pushed inside the app.
Widget? standaloneBack(BuildContext context) =>
    Navigator.canPop(context) ? null : BackButton(onPressed: SystemNavigator.pop);
