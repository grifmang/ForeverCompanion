# Forever quest helper implementation plan

> **For agentic workers:** Use the Superpowers execution workflow and track these steps. The repository's live E2E-only policy controls verification.

**Goal:** Pick up compatible quests nearby, work through an area in proximity order, and see Adventure Together progress in the same HUD.

**Architecture:** Share the existing quest observer between two independent consumers. Keep the route and optional data adapter independent of the native HUD presentation and isolate native visibility and waypoint ownership.

**Tech stack:** Camelot 16001, Lua 5.1, WoW frames and client APIs, optional separately installed QuestieDB.

**Spec:** [Quest helper design](../specs/2026-11-05-quest-helper-design.md)

## Constraints and review focus

- Keep native quest log and map, protect combat and gameplay actions, and default replacement off until launch-client acceptance. An explicit preview control enables reversible live testing.
- Never infer distances across unrelated maps, turn-in readiness from a partial snapshot, or arbitrary quest eligibility from database presence. Preserve native watches and restore owned guidance only.
- Preserve independent toggles, party protocol and privacy boundaries. No new network messages or bundled quest data.
- Only real-client end-to-end acceptance, static Lua parsing, and release packaging. Do not introduce or run unit or integration tests.

## Work

- [x] Share `FC.Quests` lifecycle and events between Adventure Together and `quests`. Add saved route view and area, module settings and launcher. Keep prior observations when collapsed quest headers make the log incomplete.
- [x] Add `FC.QuestData.Points(record, phase)` and `Nearby(mapID)` for supplemental points and pickup candidates. Use QuestieDB consumer contract, filter readable restrictions, and retain confirmed gossip and native map offers with no provider.
- [x] Add `FC.QuestRoute` sections, native waypoints and map conversion, nearest selection, sticky target, manual selection and turn-in transitions.
- [x] Add native themed `FC.QuestHUD` and replacement controls, native details and map guidance, party overlay and fallback for protected or special native objectives.
- [x] Update TOCs and static/distribution allowlists. Run Lua parsing and build the release ZIP.
- [ ] Run the `ACCEPTANCE.md` leveling route and the second-client scenario. The local Forever client was in active play and was left untouched; QuestieDB was not installed. Native replacement stays off by default.
