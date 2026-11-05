# Changelog

## 0.1.8-prototype — GitHub distribution and update notices

- Added automated, numbered GitHub preview releases on pushes to main, with curated Forever-flavor ZIPs and SHA-256 checksums suitable for WowUp's repository URL installation.
- Added sharing-gated installed-version announcements and a bounded in-game notice when a group member reports a newer version. Reports are unverified; the addon never checks GitHub or installs code.
- Added `/fc updates` and release information in Settings. The first alert-capable update requires installation outside the game.

## 0.1.7-prototype — November 4, 2026

- Added group-ready, unknown and missing-quest counts beneath watched quests in the native Objective Tracker. Native layout reserves the line height and retains objective, timer, quest-item and collapse behavior.
- Corrected native quest-log integration to the actual Camelot map/quest-list UI. The 0.1.6 adapter and book-style preview targeted a legacy UI excluded by this client's load rules.
- Reused existing session, privacy and freshness rules without adding network traffic, saved data, quest actions or watch-list changes. Added-line cleanup handles native pool reuse and defers relayout during combat.
- Static/source/package checks do not replace real-client verification of native layout, animations and third-party addon coexistence.

## 0.1.6-prototype — November 4, 2026

- Adventure Together adds compact ready/roster counts beside native quest entries, a selected-quest summary beneath the title, and companion per-member hover details.
- Unknown reports and members without a quest are distinguished from unfinished quests. Fresh complete manifests are required for absence claims; unrelated quest packets cannot keep old absence observations current.
- Native hooks follow scrolling/collapsing rows and restore addon-owned presentation when disabled or solo. Combat defers native presentation changes. No quest actions, new sharing setup or additional network traffic.
- Source/static/package checks only; real-client native layout, hooks and group behavior require verification.

## 0.1.5-prototype — November 4, 2026

- Added automatic trainer/vendor price observation and one-click budgets using the client's actual gold quote and vendor bundle size.
- Added watched vendor repricing for matching NPC/item/bundle identities, dated trainer quotes, bundle edits and conservative cached/partial price handling.
- Added per-goal funding/shortfalls from one current balance, with older goals funded first, and bounded session balance-increase/decrease counters with gap rebasing.
- Preserved manual gold goals, source-owned imported prices, explicit Finish/Reopen and full-original saved-data recovery.
- No purchase, training, gold transfer or spending attribution actions were added. Native price/event compatibility remains a real-client verification gate.

## 0.1.4-prototype — November 4, 2026

- Added recipe-driven crafting goals: select an own learned recipe in the native profession window and track a number of crafts; required materials populate automatically.
- Combined recipe and optional manual reservations into one material/tooltip calculation. Carried bags update shortages as materials change.
- Correlated confirmed own craft casts to the goal revision captured before crafting, with duplicate/failure protection. Successful casts reduce remaining crafts and pause surplus until bag counts update.
- Added saved goal validation and conservative cached/read-only handling. Unsupported recipe variants stay explicit rather than silently guessing ingredients.
- Moved recipe tracking to the main Keep or Sell workflow; retained manual reservations and Always keep as expandable options.
- Updated release-client installation instructions. Static source/package checks do not establish actual profession API, batch crafting or UI compatibility.

## 0.1.3-prototype — November 3, 2026

- Added automatic own quest-log and objective reading, My/Group quest views and per-member progress details without entering quests manually.
- Added bounded, sender-owned quest progress sharing independent from manual checklist revisions; current members' quest IDs match automatically.
- Distinguished ready-for-turn-in, partial, unknown and stale observations. Partial reads preserve unseen quests; confirmed full manifests/removal updates reconcile membership.
- Added a blank-title default and Start group tracking as leader action so untouched manual drafts do not block quest sharing.
- Preserved sharing-off preferences and local-only quest tracking. No quest-log writes or automatic quest actions.
- Kept source/packaging validation separate from the unavailable real-client E2E gate.

## 0.1.2-prototype — November 3, 2026

- Group members with Adventure Together enabled now discover and join the leader's active checklist automatically, including late arrivals and reloading members.
- Automatic joining defaults on when there is no saved sharing preference. Saved sharing-off choices remain off; Leave and pause sharing turns off automatic enrollment until re-enabled.
- Added bounded discovery, coalesced leader announcements and automatic checklist recovery with retry backoff. Duplicate announcements preserve readiness; old sessions are remembered in a bounded retired list.
- Preserved leader-controlled checklist publication and each member's manually reported readiness. Local drafts are never published by joining.
- Processed owner session-end messages during synchronization so members stop recovery when a leader ends the session.
- Static checks only; real-client automatic enrollment and multiplayer behavior remain unverified.

## 0.1.1-prototype — November 3, 2026

- Extended Adventure Together's manual quest checklists and readiness sharing to raids and instance groups, using the active group's channel and full roster.
- Preserved sessions when zoning with the same group and recovered queued sharing after same-group party/raid conversion. Switching to a separate group requires starting or joining again.
- Bound queued traffic and invitations to the current group lifecycle, category and leader identity, including direct leave messages.
- Combined raid snapshot requests, coalesced readiness replays and staggered heartbeats to bound group-size amplification.
- Updated real-client acceptance steps. Source/static verification does not establish in-game or multiplayer compatibility.

## 0.1.0-prototype

- Added four optional modules in one native WoW window with schema-versioned SavedVariables.
- Added Legacy challenge pinning and manual/client-data perk plan editing.
- Added current-character gold reservations using integer copper arithmetic.
- Added goal-based material quantities, unconditional Keep rules and item tooltip advice.
- Added persisted local adventure checklists and opt-in leader-owned party sessions with explicit joining, revision validation and bounded messages.
- Preserved the full original save when invalid data is recovered; the recovered view is read-only.
- Added missed-revision recovery and sender-owned readiness replay for late joiners, without extending session lifetime through heartbeats.
- Matched Legacy character completion flags and handled unavailable live perk data explicitly.
- Targeted Forever beta interface 16001 provisionally. Real-client and multiplayer verification remains outstanding.
