import 'package:flutter/material.dart';
import '../design_system/wingman_tokens.dart';
export '../design_system/wingman_tokens.dart';

enum WingmanTone { info, success, caution, danger }

class WingmanBrand extends StatelessWidget {
  const WingmanBrand({
    super.key,
    this.markSize = 40,
    this.wordmark = true,
    this.decorative = false,
  });
  final double markSize;
  final bool wordmark, decorative;
  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: markSize,
      height: markSize,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/brand/wingman-mark.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: (markSize * MediaQuery.devicePixelRatioOf(context) * 2)
              .ceil(),
          excludeFromSemantics: true,
        ),
      ),
    );
    return Semantics(
      label: decorative ? null : 'Wingman',
      excludeSemantics: true,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          mark,
          if (wordmark) ...[
            Text(
              'Wingman',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(letterSpacing: -.6),
            ),
          ],
        ],
      ),
    );
  }
}

/// Owned routes have a separate app stack, opaque surfaces and bounded measure.
class WingmanPage extends StatelessWidget {
  const WingmanPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.maxWidth = 720,
    this.padding,
    this.scrollable = true,
    this.onBack,
    this.backTooltip,
    this.bottomNavigationBar,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;
  final VoidCallback? onBack;
  final String? backTooltip;
  final Widget? bottomNavigationBar;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(18) / 18;
    final inset =
        padding ??
        EdgeInsets.all(WingmanTokens.gutter(MediaQuery.sizeOf(context).width));
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: inset, child: child),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        toolbarHeight: scale > 1.4 ? 64 * scale : 64,
        leading: onBack == null
            ? null
            : IconButton(
                tooltip: backTooltip ?? 'Back',
                onPressed: onBack,
                icon: const BackButtonIcon(),
              ),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: scrollable
            ? SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: content,
              )
            : content,
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class WingmanSection extends StatelessWidget {
  const WingmanSection({super.key, required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    ),
  );
}

class WingmanStatus extends StatelessWidget {
  const WingmanStatus({
    super.key,
    required this.title,
    required this.message,
    this.tone = WingmanTone.info,
    this.action,
  });
  final String title, message;
  final WingmanTone tone;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final t = WingmanTokens.of(context);
    final (color, fill, icon) = switch (tone) {
      WingmanTone.info => (t.action, t.raised, Icons.info_outline),
      WingmanTone.success => (
        t.success,
        t.successSurface,
        Icons.check_circle_outline,
      ),
      WingmanTone.caution => (t.caution, t.cautionSurface, Icons.info_outline),
      WingmanTone.danger => (t.danger, t.dangerSurface, Icons.error_outline),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WingmanEmptyState extends StatelessWidget {
  const WingmanEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: WingmanTokens.of(context).action),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class WingmanSettingsRow extends StatelessWidget {
  const WingmanSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
    trailing:
        trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
    onTap: onTap,
  );
}

Future<T?> showWingmanSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final motion = MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: WingmanTokens.sheet,
          reverseDuration: WingmanTokens.sheet,
        );
  if (MediaQuery.sizeOf(context).width >= WingmanTokens.expanded) {
    return showDialog<T>(
      context: context,
      animationStyle: motion,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: builder(context),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    sheetAnimationStyle: motion,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: builder(context),
      ),
    ),
  );
}
