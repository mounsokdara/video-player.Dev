import 'package:flutter/material.dart';
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
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
