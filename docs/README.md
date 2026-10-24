# TypeParkinson website

A static, dependency-free site for the existing app. Deploy through GitHub Pages from `main`, folder `/docs`, after Pranav merges the presentation PR.

The app's established `privacy.html` and `support.html` URLs are preserved. No store listing exists yet; the site says Coming soon. Local screenshots come from the installed simulator app. Sample histories are labeled. The correction illustration has four fixed examples and explicitly distinguishes itself from the app's touch-aware Swift decoder.

To preview from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Open `http://127.0.0.1:8765/docs/`. No npm packages, account, tracking or external font requests are required. The film is loaded only on demand (`preload="none"`), and is a smaller 720p copy of the 1080p deliverable in `presentation/`. A text transcript is available beside it.

Screenshots are WebP, with width/height specified to avoid shifting layout. The site supports keyboard navigation, visible focus, live correction announcements, reduced motion and at least 44px demo keys through a container query. On smaller screens the illustrative key layout wraps so targets stay usable.

## Publication

- Merge the PR into `pranav-atreya10/TypeParkinson:main`.
- In repository Settings → Pages, deploy from branch `main`, directory `/docs`, if not already configured.
- Verify the homepage, privacy, support, transcript and film at the published Pages URL.

The GitHub Pages API returned 404 to the fork owner's account during this work; that does not prove whether Pages is disabled or simply inaccessible to this account. Live publication must be confirmed by Pranav.
