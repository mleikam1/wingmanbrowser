"""Ordered, explicitly gated demand slots. No network client or partner is bundled.

An actual adapter must be reviewed separately. It can propose only a pre-funded,
reviewed local campaign ID, never HTML, a URL, tracking fields or a second auction.
"""
from .common import AdsError, identifier

class DemandSlot:
    def __init__(self, source, adapter=None, authorization=None):
        if source not in {'partner','merchant'}: raise AdsError('invalid-demand-source')
        self.source,self.adapter,self.authorization=source,adapter,authorization

    def choose(self, candidates, context, now):
        a=self.authorization
        if self.adapter is None or not isinstance(a,dict): return None,'uncontracted-'+self.source
        fields={'ownerApproved','expiresAt','agreementReference','apiReviewReference','privacyReviewReference',
                'inventoryApproved','providerCompatible','identifierFree','noSdkCookiePixel','merchantActionPermitted'}
        if (set(a)!=fields or any(a[k] is not True for k in ('ownerApproved','inventoryApproved','providerCompatible',
                'identifierFree','noSdkCookiePixel')) or type(a['expiresAt']) is not int or not now<a['expiresAt']
                or (self.source=='merchant' and a['merchantActionPermitted'] is not True)):
            return None,'unauthorized-'+self.source
        for key in ('agreementReference','apiReviewReference','privacyReviewReference'): identifier(a[key])
        # No adapter call when there is no reviewed, funded inventory to choose.
        allowed={item[3]['id']:item for item in candidates if item[3]['config'].get('demandSource','direct')==self.source}
        if not allowed: return None,'no-approved-'+self.source+'-inventory'
        try:
            proposed=self.adapter.select(dict(context),tuple(allowed))
        except TimeoutError:
            return None,self.source+'-timeout'
        except Exception:
            return None,self.source+'-unavailable'
        return allowed.get(proposed),'unfilled-'+self.source

class CandidateChain:
    def __init__(self, partner=None, merchant=None):
        self.partner=partner or DemandSlot('partner')
        self.merchant=merchant or DemandSlot('merchant')

    def choose(self,candidates,context,now):
        direct=[item for item in candidates if item[3]['config'].get('demandSource','direct')=='direct']
        if direct: return direct[0],[]
        reasons=[]
        for slot in (self.partner,self.merchant):
            candidate,reason=slot.choose(candidates,context,now)
            if candidate is not None: return candidate,reasons
            reasons.append(reason)
        return None,reasons
