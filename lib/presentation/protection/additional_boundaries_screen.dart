import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../../config/product_edition.dart';
import '../../state/browser_state.dart';
import '../components/wingman_components.dart';

class AdditionalBoundariesScreen extends StatefulWidget {
  const AdditionalBoundariesScreen({
    super.key,
    required this.state,
    required this.policy,
    required this.isPrivate,
    required this.canContinue,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final bool isPrivate;
  final bool Function() canContinue;
  @override
  State<AdditionalBoundariesScreen> createState() =>
      _AdditionalBoundariesScreenState();
}

class _AdditionalBoundariesScreenState
    extends State<AdditionalBoundariesScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _change({
    String? collection,
    String? resourceId,
    required bool hidden,
  }) async {
    if (_busy || widget.isPrivate || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.setAdditionalBoundary(
        collection: collection,
        resourceId: resourceId,
        hidden: hidden,
        isPrivate: widget.isPrivate,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The boundary could not be saved. Your previous restrictions remain in effect.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.state, widget.policy]),
    builder: (context, _) {
      final restrictions = widget.state.protectedPreferences.additional;
      final resources = widget.policy.catalog
          .where(
            (r) =>
                r.collection != 'support' &&
                widget.policy.policy
                    .evaluate(
                      PolicyRequest.bundled(
                        r.id,
                        isPrivate: widget.isPrivate,
                        context: productEdition == ProductEdition.consumer
                            ? ContentContext.general
                            : ContentContext.student,
                      ),
                    )
                    .isAllowed,
          )
          .toList();
      final sites = widget.policy.liveSites
          .where(
            (site) =>
                site.collection != 'support' &&
                widget.policy.policy.livePolicy
                        ?.assessNavigation(
                          Uri.parse(site.entryUrl),
                          context: productEdition == ProductEdition.consumer
                              ? ContentContext.general
                              : ContentContext.student,
                          now: widget.policy.clock.now(),
                        )
                        .isAllowed ==
                    true,
          )
          .toList();
      final collections = {
        ...resources.map((r) => r.collection),
        ...sites.map((s) => s.collection),
      }.toList()..sort();
      return WingmanPage(
        title: 'Additional boundaries',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose less of the reviewed library and supported websites. Removing an additional boundary never approves prohibited, expired, unsupported or unreviewed content.',
            ),
            if (widget.isPrivate)
              const WingmanStatus(
                title: 'Inherited in private',
                message:
                    'Your existing additional boundaries apply here. Change them from a normal session; private controls cannot alter the owner’s preferences.',
                tone: WingmanTone.info,
              ),
            const SizedBox(height: 20),
            const WingmanSection(title: 'Collections'),
            for (final collection in collections)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Hide ${collection.replaceAll('-', ' ')}'),
                value: restrictions.blockedCollections.contains(collection),
                onChanged: _busy || widget.isPrivate
                    ? null
                    : (v) => _change(collection: collection, hidden: v),
              ),
            const SizedBox(height: 20),
            const WingmanSection(title: 'Individual reviewed items'),
            if (widget.policy.status.usable)
              for (final resource in resources)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Hide ${resource.title}'),
                  value: restrictions.blockedResourceIds.contains(resource.id),
                  onChanged: _busy || widget.isPrivate
                      ? null
                      : (v) => _change(resourceId: resource.id, hidden: v),
                )
            else
              const Text(
                'The catalog is unavailable. Previously saved boundaries remain in place.',
              ),
            if (sites.isNotEmpty) ...[
              const SizedBox(height: 20),
              const WingmanSection(title: 'Reviewed website scopes'),
              for (final site in sites)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Hide ${site.title}'),
                  subtitle: Text(Uri.parse(site.entryUrl).host),
                  value: restrictions.blockedResourceIds.contains(site.id),
                  onChanged: _busy || widget.isPrivate
                      ? null
                      : (v) => _change(resourceId: site.id, hidden: v),
                ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Schedules and authenticated managed settings are unavailable. Hiding a website closes its entire reviewed scope. Reviewed support stays available while its policy is valid.',
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              WingmanStatus(
                title: 'Not saved',
                message: _error!,
                tone: WingmanTone.caution,
              ),
          ],
        ),
      );
    },
  );
}
