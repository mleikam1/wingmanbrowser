import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../search/controller.dart';
import '../live_content/live_story_image.dart' show LivePublisherImage;

/// A reserved, compact preview slot keeps text and scroll geometry stable while
/// a visible result loads. Its optional bytes never become a navigation target.
class SearchResultPreview extends StatefulWidget {
  const SearchResultPreview({
    super.key,
    required this.result,
    required this.controller,
    required this.scrollController,
    required this.canContinue,
    required this.child,
  });
  final SearchResult result;
  final WingmanSearchController controller;
  final ScrollController scrollController;
  final bool Function() canContinue;
  final Widget child;
  @override
  State<SearchResultPreview> createState() => _SearchResultPreviewState();
}

class _SearchResultPreviewState extends State<SearchResultPreview>
    with WidgetsBindingObserver {
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.scrollController.addListener(_afterLayout);
    _afterLayout();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _afterLayout();
  }

  @override
  void didUpdateWidget(SearchResultPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_afterLayout);
      widget.scrollController.addListener(_afterLayout);
    }
    _afterLayout();
  }

  void _afterLayout() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _check();
    });
  }

  bool _visible() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        !widget.canContinue() ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    final render = context.findRenderObject();
    if (render is! RenderBox ||
        !render.attached ||
        !render.hasSize ||
        render.size.isEmpty) {
      return false;
    }
    var rect = MatrixUtils.transformRect(
      render.getTransformTo(null),
      render.paintBounds,
    ).intersect(Offset.zero & MediaQuery.sizeOf(context));
    RenderObject? parent = render.parent;
    while (parent != null) {
      if (parent is RenderAbstractViewport) {
        rect = rect.intersect(
          MatrixUtils.transformRect(
            parent.getTransformTo(null),
            parent.paintBounds,
          ),
        );
      }
      parent = parent.parent;
    }
    return !rect.isEmpty;
  }

  void _check() {
    if (_visible()) {
      widget.controller.requestThumbnail(widget.result, visible: _visible);
    }
  }

  @override
  void didChangeMetrics() => _afterLayout();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _afterLayout();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_afterLayout);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.controller;
    if (widget.result.thumbnail == null ||
        model.context != SearchContext.normal ||
        model.kind != SearchKind.news) {
      return widget.child;
    }
    final bytes = model.thumbnailBytesFor(widget.result);
    // Keep this same slot after a missing/expired/failed image; no spinner,
    // broken-image control or replacement art competes with the original text.
    Widget visual(double width) => SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: bytes == null
            ? const SizedBox.shrink()
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ExcludeSemantics(
                  child: LivePublisherImage(
                    key: ValueKey(
                      'search-thumbnail-${widget.result.thumbnail!.token}',
                    ),
                    bytes: bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 360 &&
            MediaQuery.textScalerOf(context).scale(16) < 24) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: widget.child),
              const SizedBox(width: 16),
              visual(120),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            visual(constraints.maxWidth.clamp(0, 192)),
            const SizedBox(height: 8),
            widget.child,
          ],
        );
      },
    );
  }
}
