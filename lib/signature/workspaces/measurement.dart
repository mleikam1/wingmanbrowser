enum MeasureDimension { length, area, volume, temperature }

enum MeasureUnit {
  millimetres('mm', MeasureDimension.length, .001),
  centimetres('cm', MeasureDimension.length, .01),
  metres('m', MeasureDimension.length, 1),
  inches('in', MeasureDimension.length, .0254),
  feet('ft', MeasureDimension.length, .3048),
  squareMetres('m²', MeasureDimension.area, 1),
  squareFeet('ft²', MeasureDimension.area, .09290304),
  millilitres('mL', MeasureDimension.volume, .001),
  litres('L', MeasureDimension.volume, 1),
  celsius('°C', MeasureDimension.temperature, 1),
  fahrenheit('°F', MeasureDimension.temperature, 1);

  const MeasureUnit(this.label, this.dimension, this.factor);
  final String label;
  final MeasureDimension dimension;
  final double factor;
}

/// General planning arithmetic, never a structural/material safety assessment.
/// Length uses the international foot, not the retired US survey foot.
double convertMeasurement(double value, MeasureUnit from, MeasureUnit to) {
  if (!value.isFinite ||
      value.abs() > 1e12 ||
      from.dimension != to.dimension ||
      (from.dimension != MeasureDimension.temperature && value < 0)) {
    throw const FormatException('Enter a finite value in compatible units.');
  }
  if (from.dimension == MeasureDimension.temperature) {
    final converted = from == MeasureUnit.fahrenheit
        ? (value - 32) / 1.8
        : value;
    // The exact boundary -459.67°F incurs a few ulps in binary arithmetic.
    if (converted < -273.15 - 1e-10) {
      throw const FormatException('Below absolute zero.');
    }
    final celsius = converted < -273.15 ? -273.15 : converted;
    return to == MeasureUnit.fahrenheit ? celsius * 1.8 + 32 : celsius;
  }
  return value * from.factor / to.factor;
}
