# Balanced tracking starter data

Adapted from **EasyPrivacy**, by **The EasyList authors (https://easylist.to/)**.

- Original file: [easyprivacy_trackingservers_thirdparty.txt at c55f475954a28426e8884a6c8d92099d23366536](https://github.com/easylist/easylist/blob/c55f475954a28426e8884a6c8d92099d23366536/easyprivacy/easyprivacy_trackingservers_thirdparty.txt)
- Source SHA-256: `263c91173748a3adb099aeb139081a240addb1885efa6e31ef7b9538b5faa74d`
- Retrieved September 10, 2026. Selection version `2026.09.10.1`.
- Upstream offers GPL 3+ or CC BY-SA 3+. This separate data adaptation is distributed under **Creative Commons Attribution-ShareAlike 3.0 Unported**. [Author licensing statement](https://easylist.to/pages/licence.html), [license](https://creativecommons.org/licenses/by-sa/3.0/), [included legal text](CC-BY-SA-3.0.txt).

Changes: Wingman selected seven exact `||domain^$third-party` rules, represented them as JSON domain suffixes, and additionally excludes main-frame navigation. No original resource-type restrictions were broadened. Keep this attribution, identify further modifications, and share adaptations of this dataset under the applicable ShareAlike license. This data attribution is not an endorsement by EasyList and does not relicense unrelated application source.

The starter contains established analytics/session-replay resources. It is deliberately small and is not all of EasyPrivacy or a complete tracker database. It is separate from lifestyle category and threat lists. It does not classify every advertisement as tracking. Larger future lists need native-format compatibility, exception handling, licensing and breakage review.

Rules must apply only to third-party browser resources, never main-frame navigation or Wingman-owned ad SDK views. Preserve first-party access and the user's temporary site-level Tracking Protection exception. Exceptions must not weaken TLS, phishing, malware or voluntary Guard category policy.

Not included: Disconnect and DuckDuckGo tracker lists, whose published licenses restrict commercial use without a separate agreement. No commercial license or partnership is claimed.
