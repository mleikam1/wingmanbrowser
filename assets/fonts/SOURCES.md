# Bundled interface fonts

Roboto regular/medium/bold were copied without modification from the installed
Flutter 3.44.4 SDK `bin/cache/artifacts/material_fonts/` directory. Their Apache
2.0 license is in `Roboto_LICENSE.txt` and is included as an application asset.

Noto Sans Symbols was downloaded without modification from the Google Fonts
repository's `ofl/notosanssymbols/NotoSansSymbols[wght].ttf` on 2026-09-10:
https://github.com/google/fonts/tree/main/ofl/notosanssymbols
Its SIL Open Font License is in `NotoSansSymbols_OFL.txt` and is included as an
application asset. This fallback covers symbols used by Wingman's interface.

Fonts are bundled to avoid default Flutter web typography/CDN requests. Other
Unicode script/emoji glyphs may use Flutter's conditional Google-hosted font
fallbacks; requests contain technical network information and font identifiers,
not title text or search queries. This is documented, not a zero-network claim.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `NotoSansSymbols.ttf` | 372,684 | `f7e7e04b4a24b6c78893d50cbfd2b2f6cae49617ab047bfef668d252adb128f7` |
| `Roboto-Bold.ttf` | 170,760 | `7d0b991ee3e0be7af01ad7ea8cd2beea6c00a25e679a0226b6737f079aafff86` |
| `Roboto-Medium.ttf` | 172,064 | `f205cc511821ea56078a105557fcea6253129404d411c997e1866fbd006abb68` |
| `Roboto-Regular.ttf` | 171,676 | `79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95` |
