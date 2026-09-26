"""Explicit deployment entry point. Never imported by local fixtures or tests."""
import os
from .wsgi import create_application
from .config import ConfigurationError

config_path = os.environ.get('WINGMAN_SEARCH_CONFIG')
if not config_path or not os.path.isabs(config_path):
    raise ConfigurationError('explicit_mounted_search_config_required')
application = create_application(config_path)
