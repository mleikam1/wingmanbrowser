# Actual story photographs

**Version: 0.13.1+15.** Story cards show only photographs verified against the exact publisher article. The local catalog contains **four** reviewed images: three from NASA/USGS and a separately licensed Solidarity Center photograph used by Global Voices. A match requires both the article's canonical URL and its approved source ID. All other stories remain text-only; there is no stock, topic or generic-photo fallback.

Existing DiscoveryPhotos are separate user-selected Home artwork. They are not assigned to stories. No new Unsplash topic-photo collection is part of this feature.

## Display and selection

`lib/live_content/story_images.dart` owns the finite image records and nullable article lookup. `lib/presentation/live_content/live_story_image.dart` renders an approved record with `Image.asset`. Home, Updates and eligible Reading List entries use the same matching rule; a source mismatch or another story on the same host does not receive the image.

Each displayed photo includes its credit and image date or archive date. The satellite picture is dated September 5, 2026. The zebra-mussel photograph is identified as a 1992 archive image, the Maunaiki photographs as 1919–1920 archives, and the Bangladesh factory photograph as a 2015 archive image. An image used by the publisher is not necessarily a photograph of the new event described in the headline. In particular, the mussel photograph shows Lake Huron specimens, not newly found Utah mussels; the garment workers were not photographed in 2026.

Descriptive alternative text describes the actual image. The responsive image layout must preserve readable headlines and captions at larger text sizes. If a packaged asset cannot decode, the renderer uses a local unavailable state and makes no remote request. No unrelated illustration replaces an unavailable story photo.

## Current image inventory

