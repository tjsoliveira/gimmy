# Gimmy — instructions for Claude

An iPhone app (SwiftUI) for logging workouts. The Google spreadsheet "Controle de Treinos" is the database (tabs Registro, Rotinas, Exercícios), read and written through the Sheets API. See DESIGN.md for the look. It is a personal app: the README has (and must not have) no install instructions. The IDs (Bundle ID, Google client, spreadsheet) live in `Config/Secrets.xcconfig`, outside git (template in `Config/Secrets.example.xcconfig`), and in the GitHub secrets used by CI.

## Rules

- **Regression tests are mandatory.** Every change to core functionality comes with unit tests in `GimmyTests/` (XCTest), new or updated. Core = reading the spreadsheet (`Parse`, `DayKey`, `RestInput`), workout rules (`Ledger`: numbering with drop/rest-pause, 1RM, status, records, kg/lb volume, building the workout, sessions and stats), drafts and rest-pause (`Drafts.swift`), configured workouts and validity (`Plan.swift`: planned sets, versions by date, copying the workout), the workout screen's focus (`Focus.swift`), reordering sets (`SeriesOrder.swift`) and a new routine from the workout (`NewRoutine.swift`).
- Keep testable logic out of the views and out of `AppModel` (which talks to the network): pure functions in `Model/`, called by `AppModel`.
- CI (`.github/workflows/build.yml`) runs the tests before building the IPA; the IPA only comes out if they pass. There is no Swift compiler in the cloud environment: check the result on GitHub Actions after pushing.
- **Changelog:** every commit adds a line to `CHANGELOG.md`, in the same commit: `python3 .github/scripts/changelog.py "what changed"` (puts the line under today's date, São Paulo time). Write one sentence saying what changed for someone using the app. This applies to every commit, including docs-only or CI-only ones; the screenshots workflow already does the same for its own commits.
- **Language:** everything in the repo is in English: docs, the changelog, commit messages and code comments. Only the app's UI is in Portuguese, along with the spreadsheet's own names and values (tabs, columns, set types).
- Don't add features that weren't asked for.
- Look: follow DESIGN.md (Kinetic Dark Minimal) and the tokens in `Gimmy/App/Theme.swift`.
- The spreadsheet doesn't change format without agreeing first: the app uses the columns that already exist, plus J (Tipos), K (Início) and L (Fim) in the Rotinas tab. Columns D and E of Rotinas are formulas and are never written. The Unit (D) column of the Exercícios tab takes kg, lb or placas (plates); in kg volume, each plate counts as 4.5 kg (an estimate), in the app and in the spreadsheet's formulas.
