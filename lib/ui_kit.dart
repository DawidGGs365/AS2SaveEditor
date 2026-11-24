import 'l10n.dart';
import 'package:material_ui/material_ui.dart';

/// One type scale for the whole app. Everything uses these five styles.
ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1F8A7A), brightness: b);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  final tt = base.textTheme.copyWith(
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w400),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
  );
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
  return base.copyWith(
    textTheme: tt,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: tt.headlineSmall?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        shape: const StadiumBorder(),
        textStyle: tt.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const StadiumBorder(),
        textStyle: tt.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: pill,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 28),
      extendedTextStyle: tt.labelLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: scheme.primary, width: 2)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      titleTextStyle: tt.headlineSmall?.copyWith(color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStatePropertyAll(tt.bodySmall),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

extension Ctx on BuildContext {
  TextTheme get tt => Theme.of(this).textTheme;
  ColorScheme get cs => Theme.of(this).colorScheme;
}

const double kIndent = 22;

/// Draws the vertical guide lines of a tree row for each depth level.
class _Guides extends CustomPainter {
  final int depth;
  final Color color;
  _Guides(this.depth, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var i = 0; i < depth; i++) {
      final x = 12.0 + i * kIndent + 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_Guides o) => o.depth != depth || o.color != color;
}

class GuideRow extends StatelessWidget {
  final int depth;
  final Widget child;
  const GuideRow({super.key, required this.depth, required this.child});
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _Guides(depth, context.cs.outlineVariant),
        child: Padding(padding: EdgeInsets.only(left: 12.0 + depth * kIndent, right: 12), child: child),
      );
}

/// Rounded value chip shown on the right of a leaf row.
class ValuePill extends StatelessWidget {
  final String text;
  final bool muted;
  const ValuePill(this.text, {super.key, this.muted = false});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.42),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: muted ? Colors.transparent : cs.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: muted ? Border.all(color: cs.outlineVariant) : null,
      ),
      child: Text(
        text.isEmpty ? t('(empty)') : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.tt.labelLarge?.copyWith(
            color: muted ? cs.onSurfaceVariant : cs.onSecondaryContainer),
      ),
    );
  }
}

/// A leaf row: title + small type line on the left, value on the right.
class LeafRow extends StatelessWidget {
  final int depth;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  const LeafRow(
      {super.key,
      required this.depth,
      required this.title,
      this.subtitle,
      required this.trailing,
      this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: GuideRow(
        depth: depth,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const SizedBox(width: 32),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: context.tt.bodyLarge),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(width: 12),
              trailing,
            ]),
          ),
        ),
      ),
    );
  }
}

/// A tree node that expands to show children, built only when opened.
class TreeNode extends StatefulWidget {
  final int depth;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool initiallyOpen;
  final List<Widget> Function() build;
  const TreeNode(
      {super.key,
      required this.depth,
      required this.title,
      this.subtitle,
      this.leading,
      this.initiallyOpen = false,
      required this.build});
  @override
  State<TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<TreeNode> {
  late bool open = widget.initiallyOpen;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => open = !open),
        borderRadius: BorderRadius.circular(16),
        child: GuideRow(
          depth: widget.depth,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.chevron_right, color: context.cs.primary),
                ),
                const SizedBox(width: 8),
                if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.title, style: context.tt.titleMedium),
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                      Text(widget.subtitle!,
                          style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
      if (open) ...widget.build(),
    ]);
  }
}

/// Rounded card with a heading, used to group rows.
class SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SectionCard({super.key, required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(title, style: context.tt.titleMedium?.copyWith(color: context.cs.primary)),
          ),
          ...children,
        ]),
      ),
    );
  }
}
