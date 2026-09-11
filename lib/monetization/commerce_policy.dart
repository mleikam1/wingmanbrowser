import '../config/product_edition.dart';

enum CommerceSurface {
  unknown,
  home,
  discovery,
  classroom,
  externalPage,
  blockedPage,
  support,
  settings,
}

enum CommerceDecision {
  studentEdition,
  unknownEdition,
  privateSession,
  prohibitedSurface,
  inactiveSurface,
  inventoryDisabled,
}

/// Local context only: no URL, query, history, category, identity or interest.
class CommerceContext {
  const CommerceContext({
    this.edition = productEdition,
    this.surface = CommerceSurface.unknown,
    this.isPrivate = false,
    this.isCurrentRoute = false,
    this.isForeground = false,
  });

  final ProductEdition edition;
  final CommerceSurface surface;
  final bool isPrivate;
  final bool isCurrentRoute;
  final bool isForeground;
}

/// All current inventory is closed. There is no enabled result, environment
/// switch, SDK adapter or provider capability that can turn this into an ad.
class CommercePolicy {
  const CommercePolicy();

  CommerceDecision evaluate(CommerceContext context) {
    if (context.edition == ProductEdition.student) {
      return CommerceDecision.studentEdition;
    }
    if (context.edition != ProductEdition.consumer) {
      return CommerceDecision.unknownEdition;
    }
    if (context.isPrivate) return CommerceDecision.privateSession;
    if (context.surface != CommerceSurface.home) {
      return CommerceDecision.prohibitedSurface;
    }
    if (!context.isCurrentRoute || !context.isForeground) {
      return CommerceDecision.inactiveSurface;
    }
    return CommerceDecision.inventoryDisabled;
  }

  /// Even reviewed consumer inventory is not enabled in this milestone.
  bool canDisplay(CommerceContext context) => false;
}
