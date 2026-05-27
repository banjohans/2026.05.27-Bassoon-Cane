# ReedLab

ReedLab is a cross-platform Flutter application for cane and reed tracking,
focused on predictable outcomes rather than generic quality rankings.

## Scientific Intent

The app is grounded in observations from A. B. Lauritzen's _Something About Cane_
(2011):

- Cane properties are measurable.
- Geometry strongly affects measurements.
- Elasticity and stiffness are separate variables.
- Resonance is useful but must be dimension-aware.
- Historical reed outcomes are required for prediction.

## MVP Included

- Cane registration with required dimensions and measurement fields.
- Automatic relative stiffness calculation: $S = \frac{Load}{Twist}$.
- Standard Flexter load set to 200 g.
- Hardness is treated as the primary material-quality test; mass is supplementary context.
- Frequency is shown both as raw Hz and Lauritzen tone index (0-36).
- Reed outcome tracking with seven 1-10 criteria.
- Local-first offline persistence.
- Personal similarity prediction against successful reeds.

## Current Architecture

- Frontend: Flutter (Android, iOS, macOS, Windows).
- State: Provider + ChangeNotifier.
- Storage: Local JSON store in app documents directory.
- Sync layer: Pluggable gateway stub for Firebase/Supabase integration.

## Run

```bash
flutter pub get
flutter run
```

## Try it in the browser (testers)

A live web build is deployed to GitHub Pages on every push to `main`:

**`https://<your-github-username>.github.io/<repo-name>/`**

The link will be printed in the `Deploy web build to GitHub Pages` workflow
summary in the **Actions** tab the first time it runs.

### One-time GitHub setup

1. Push this repository to GitHub.
2. Go to **Settings → Pages**.
3. Under **Build and deployment → Source**, choose **GitHub Actions**.
4. Push to `main` (or trigger the workflow manually under **Actions →
   Deploy web build to GitHub Pages → Run workflow**).
5. Wait ~3 minutes for the build to finish, then open the link above.

The web build is fully offline-capable for the session: cane samples, reed
evaluations, and photos are stored in browser local storage. Clearing site
data wipes the test data.

### Build the web version locally

```bash
flutter build web --release --base-href "/<repo-name>/"
# Serve the output to test before pushing:
cd build/web && python3 -m http.server 8000
# Open http://localhost:8000
```


## Data Model (MVP)

Each cane sample stores:

- Date of purchase
- Source with history suggestions
- Length (mm)
- Width (mm)
- Thickness readings (multiple points) and averaged thickness (mm)
- Inner gouge type (excentric / concentric / none)
- Mass (g, supplemental)
- Flexibility/Twist (deg)
- Applied Load (g, standard 200 g)
- Relative Stiffness (calculated)
- Natural Frequency (Hz)
- Lauritzen tone index (0-36)
- Buoyancy test (submerged length / non-submerged ratio)
- Hardness (optional; point-based, not exact)
- Notes (optional)

Each reed evaluation stores:

- Linked cane sample
- Response, Stability, Tone, Intonation, Flexibility, Projection, Resistance (1-10)
- Comment and optional longevity

## Version 2 Direction

- FFT-based resonance and overtone analysis.
- Advanced geometry normalization models.
- Optional density and hardness weighting experiments.
- Cloud sync/auth rollout with conflict handling.