| Local asset | Exact source ID | Publisher story | Credit and image context |
| --- | --- | --- | --- |
| `assets/story_images/story_krakatau.jpg` | `nasa-technology` | [Anak Krakatau Rumbles Again](https://science.nasa.gov/earth/earth-observatory/anak-krakatau-rumbles-again/) | NASA Earth Observatory / Michala Garrison; Landsat data from USGS. Satellite image from September 5, 2026, accompanying the September 9 story. |
| `assets/story_images/story_zebra_mussels.jpg` | `usgs-news` | [Environmental DNA monitoring in the Colorado River](https://www.usgs.gov/centers/norock/news/environmental-dna-monitoring-leads-early-detection-invasive-zebra-mussel-dna) | U.S. Geological Survey / Amy Benson. Lake Huron specimens, archive photograph dated March 14, 1992, used in the September 11, 2026 article. |
| `assets/story_images/story_maunaiki.jpg` | `usgs-news` | [Remembering the 1919–1920 Maunaiki eruption](https://www.usgs.gov/observatories/hvo/news/volcano-watch-remembering-1919-1920-maunaiki-eruption-kilauea) | U.S. Geological Survey / Hawaiian Volcano Observatory; Thomas Jaggar. Photographs from December 22, 1919 and January 14, 1920, used in the September 10, 2026 article. |
| `assets/story_images/story_garment_workers.webp` | `globalvoices-fashion` | [Garment workers and childcare in Bangladesh](https://globalvoices.org/2026/09/04/maternity-leave-is-expanding-in-bangladesh-but-garment-workers-still-struggle-for-childcare/) | Solidarity Center · CC BY 2.0. Gazipur factory photograph taken November 18, 2015; publisher-cropped rendition used in the September 4, 2026 article. |

The exact article URLs in this table are the matching identities, not host-wide permissions. The current finite catalog does not establish article-specific photos for the other stories or for all ten content topics. Further photos require separate review; unconfirmed candidates are not shipped as approved images.

## Rights and provenance

NASA's [image-use guidance](https://www.nasa.gov/nasa-brand-center/images-and-media/) permits credited factual/editorial use within its conditions. It does not authorize copying protected third-party material, imply NASA endorsement or waive identifiable-person and branding restrictions. The selected satellite image's [article](https://science.nasa.gov/earth/earth-observatory/anak-krakatau-rumbles-again/) supplies the image credit and acquisition date; no third-party copyright notice accompanies it. Do not describe this as a universal CC0 license for NASA imagery.

USGS explicitly marks the individual [zebra-mussel media record](https://www.usgs.gov/media/images/zebra-mussels) and [Maunaiki media record](https://www.usgs.gov/media/images/photos-lead-and-eruption-1919-1920-maunaiki-shield-southwest-rift-zone-kilauea) **Public Domain**. Those records identify Amy Benson and Thomas Jaggar respectively. The [USGS copyright/credit policy](https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits) distinguishes agency-produced work from protected third-party material and requests proper photographer credit. These decisions are per image, not permission to reuse every photograph on a government domain.

The garment-worker article's caption and the [original Solidarity Center photo](https://www.flickr.com/photos/62762640@N02/29010292884) independently identify [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/), permitting commercial copying/adaptation with attribution and license information. Retain the original title, creator, photo link and license in credits; show 2015 as the photo date and disclose publisher cropping/resizing and display cropping. The photograph remains in its documented labor-reporting context, without claiming that the depicted workers endorse Wingman. This permission is separate from Global Voices' text license.

Original download URLs, dimensions, byte counts, hashes and saved-image review are retained in `assets/story_images/article_manifest.json` and `assets/story_images/ARTICLE_LICENSES.md`. The app's Photo credits surface retains photographer, source and license information. Download URLs are provenance; rendering does not contact them. The satellite and mussel photographs may be cropped to fit; the paired Maunaiki photographs use containment so both panels remain visible. Preserve the historical distinction in captions.

No current NOAA story image was cleared in the bounded review: its selected article page returned 403. Global Voices' [text attribution policy](https://globalvoices.org/about/global-voices-attribution-policy/) explicitly distinguishes third-party media rights; its CC BY 3.0 text grant is not inherited by unknown photos. The reviewed Casablanca music photos had permission-only/courtesy notices, the Haiti football lead image used Canva Pro elements, and the Indigenous-crops photo had a permission-only credit. These were not cleared for Wingman. Apart from the separately licensed factory photo, those reviewed stories remain text-only.

## Privacy, protection and cost

Source-wide `images:false` is unchanged. RSS/Atom image and enclosure URLs remain rejected; no `og:image` scraper, arbitrary asset path, remote fallback, thumbnail tracker or image-classification API is introduced. A local photo record cannot bypass current item eligibility, additional restrictions, destination protection, owner-context checks or withdrawn-content handling. Private and handoff views do not receive the owner's story images or Reading List content.

The four new files—three JPEGs and one WebP—total **1,180,639 bytes (1.181 MB)** before packaging: Krakatau 56,671; zebra mussels 760,401; Maunaiki 281,597; garment workers 81,970. Native viewing uses installed bytes and needs no image network request. Web distribution serves them as ordinary same-origin application assets, not requests to NASA, USGS, Global Voices, Flickr or an image CDN. No image API, paid stock subscription, account, per-view charge or dedicated image-hosting service is configured. Existing app distribution and bandwidth costs remain separate.

Photos were acquired and reviewed as finite assets; future publisher changes cannot silently replace installed image bytes. New or changed images require rights/credit review, visual review and a new packaged catalog entry. That review is not an automatic image-safety guarantee for publisher websites, ads, recommendations or future stories.

## Evidence scope

The initial three government candidate image URLs returned HEAD 200 with `image/jpeg` during the September 13 research. That stage downloaded no image bodies; later asset acquisition and saved-byte review are documented in the asset records. The separate factory-photo review checked the publisher caption and Flickr license before downloading and visually inspecting the exact WebP. All four packaged files' hashes and sizes match the final article manifest. Source review and manifest checks are distinct from UI, automated-test and native-build validation. The measured checks below describe this implementation; no physical-device browser journey is claimed by the widget renders.

Related: [Content sources and rights](CONTENT_SOURCES_AND_RIGHTS.md), [Privacy architecture](PRIVACY_ARCHITECTURE.md), and the initial research in `work/story-images/source-rights.md` (whose proposed generic fallback was superseded by the actual-story-only requirement).

## Measured validation — 13 September 2026

- `flutter analyze`: no issues.
- Full Flutter suite: **828 passed, 5 skipped** (opt-in/native capture fixtures).
- Focused image/core/UI checks: **28 passed**; the four core image/provenance checks also passed after adding the original Creative Commons photo title to its credit record.
- Real publisher snapshot render: **1 passed**, 12 screenshots over 78 cached native-feed items, no network during capture. All four exact story images, text-only unmatched stories, saved imagery and dark layout were inspected. Responsive tests cover 320px width and 200% text in both themes.
- Android release APK: **72,272,373 bytes**; installed with `adb install -r` on emulator-5554. Package metadata confirms version **0.13.1**, code **15**.
- Signed iOS archive and App Store IPA: **31,227,418-byte IPA**, bundle **com.wingmanbrowser.app**, version **0.13.1 (15)**. Deep/strict archive signature verification passed.
- All four image hashes in the APK and IPA match the reviewed source manifest. Image viewing does not depend on a publisher media request.

Local logs, build/hash receipt and capture evidence are under `work/story-images/`. Build/export success does not itself establish TestFlight availability; upload and internal-group assignment must be confirmed separately in App Store Connect.

## Internal TestFlight delivery

Xcode Organizer uploaded **0.13.1 (15)** using **TestFlight Internal Only** on
September 13, 2026. The earlier command-line upload returned `Failed to Use
Accounts`; the signed-in graphical Organizer workflow succeeded. App Store
Connect completed processing, accepted the existing standard-encryption/no-France
answers for the user-confirmed U.S.-only beta, and saved the new testing notes.
The build was assigned to **Wingman Device Testing** and its group row was
verified as **Testing**, with one internal tester. Testers can update Wingman in
TestFlight. This confirms availability; it does not claim the new build has
already been installed or exercised on a physical device.
