# DESIGN.md — Kinetic Dark Minimal

Gimmy's design system: high density, dark mode, inspired by Linear and precision tools.
The tokens below are implemented in `Gimmy/App/Theme.swift`.

```yaml
name: Kinetic Dark Minimal
description: A high-density, dark-mode design system tailored for gym tracking and workout analytics, inspired by Linear and high-precision developer tools.
version: 1.0.0

theme:
  color_mode: DARK
  font: Inter
  roundness: ROUND_EIGHT
  accent_color: "#5E6AD2"

colors:
  # Base surfaces & Elevation
  surface: "#131315"
  surface-dim: "#0E0E10"
  surface-bright: "#39393B"
  surface-container-lowest: "#0E0E10"
  surface-container-low: "#1C1B1E"
  surface-container: "#222126"
  surface-container-high: "#262529"
  surface-container-highest: "#323135"

  # Borders & Dividers
  border-subtle: "rgba(255, 255, 255, 0.06)"
  border-default: "rgba(255, 255, 255, 0.10)"
  border-strong: "rgba(255, 255, 255, 0.16)"

  # Text & Content Hierarchy
  text-primary: "#F4F4F5"
  text-secondary: "#A1A1AA"
  text-muted: "#71717A"
  text-inverse: "#0E0E10"

  # Brand & Primary Actions (Linear Electric Indigo)
  primary: "#5E6AD2"
  primary-hover: "#4E5AC0"
  primary-container: "rgba(94, 106, 210, 0.15)"
  on-primary: "#FFFFFF"

  # Semantic Workout Set Types
  set-warmup: "#F59E0B"     # Amber / Warm-up
  set-normal: "#71717A"     # Neutral gray / Regular set
  set-dropset: "#A855F7"    # Electric purple / Drop set
  set-restpause: "#14B8A6"  # Teal / Rest-pause (added in the app; not in the original design)
  set-failure: "#EF4444"    # Coral red / Muscle failure

  # Status & Indicators
  status-success: "#22C55E" # Green / Done and streaks
  status-warning: "#F59E0B" # Amber
  status-danger: "#EF4444"  # Red

radii:
  none: "0px"
  xs: "4px"
  sm: "6px"       # Small badges, increment shortcuts (chips)
  md: "8px"       # Secondary buttons, inputs, pills
  lg: "12px"      # Main action buttons, inner cards
  card: "16px"    # Main exercise cards and modals
  full: "9999px"  # Pills, status tags and avatars

spacing:
  2xs: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "24px"
  2xl: "32px"
  3xl: "48px"

typography:
  font_family: "Inter, -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif"
  numeric_font_family: "'SF Pro Rounded', Inter, sans-serif"

  scales:
    display:      { size: "28px", weight: "700", line_height: "1.2",  tracking: "-0.02em" }
    title_large:  { size: "20px", weight: "700", line_height: "1.3",  tracking: "-0.01em" }
    title_medium: { size: "17px", weight: "600", line_height: "1.35", tracking: "-0.01em" }
    body:         { size: "15px", weight: "400", line_height: "1.4" }
    body_bold:    { size: "15px", weight: "600", line_height: "1.4" }
    caption:      { size: "12px", weight: "500", line_height: "1.3" }
    caption_bold: { size: "10px", weight: "700", line_height: "1.2", tracking: "0.05em", text_transform: "uppercase" }

components:
  card:
    background: "surface"
    border: "border-subtle"
    radius: "card"
    padding: "md"

  primary_button:
    background: "primary"
    text: "on-primary"
    radius: "lg"
    height: "48px"
    font_weight: "600"
    shadow: "0 4px 14px rgba(94, 106, 210, 0.3)"

  secondary_button:
    background: "surface-container-high"
    text: "text-primary"
    border: "border-default"
    radius: "md"
    height: "36px"

  set_badge:
    width: "34px"
    height: "34px"
    radius: "full"
    border_width: "1.5px"
    font_weight: "700"
```


## Implementation notes

The app's UI is in Portuguese; labels on screen are quoted as they appear, with a translation where it helps.

