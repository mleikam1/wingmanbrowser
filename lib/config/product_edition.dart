/// Packaging choice only. It is never loaded from preferences or a deep link.
/// All editions retain the same mandatory content policy.
enum ProductEdition { consumer, student, unknown }

const _configuredEdition = String.fromEnvironment(
  'WINGMAN_EDITION',
  defaultValue: 'consumer',
);

const productEdition = _configuredEdition == 'consumer'
    ? ProductEdition.consumer
    : _configuredEdition == 'student'
    ? ProductEdition.student
    : ProductEdition.unknown;
