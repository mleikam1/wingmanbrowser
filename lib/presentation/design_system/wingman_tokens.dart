import 'package:flutter/material.dart';

/// Semantic roles from the committed handoff; artwork retains its own colors.
@immutable
class WingmanTokens extends ThemeExtension<WingmanTokens> {
  const WingmanTokens({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.text,
    required this.secondaryText,
    required this.action,
    required this.onAction,
    required this.divider,
    required this.controlOutline,
    required this.success,
    required this.successSurface,
    required this.caution,
    required this.cautionSurface,
    required this.danger,
    required this.dangerSurface,
  });
  final Color canvas, surface, raised, text, secondaryText, action, onAction;
  final Color divider, controlOutline, success, successSurface;
  final Color caution, cautionSurface, danger, dangerSurface;
  static const navy = Color(0xff071b4d), cyan = Color(0xff20cff2);
  static const compact = 600.0, expanded = 1024.0;
  static const press = Duration(milliseconds: 120);
  static const sheet = Duration(milliseconds: 200);
  static const route = Duration(milliseconds: 250);
  static const light = WingmanTokens(
    canvas: Color(0xfff5f8ff),
    surface: Color(0xffffffff),
    raised: Color(0xffedf3ff),
    text: Color(0xff10213d),
    secondaryText: Color(0xff54647b),
    action: Color(0xff0062e8),
    onAction: Color(0xffffffff),
    divider: Color(0xffdfe7f3),
    controlOutline: Color(0xff73829a),
    success: Color(0xff186440),
    successSurface: Color(0xffeaf6ef),
    caution: Color(0xff805100),
    cautionSurface: Color(0xfffff5e2),
    danger: Color(0xffad283c),
    dangerSurface: Color(0xffffedf0),
  );
  static const dark = WingmanTokens(
    canvas: Color(0xff08111f),
    surface: Color(0xff101d31),
    raised: Color(0xff162640),
    text: Color(0xffedf4ff),
    secondaryText: Color(0xffa9b9d0),
    action: Color(0xff79aaff),
    onAction: Color(0xff071b4d),
    divider: Color(0xff2a3b55),
    controlOutline: Color(0xff8093ae),
    success: Color(0xff8bdbab),
    successSurface: Color(0xff123325),
    caution: Color(0xffffcf83),
    cautionSurface: Color(0xff342918),
    danger: Color(0xffffa1b0),
    dangerSurface: Color(0xff3b1c29),
  );
  static WingmanTokens of(BuildContext context) =>
      Theme.of(context).extension<WingmanTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  static double gutter(double width) => width < 360
      ? 16
      : width < 600
      ? 20
      : width < 1024
      ? 32
      : 40;
  @override
  WingmanTokens copyWith() => this;
  @override
  WingmanTokens lerp(covariant WingmanTokens? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return WingmanTokens(
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      text: mix(text, other.text),
      secondaryText: mix(secondaryText, other.secondaryText),
      action: mix(action, other.action),
      onAction: mix(onAction, other.onAction),
      divider: mix(divider, other.divider),
      controlOutline: mix(controlOutline, other.controlOutline),
      success: mix(success, other.success),
      successSurface: mix(successSurface, other.successSurface),
      caution: mix(caution, other.caution),
      cautionSurface: mix(cautionSurface, other.cautionSurface),
      danger: mix(danger, other.danger),
      dangerSurface: mix(dangerSurface, other.dangerSurface),
    );
  }
}