- **Font:** the app uses SF Pro (the system font) instead of Inter, as in the reference components; numbers use SF Pro Rounded.
- **Workout screen:** focus on the current exercise. The exercise with sets still to log stays open; tapping a set opens the edit panel (Quick Entry + set options); the others show as compact cards (empty circle for not started, half circle for in progress, check for done). Tapping a compact card opens that exercise; exercises can be done in any order. When every set of the workout is logged, all exercises close with the check, the last one included. The open exercise has an up-arrow button at the corner of its title that collapses it: then all stay closed until you tap one.
- **Reordering sets:** touching and holding a set and dragging it over another puts the dragged one in its place; the others keep their order. A set moves together with its drops or mini-sets (only the main set can be dragged), and the target is highlighted in indigo. Holding without dragging still opens the set's menu. The spreadsheet rows don't move: their content does (type, load, reps, notes and rest). A set ending in a drop or rest-pause with no following part has to stay last. The exercise's setup (Rotinas tab) follows the new order when the workout has the same number of sets as the setup, so the next copy comes out the same; an exercise with no configured sets already copies the last workout. In VoiceOver, the "Subir série" (move set up) and "Descer série" (move set down) actions do the same.
- **Plates:** besides kg and lb, an exercise can be measured in plates (the number of plates on the machine's stack). The panel's picker becomes KG | LBS | PLACAS and, in plates, − and + step by 1 and the shortcuts are +1 to +5. In kg volume, each plate counts as 4.5 kg (an estimate: these machines don't show the weight); 1RM, the comparison with last time and records keep working, in plates.
- **Routine integrity:** only one routine per muscle group is in effect on any day. The group is the routine's name, ignoring accents, case and spaces (Braços = bracos). Whenever a routine is saved (created, validity changed, new routine from the workout), the app checks all of them, including ones edited outside the app: when two of the same group overlap, the one that started earlier now ends the day before the other, and the notice says what changed. It doesn't save, and explains why, if the routine being saved would have to be shortened or if both start on the same day (or neither has a start).
- **New routine from the workout:** when finishing today's workout, if it changed from what "Começar treino" (start workout) copies (set type, sets or exercises added, removed or reordered; the load and reps done don't count), the app asks "Montar uma rotina nova?" (build a new routine?). On yes, the current setup ends today and a new version with the same name, matching the workout, takes effect from tomorrow. Sets that already existed in the same position (3, 3.1) keep their rep target; new ones use today's reps. Notes and target rest come from the current setup.
- **Set options:** type, repeat the last one, rest, clear and remove sit in the edit panel, below Quick Entry, and also in the long press on each set.
- **Sets:** done sets get a `surface-container-high` background, a badge filled with the type's color and a green check; sets with values filled in but not saved show as "pré-definida" (preset) in indigo.
- **Workout time:** a timer at the top of the workout screen while today's workout is open; it goes away when the workout is finished. The "Pausar" (pause) button stops the count (the time stays still in gray, with "Pausado") and "Continuar" (resume) counts again without the paused time. Logging a set while the timer is paused resumes it.
- **Drop and rest-pause:** in the panel, choosing Drop or Rest-pause opens the set's parts (drops or mini-sets) and a pause field (− value +, in 5 s steps). At the top of Quick Entry, a row of buttons (`3 · 3.1 · 3.2 · +`, each with load×reps) picks what the large steppers and shortcuts edit: the set or one of its parts, selected in indigo. Below, the parts show as a large summary; tapping one opens that part at the top. In rest-pause mini-sets, the rep shortcuts are low (2 to 6). A new drop comes with about 20% less load, rounded to the unit's step, and the same reps; a new mini-set repeats the load. Saving writes the set and its parts at once, with the pause on all of them but the last. The starting pause is the one from the last time the exercise had that type; with no history, 10 s for drop and 15 s for rest-pause.
- **Set panel:** load and reps at full width (56 pt keys, 40 pt numbers), type, drops or rest-pause mini-sets, repeat the last one and rest; the rest bar stays visible in the panel.
- **Setup (*Configurar*):** list of workouts grouped into "Vigentes" (current), "Programados" (scheduled) and "Encerrados" (ended). In a workout: name and validity (optional start and end) and the exercises, which are reordered in "Reordenar" and removed with a swipe. In an exercise: one row per set with the type badge, the type menu and − reps +, plus target rest, unit and notes. With unsaved changes, the back button becomes "Descartar" (discard) and "Salvar" (save) stays pinned at the bottom.
- **History:** today's workout, while not finished, shows "em andamento" (in progress) in indigo instead of the volume change, which only shows after "Finalizar" (finish).
- **Exercise notes:** shown on the workout screen, right below last time, with an info icon.
