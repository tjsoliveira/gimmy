# Changelog

What changed in Gimmy, newest first. Every commit adds a line here, under that day's date.

## 2026-11-25

- Changelog created, with the history since the first version.
- Changelog and README now in English.
- CLAUDE.md and DESIGN.md now in English, like the rest of the repo.

## 2026-11-24

- README: makes it clear this is a personal app, just for tracking my workouts, and drops the install and setup instructions.

## 2026-11-23

- CI: each build was published as a release, with a source for SideStore. Undone the same day: updating stays manual, through Sideloadly.

## 2026-11-21

- Plates as a load unit, alongside kg and lb: a KG | LBS | PLACAS picker, − and + one plate at a time, +1 to +5 shortcuts and drops suggested in whole plates.
- Volume: each plate counts as 4.5 kg (an estimate), in the app and in the spreadsheet's volume formula.
- Tests: fixes the expected 1RM for plates.

## 2026-11-20

- Reorder sets by touching and dragging. A set moves together with its drops or mini-sets, and the others keep their order.
- The workout setup follows the new order, so the next copied workout comes out the same.
- When finishing a workout that differs from its setup, the app asks whether to build a new routine from it (a new version, in effect from the next day).
- Routine integrity: only one routine per muscle group is in effect on any day; when two overlap, the older one ends the day before the new one starts.

## 2026-11-18

- Drop sets: drops are entered together with the set, in the same panel, with the load and reps of each one and the pause between them.
- Drops and rest-pause mini-sets use the same large controls as the set, picking the part from a row at the top of the card.

## 2026-11-16

- History: today's workout, while not finished, shows "em andamento" (in progress) instead of the volume change.
- README screenshots: the rest bar only shows in the first one.
- Removes the data layer for the progress screen, which was never built.
- README screenshots updated.
- Buttons to pause and resume the workout clock.
- README screenshots updated.
- Button to collapse the open exercise.
- Rest-pause: a single pause, saved on the set and on every mini-set except the last.

## 2026-11-12

- Rest-pause set type.
- Brings over the remaining changes from the Registro de Treino artifact.
- Kinetic Dark Minimal look.
- Quick entry card pinned to the bottom of the workout screen (undone the same day).
- Data layer for the progress screen (removed on Nov 16).
- A set is chosen by tapping its row.
- The set editor opens as a panel again.
- Removes the lock from exercises not started yet.
- Editor and list: finished sets stand out more, unsaved values are kept when the panel closes, the rest timer keeps running while editing, the whole rest-pause in one panel and a number pad for rest. First unit tests.
- Total workout timer.
- Logged sets stay in sync with the spreadsheet, even after a connection failure.
- Setup for workouts, exercises and sets, with validity periods. The picker only shows workouts in effect, and a day with no workout starts with a copy of the configured workout, without the loads.
- README: personal project notice and screenshots.
- The last exercise closes with its check when all its sets are logged.
- README screenshots updated.

## 2026-11-11

- First version: a native iPhone app (SwiftUI) for Registro de Treino, reading from and writing to the Controle de Treinos spreadsheet.
