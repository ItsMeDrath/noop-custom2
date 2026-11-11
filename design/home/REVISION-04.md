# Home revision 04 — expiry removed and typography corrected

The latest user feedback rejects the previous match and explicitly removes the membership-expiry banner. The warning view, its call site, the sample expiry field and the expiry wording in the local membership panel are removed. Home content now occupies the space previously used by the banner; no blank spacer is retained. The compact mini-ring header starts at the revised scroll offset.

The typography review identified that all-Inter figures and uppercase labels were visibly different from the supplied screenshots. Barlow Bold, SemiBold and Medium now supply figures, uppercase labels and compact values, while Inter remains the body font. Both are free fonts. A more condensed candidate was rejected after visual review; the final Barlow family is wider and closer to the reference proportions. Font source URLs, byte sizes and hashes are retained in [PULSE-fonts.json](../../Docs/PULSE-fonts.json). The OFL license is bundled with the font resources.

The header streak uses a system flame emoji, and the native tracker button uses the closer watch/band SF Symbol. Sleep, Recovery, Strain and all previously restored section labels remain unchanged. The real tracker panel and adapter are unchanged; the Home reference scores remain illustrative.

## Checks

- Ten browser checks pass, including an explicit absence check for the expiry warning and expiry date.
- The actual Swift DTO decodes the updated seven-day fixture after removing the expiry field.
- All 32 app Swift sources plus the widget pass frontend syntax parsing; project and all four registered font references pass structural validation.
- The font PostScript names were checked against the names used by the native app.

The current images are browser interpretations of the updated source. They do not establish native SwiftUI rendering or an exact reference-image match. The original-branding constraint still creates intentional differences: PULSE wordmark/Coach monogram, free fonts and SF Symbols, and original symbol-based promotional illustrations. No Apple SDK build or iPhone simulator comparison was performed.

This revision supersedes the expiry-banner and typography descriptions in revision 03 and older notes. Other primary screens continue to await Home approval.
