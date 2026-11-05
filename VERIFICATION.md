# Verification and compatibility

Forever Companion is a prototype for WoW: Forever/Camelot, with provisional interface16001. Source analysis follows Blizzard UI code mirrored in the Forever branch of Gethe/wow-ui-source. The mirror may differ from an installed client.

## Automated checks

The release workflow parses every TOC-listed Lua file using Lua5.1 grammar without executing addon code. It validates matching flavor TOCs and base version, builds from a fixed distribution allowlist, stamps one build version into staged Core.lua and TOCs, and inspects the ZIP for a single ForeverCompanion root and matching file bytes. GitHub builds run on trusted main commits; publication is separately permissioned. The release asset includes a SHA-256 sidecar.

These checks establish source syntax and package integrity. They do not establish native API compatibility, in-game rendering, combat safety, SavedVariables behavior or two-client synchronization. No unit, integration, component or snapshot tests or mocked WoW runtime substitute for those checks.

## Current source boundaries

- Quest logs are read automatically. Partial/collapsed/restricted observations remain unknown; completion means ready for turn-in. Remote status is bound to current roster/session/channel/member identity and expires. Normal/campaign Objective Tracker modules use native-managed lines; Camelot's map quest list uses pooled quest entries, measured spacing and separate owned tooltips.
- The earlier0.1.6 adapter and book-style preview incorrectly assumed Vanilla QuestLogFrame was loaded. Actual Camelot flavor rules exclude it. Version0.1.7 corrected the target to Mainline QuestMapFrame with Camelot overrides. The old preview is not evidence of the client's layout.
- Recipe material goals use fixed own learned recipe ingredients. Confirmed own craft identity controls progress; unconfirmed bag changes do not count as crafts. Unknown/quest/read-only metadata withholds sellable surplus.
- Wallet quotes come from readable open trainer/vendor windows. Trainer quotes remain historical; matched vendor bundles may reprice. Gold changes update ordered funding but do not identify a completed purchase.
- Peer version notices accept only bounded canonical stable/prototype versions from the active group while sharing is enabled. No newer claim means no observation, not proof of being current. A fixed repository URL is displayed; no peer-provided URL or code is used, and no install or HTTP request occurs in-game.

## Remaining real-client checks

Follow ACCEPTANCE.md with one Forever character and a second real client. Verify native map/tracker loading, animations, pool reuse, long titles, available-height behavior, combat hide/restore, sharing opt-outs, stale reports, party/raid/instance changes, recipe/craft identity, NPC prices and ordinary money changes. No unintended resource spending is required.

For distribution, verify WowUp selects the Forever profile, installs the named -forever.zip release asset into the right AddOns folder, and detects a later release. Upstream WowUp supports GitHub repository URLs and a Forever flavor; this is not an end-to-end guarantee for every user's desktop installation. Manual ZIP installation is the fallback.

Primary sources: [Forever UI load rules](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc), [quest tracker](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_QuestObjectiveTracker.lua), [quest-map UI](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua), [WowUp GitHub installation guide](https://wowup.io/guide/get-addons/overview), [WowUp GitHub provider](https://github.com/WowUp/WowUp/blob/master/wowup-electron/src/app/addon-providers/github-addon-provider.ts).
