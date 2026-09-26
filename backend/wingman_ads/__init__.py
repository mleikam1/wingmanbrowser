"""First-party direct campaigns. Fixture money never becomes commercial revenue."""
from .store import AdsStore
from .service import AdsService
from .common import AdsError

__all__ = ['AdsStore', 'AdsService', 'AdsError']
