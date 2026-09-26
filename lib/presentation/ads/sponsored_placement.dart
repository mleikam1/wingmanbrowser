import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../ads/session.dart';
import '../components/wingman_components.dart';

/// Only first-party text is painted. Delivery, paint, viewability and deliberate
/// activation are separate events; no merchant request happens before activation.
class SponsoredPlacement extends StatefulWidget {
  const SponsoredPlacement({
    super.key,
    required this.session,
    required this.onOpen,
    required this.canContinue,
    this.scrollController,
  });
  final AdSession session;
  final ValueChanged<Uri> onOpen;
  final bool Function() canContinue;
  final ScrollController? scrollController;
  @override
  State<SponsoredPlacement> createState() => _SponsoredPlacementState();
}

class _SponsoredPlacementState extends State<SponsoredPlacement>
    with WidgetsBindingObserver {
  final _creative = GlobalKey();
  Timer? _viewTimer, _geometryTimer;
  bool _foreground = true, _clicked = false, _expired = false;
  int _visible = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.session.addListener(_changed);
    widget.scrollController?.addListener(_check);
    _geometryTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _check(),
    );
    _afterPaint();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reset();
    _afterPaint();
  }

  @override
  void didUpdateWidget(SponsoredPlacement old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_changed);
      widget.session.addListener(_changed);
      _clicked = false;
      _expired = false;
      _reset();
    }
    if (old.scrollController != widget.scrollController) {
      old.scrollController?.removeListener(_check);
      widget.scrollController?.addListener(_check);
    }
    _afterPaint();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
      _afterPaint();
    }
  }

  void _afterPaint() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (_active) unawaited(widget.session.load());
    _check();
  });
  bool get _active =>
      mounted &&
      _foreground &&
      widget.canContinue() &&
      widget.session.eligible &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  int _visibility() {
    if (!_active) return 0;
    final render = _creative.currentContext?.findRenderObject();
    if (render is! RenderBox ||
        !render.attached ||
        !render.hasSize ||
        render.size.isEmpty) {
      return 0;
    }
    final rect = MatrixUtils.transformRect(
      render.getTransformTo(null),
      render.paintBounds,
    );
    var visible = rect.intersect(Offset.zero & MediaQuery.sizeOf(context));
    RenderObject? parent = render.parent;
    while (parent != null) {
      if (parent is RenderAbstractViewport) {
        visible = visible.intersect(
          MatrixUtils.transformRect(
            parent.getTransformTo(null),
            parent.paintBounds,
          ),
        );
      }
      parent = parent.parent;
    }
    if (visible.isEmpty || rect.isEmpty) return 0;
    return ((visible.width * visible.height / (rect.width * rect.height)) *
            1000)
        .floor()
        .clamp(0, 1000);
  }

  void _reset() {
    _viewTimer?.cancel();
    _viewTimer = null;
    _visible = 0;
  }

  void _check() {
    if (!mounted) return;
    if (widget.session.ad?.expired == true && !_expired) {
      _expired = true;
      setState(() {});
    }
    _visible = _visibility();
    if (_visible > 0) {
      unawaited(
        widget.session.send('render', visiblePermille: _visible, visibleMs: 0),
      );
    }
    if (_visible < 500 || !_active) {
      _viewTimer?.cancel();
      _viewTimer = null;
      return;
    }
    if (_viewTimer == null && !widget.session.hasSent('view')) {
      _viewTimer = Timer(const Duration(seconds: 1), () {
        _viewTimer = null;
        _visible = _visibility();
        if (_visible >= 500 && _active) {
          unawaited(
            widget.session.send(
              'view',
              visiblePermille: _visible,
              visibleMs: 1000,
            ),
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _reset();
    if (!_foreground) {
      widget.session.cancel();
    } else {
      _afterPaint();
    }
  }

  @override
  void didChangeMetrics() {
    _reset();
    _afterPaint();
  }

  Future<void> _click() async {
    _check();
    if (!_active ||
        _visible == 0 ||
        _clicked ||
        widget.session.hasSent('click')) {
      return;
    }
    setState(() => _clicked = true);
    final url = await widget.session.send(
      'click',
      visiblePermille: _visible,
      visibleMs: 0,
      explicitAction: true,
    );
    if (_active && url != null) widget.onOpen(url);
  }

  @override
  void dispose() {
    _reset();
    _geometryTimer?.cancel();
    widget.session.removeListener(_changed);
    widget.scrollController?.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.session.ad;
    if (ad == null || _expired || !_active) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Card(
        key: _creative,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: WingmanTokens.of(context).divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: 'Sponsored advertisement',
                child: Text(
                  ad.fixture
                      ? 'Sponsored · Test campaign · No real charges'
                      : 'Sponsored',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ad.advertiser,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Text(ad.headline, style: Theme.of(context).textTheme.titleLarge),
              if (ad.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(ad.body),
              ],
              const SizedBox(height: 6),
              Text(
                ad.displayDomain,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: _clicked ? null : _click,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(
                      _clicked ? 'Sponsor selected' : 'Visit sponsor',
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _reset();
                      showDialog<void>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: const Text('Why this ad?'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ad.whyThisAd),
                                const SizedBox(height: 12),
                                const Text(
                                  'Wingman does not use browsing history, past searches or personal profiles to select this placement. Advertisers receive no individual query or browsing-session report. Visiting the sponsor opens its website, which has its own data practices.',
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Why this ad?'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
