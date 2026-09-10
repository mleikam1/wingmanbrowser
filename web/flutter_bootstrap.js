{{flutter_js}}
{{flutter_build_config}}

// Home must not contact a font/runtime CDN merely to draw Wingman's UI.
// Resolve from <base> so this works at / and with --base-href /wingman/.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    // Roboto and the interface's Noto Sans Symbols glyphs are bundled. Retain
    // Flutter's standard fallback for other Unicode scripts rather than leave
    // saved titles unreadable. Those conditional requests go to fonts.gstatic.com
    // and carry technical request data, not the title or search query.
  },
});
