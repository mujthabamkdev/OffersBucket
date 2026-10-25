# OffersBucket landing page

A self-contained, static HTML/CSS website. No build step, JavaScript, external
fonts, or package installation is required. Upload the contents of this directory
to any static host, or select `website` as the site's root directory.

## Preview locally

From the repository root:

```bash
python3 -m http.server 8080 --bind 127.0.0.1 --directory website
```

Open <http://localhost:8080>. Opening `index.html` directly also works.

## Add store links

In `index.html`, find `android-download` and `ios-download`. When each app is
published:

1. Replace its disabled `<button>` with an `<a>` using the real store URL as
   `href`, retaining the `store-button` class and ID.
2. Remove `type`, `disabled`, and `aria-describedby` from that element, and
   replace the closing `</button>` with `</a>`.
3. Change its “Coming soon” text to “Download”, and update the release-status
   copy in the hero, download section, and page description as appropriate.
4. Keep the platform distinction: Android supports opt-in notification capture;
   iOS supports manual entry, not capture of other apps' notifications.

The disabled buttons intentionally do not download APKs or link to unrelated
store listings.

## Assets

- `assets/screenshots/`: actual Flutter UI rendered with sample data, exported
  at 2× resolution and compressed as WebP. These are previews, not live offers.
- `assets/mark.svg`: the app's OffersBucket mark with a tighter view box.
- `assets/fonts/`: bundled Manrope fonts and their SIL Open Font License.

Typography, charcoal colors, a fine grid background, and rounded panels follow
the MotoMall-inspired visual direction used in the app. No MotoMall assets or
commercial font files are included.
