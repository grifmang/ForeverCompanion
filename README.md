# Forever Companion

Version 0.1.14-prototype — a WoW: Forever addon suite with five optional modules.

**Status:** Source has been checked with a Lua 5.1 syntax parser. Real-client loading, SavedVariables persistence, tooltip behavior, Legacy data and two-player synchronization still need verification. This is a prototype, not a launch-ready release.

## Install

The public source and release downloads are at [grifmang/ForeverCompanion](https://github.com/grifmang/ForeverCompanion).

For update checks, use [WowUp's Install from URL](https://wowup.io/guide/get-addons/overview):

1. Choose your **Forever** game installation in WowUp.
2. Choose **Get Addons → Install from URL** and paste `https://github.com/grifmang/ForeverCompanion`.
3. Install the addon with WoW closed. Use the repository URL, rather than a direct ZIP URL, so WowUp can discover later releases.
4. WowUp checks for updates periodically; **Check Updates** and **Update All** are also available. These are preview releases. If a future channel setting filters previews, select a channel that includes them. Verify that the selected destination is the release `_forever_` client.

The release ZIP ends in **`-forever.zip`** so WowUp can select the correct flavor. WowUp's upstream source supports Forever, but discovery and update behavior on a particular installation still need verification. If the client is not recognized, use the manual installation below. Avoid GitHub's automatically generated “Source code” archives; download the named Forever ZIP attached to a release.

Manual installation:

1. Close the game before installing new addon files.
2. Extract the ZIP so the folder is `ForeverCompanion`, containing `ForeverCompanion.toc` directly inside it.
3. Place that folder in your Forever release client's `_forever_/Interface/AddOns` directory.
4. Restart the game, enable **Forever Companion** on the character-selection AddOns screen, and enter the world.
5. Type `/fc`.

Do not nest it as `AddOns/ForeverCompanion/ForeverCompanion/`. The TOC targets interface 16001 provisionally. Source research targets product wowf/Camelot; actual loading/interface/API behavior still requires in-game verification with `/fc diagnostics`.

## Updates and notices

Every push to `main` builds a new numbered GitHub preview release, with an installable Forever ZIP and SHA-256 checksum. Friends using the repository in WowUp can discover it there. WoW cannot download or replace addon files while running; desktop updates load after a user-controlled reload/restart. Close the game when replacing files.

The addon announces only its installed version to the active group while Adventure Together sharing is enabled. If a current party, raid or instance member reports a newer version, it prints one notice per login/reload and points to this repository's releases. This is an unverified member report, not confirmation that GitHub published that version. It works without starting a group checklist, respects sharing/module opt-outs, and pauses during combat or chat restrictions. It never installs or executes an update.

Use **`/fc updates`** or Settings for your installed version and a copyable release link. No notice means no newer group version has been observed; it does not mean you have the newest GitHub release. The first version with this feature must be installed through WowUp or a release ZIP.

## Commands

| Command | Opens |
| --- | --- |
| `/fc` | Main window |
| `/fc legacy` | Legacy Compass |
| `/fc wallet` | Launch Wallet |
| `/fc items` | Keep or Sell? |
| `/fc quests` | Quest Helper |
| `/fc party` | Adventure Together |
| `/fc settings` | Module switches |
| `/fc updates` | Installed version and release information |
| `/fc help` | Command help |
| `/fc diagnostics` | Client build, capabilities and bounded recent errors |

Drag the window to move it. Escape closes it. Fields do not take focus automatically; press Enter or Escape to finish typing. Switch off any module in Settings without deleting its saved data.

## Quest Helper

When Quest Helper is enabled, it opens with the Quest and Map Log. **Route** and **Nearby** are available in the Objective Tracker even when no quests are watched. **Nearby** groups pickups by giver or map location. Select a pickup to open the map. When the work area is known, the list shows which quests can be done together. **Likely available** means you may still need a prerequisite. **Confirmed offer** means the native NPC dialogue recently offered the quest. Talk to the NPC to accept it.

**Route** organizes accepted quests by the location of their current objectives. Choose **Track** beside an area to start at its nearest known quest. The current target stays selected as you move, and the route advances when you finish its work in that area. Use **Focus** to select a particular quest and **Stop** to end the route. Finished quests move to **Turn in**. Instanced quests and quests without usable locations remain visible. A tilde marks an approximate straight-line distance. If the quest log is incomplete, expand its collapsed sections in Blizzard's quest log.

For wider pickup and objective coverage, separately install [QuestieDB Forever](https://github.com/Questie/QuestieDB/releases). Quest Helper also reads offers and map data from the game without QuestieDB. Coverage varies, especially for new Forever quests, and the add-on leaves missing locations unknown. A map guidance message explains if the client cannot place a pin or you already have another destination selected.

Focus and Track also watch the active quest in Blizzard's Quest Log and Objective Tracker. When the target changes or the route stops, Quest Helper clears only the watch it added during the current session. Untrack from Blizzard's tracker to stop the native watch for that quest. Select Focus again to resume it.

**Track Area** in the Objective Tracker lets you select or stop a route there, and the tracker shows your active target above the native objectives. Choose **Quest Log** to use the regular quest list until you close the log, or select a quest title to open its native details. Use the **Quest Helper** button or the quest log settings menu to return to the helper while the log is open.

In an active Adventure Together session, quest rows show party readiness and unknown reports, with your checklist progress at the bottom. The two modules can run independently. Quest Helper doesn't share your location, route or pickup list.

## Legacy Compass

Open the panel to load Blizzard's Legacy UI data. Search challenge names or categories, switch between all challenges and Next goals, pin goals using their checkboxes, and open Details for criteria. Next goals puts pinned unfinished challenges first, then readable progress. It does not estimate travel time or identify an optimal route.

The addon identifies Legacy challenges by their actual Legacy trait-currency reward. Completion follows Blizzard's character-earned flag; Legacy rewards contribute to account progression. It does not change Blizzard's achievement search/filter settings. Unknown, restricted or locked progress remains labeled unavailable. Last-observed values are labeled when reads cannot be refreshed.

Choose **Perk plans** to save a named plan. Manual mode lets you enter tree names, perk names, point counts, notes and a cap. The default manual cap of 16 is an announced beta reference, not a claim that current live data was read. Manual allocations are not verified against prerequisite paths. Live mode requires readable perk names, rank limits, unit point costs and the client's spending cap; unsupported data returns you to a clearly labeled manual option. Even live plans are a rank/budget planning aid, not proof every tree prerequisite is satisfied.

Plans are saved per character. They never spend or refund in-game points; use **Native Legacy UI** to apply your choices yourself.

## Launch Wallet

1. Visit a trainer or vendor and keep the native window open. Open `/fc wallet`: supported displayed gold prices appear automatically under **Trainer and vendor prices**.
2. Choose **Budget** on an offer. Vendor quantities are **bundles**, with the number of items per bundle shown; trainer quotes are one service. Names and prices are filled from the client rather than typed. Unknown, non-gold, buyback, pet-point and unsupported offers show a reason and cannot become invented zero-cost budgets.
3. As carried gold changes, current gold is allocated once across active goals in ascending ID order: older goals fund first. Each budget shows target, funded amount and shortfall; the header updates total reservations and available/estimated spendable gold.
4. Use **Finish** after completing a purchase or training goal; Reopen restores the reservation. Balance changes do not identify a completed purchase, so goals never auto-finish from money or bag changes.

Vendor goals refresh their price when the same NPC, item and bundle are observed in a complete, unambiguous catalogue. Editing an imported vendor goal changes bundle quantity while its unit price stays source-owned. A changed bundle/source or unreadable catalogue preserves the old quote as an estimate. A valid row in a partial catalogue can be explicitly budgeted after its exact row/item/price is checked again; it remains an estimate. Trainer services lack a durable service ID in the inspected API, so their prices are recorded historical quotes and do not silently reprice. Choosing Budget on a freshly observed trainer offer can explicitly update its matching quote.

Session balance-change counters show observed gold increases/decreases while the module is enabled, including transfers. They are net observations rather than attributed transaction receipts. Reload/module re-enable starts a new baseline; unreadable gaps are rebased and mark totals partial. No gold earned/spent during an unreadable gap is invented. Quotes show their NPC and observation time; saved price estimates and recovered read-only data are distinguished from current observations.

Expand **Custom gold goals** to keep using manual reservations: enter a name and target amount, then Reserve gold. These participate in the same funding order as imported goals. Caps are 100 budgets, 200 observed catalogue rows and 9,999 vendor bundles; each complete target is at most 1,000,000 gold.

Up to four fractional digits are accepted: `1.0001` means 1 gold and 1 copper. Distinct active reservations add together. Editing updates the same reservation. Finish releases its allocation; Reopen activates it again. Carried balance, total reserved, available-to-spend and shortfall refresh when money changes.

Money is not moved or locked, and the addon cannot prevent overspending. It uses only the current character's carried balance.

## Keep or Sell?

1. Open your own profession window and select a learned recipe.
2. Open `/fc items`, enter a **Number of crafts**, and choose **Track selected recipe**. Materials are pulled from the client's recipe schematic; there is no item-by-item entry. Counts mean craft executions, not output items: a recipe producing several items still consumes one craft from the goal per confirmed cast.
3. Gather, buy or move materials into carried bags: **Materials to keep** updates total need, carried count and shortage automatically. Shared ingredients across goals are combined before subtracting bags once.
4. Craft normally in the profession window. Confirmed successful player casts reduce remaining crafts exactly once. Failed/canceled casts, item purchases, sales, trades and bag losses do not count as crafts. Existing cast contexts cannot credit a goal created or edited mid-cast.

Tracking the same recipe updates its single goal. Edit changes remaining crafts (zero completes it); Remove stops its reservations. Finished goals release their material needs. If the client does not expose reliable per-craft cast identity, the count stays unchanged; use Edit to correct remaining crafts rather than relying on guessed bag changes. Batch/event semantics still require real-client verification.

The first version supports fixed, required, single-item reagent slots in own learned item/enchant recipes. Optional/alternative/variable/currency ingredients, linked/guild/NPC lists, leveled recipes, recrafts, salvage and gathering schematics return an explicit unsupported/unavailable reason. No alternatives are chosen or silently summed. Last complete snapshots survive reload for conservative reservations; open your profession to revalidate. Unverified metadata or read-only recovery withholds surplus. After a credited craft, surplus pauses until the next successful post-craft bag update/read, preventing old bag counts from appearing sellable.

Expand **Manual reservations and Always keep** for custom goals. Paste an item link/ID, quantity and reason to reserve extra materials; these add to recipe goals. Always keep creates an unconditional rule and never receives surplus advice. Quest/unknown items also receive conservative guidance.

The panel and supported item tooltips explain total needed, carried quantity and surplus across carried bags. A surplus is a total-inventory calculation, not permission to vendor the hovered stack. Quest or unknown item status receives conservative guidance. Item names may appear as an ID while metadata loads.

**Keep rules are advice, not sale protection.** The addon does not craft, buy, sell, delete, move, mail or trade items, and does not intercept Blizzard's Sell Junk button or another addon's selling. It reads the client's recipes; no external recipe/auction database is bundled. Bank and unobserved alt inventory are excluded. Limits: 50 goals, 32 distinct ingredients per recipe, 9,999 crafts per goal and 100,000 units of one ingredient per craft.

## Adventure Together

**Automatic quest progress** reads your active quest log and objective counts without entering quests manually. It works solo and inside or outside dungeons and raids. Use **My quests** for your own log, **Group quests** for the combined logs reported by joined addon members, and **Details** for each player's objectives. Shared quests are matched by quest ID. Ready for turn-in means complete in the log, not rewarded or turned in.

**Native quest log and Objective Tracker:** While grouped, the on-screen tracker shows a line such as **Group: 2/4 ready** beneath each supported watched quest, including the separate campaign section. Unknown reports and members without the quest are listed separately when present. The native map's quest list also shows a group-progress line under each quest entry; hover a quest there for a companion tooltip with member statuses. Blizzard's existing tooltip information stays separate. The denominator includes the whole active party, raid or instance group, including members who have not reported through the addon. Ready means ready for turn-in. Unknown, stale, partial and missing quests never count as ready. A complete, fresh log is required to say someone lacks a quest.

The native displays use the same sharing session and preferences as `/fc party`. With sharing paused they show your own progress and label other members unavailable; without an active session the quest-log hover details explain how the leader starts tracking. They hide when solo, during combat, or when Adventure Together is disabled, and update without opening `/fc`. The tracker respects Blizzard's watched list, collapse state, quest items, timers and available height; extra progress lines can reduce how many quests fit. Native titles, selection, shift-click tracking and quest actions remain Blizzard's. Compatibility with replacement quest UIs is not guaranteed; the custom Adventure Together panel remains available if native frames are unsupported.

Version 0.1.7 corrects the prior quest-log adapter to target Forever's actual Camelot map/quest-list UI. The legacy book-style layout used in the earlier preview is not the layout loaded by this client.

The addon reads the log. Accepting, abandoning, turning in and completing quests are player actions. Collapsed headers, unreadable data and unsupported objectives produce a partial or unavailable label. Expand native quest-log headers to expose missing entries. Unseen or stale quests remain unknown. The reader retains up to 100 quests and eight objectives per quest and labels larger or unsupported reads as partial. Names come from the client's data, with a quest ID shown while a name is unavailable.

You can still save a local session name/meeting point and up to 20 optional preparation tasks. These manual tasks and their readiness are independent from automatic quest progress. Local drafts remain separate from shared sessions.

To share with friends:

1. All participants install this update and keep the Adventure Together module enabled.
2. Join the same party, raid or instance group. **Automatically join group sessions** defaults on when no sharing preference has been saved; an existing sharing-off choice remains off.
3. The group leader clicks **Start group tracking as leader** or **Start as leader**. No manual tasks or title are required; a blank title uses Adventure Together. A manual draft is published only when its owner starts/publishes it.
4. Other addon users discover and join the leader's checklist automatically, including late arrivals and reloading members. They do not need to open the panel or click Join. A leader still chooses which local draft to publish.
5. Each participant's quests/objective counts update from their own log automatically. Optional manual tasks still use each player's own readiness checkboxes; unknown states remain unknown.

Uncheck **Automatically join group sessions** or use **Leave and pause sharing** to stop group sharing and automatic enrollment. That choice persists through reload and group changes; your local quest view still works. Re-enable it to join again. Joining shares quest IDs/status/objective counts, but never publishes your manual draft, inventory, gold or Legacy plans.

The leader edits the local draft, then clicks **Publish local draft** to publish a new revision. A changed revision clears manual readiness; automatic quest progress remains separate. Leaders advertise active sessions periodically and answer bounded discovery requests, so late participants join automatically. Missed or incomplete checklists retry with backoff; **Announce again** and **Request again** remain available for manual recovery. Incoming updates never overwrite local drafts.

Sharing automatically uses PARTY, RAID or INSTANCE_CHAT for the active group. An active instance group takes priority over a separate home party; messages are never broadcast to both. Entering or leaving a dungeon with the same group preserves the session. Converting that same party to a raid (or back) discards old-channel packets and recovers the checklist on the new channel.

Sharing is queued at a small fixed rate and pauses during combat or client communication restrictions. The client accepting a message does not prove peer receipt; joined participants are counted after their acknowledgements. Raid snapshot requests are combined into shared responses. An addon-only heartbeat every 60–74 seconds replays each sender's own reported readiness and helps expire stale participant readiness after two minutes. Late raid joiners may need one heartbeat to see previously reported readiness. Unreported readiness remains unknown. Heartbeats and unchanged recovery snapshots do not extend the four-hour user-activity lifetime of a session. No ordinary chat is sent.

Automatic quest updates use spare communication capacity, capped at two packets/second within the shared four-packet/second budget. Large logs and late arrivals can take a minute or more to converge. Quest presence/version manifests repair missing updates, and unconfirmed progress becomes stale after four minutes. Meaningful quest changes count as session activity; unchanged periodic traffic does not keep an idle session alive.

Leaving or replacing the group, switching between a home group and a separate instance group, changing leader, disabling the module, or session expiration closes shared state and peer quest data. Local quests are independently read again. Members automatically discover the new leader's active session when sharing is enabled; a new leader must start it. Reload preserves local drafts and sharing preferences; members recover the active session automatically, while leaders must start again. Ended, replaced or expired session IDs are remembered in a bounded list so delayed announcements do not immediately re-enroll a client into an old session. Re-enabling automatic joining clears that suppression. If a leave packet cannot be sent during a restriction, peers expire stale readiness/quest progress; their client cannot instantly know sharing was disabled.

## Saved data and privacy

`ForeverCompanionDB` is stored in WoW's normal SavedVariables files. Module switches and window position are account preferences; goals, material needs, plans and local drafts belong to a character GUID. Unsupported schemas preserve the original data and disable writes. If normalization finds invalid records, the entire original save remains intact and the recovered view becomes read-only. A bounded in-memory quarantine aids diagnosis; it is never the only preserved copy. Restore a backup with the game closed before resuming edits.

Automatic group joining is enabled by default unless a saved sharing-off preference exists. Session labels, meeting point, checklist definitions/revision, manual readiness, quest IDs, quest status and objective counts/finished flags go to participating current group clients. Installed addon versions can also be announced to the active group before a shared session starts. Quest titles and objective text are resolved locally, not sent. Discovery messages contain no checklist text. Full quest logs and peer progress are ephemeral; one persistent counter allocates sender generations to reject pre-reload packets. Gold, bag contents and Legacy plans are not shared. The addon makes no web request and requires no login; an optional desktop manager contacts GitHub separately.

To back up data, close the game and copy its `ForeverCompanion.lua` SavedVariables file. Do not edit it while the game is running. Removing the addon folder stops the addon; it does not remove saved data. Restore a backup with the game closed.

## Validation and reporting

See [ACCEPTANCE.md](ACCEPTANCE.md) for the real-client acceptance walkthrough. Report the client build/interface from `/fc diagnostics`, the module/action, and the bounded diagnostic output. Do not post account credentials or full private logs.

See `VERIFICATION.md` for completed static checks, review corrections and remaining compatibility gates.

The prototype is not verified by a simulated WoW runtime. A real Forever character and a second real party client are required for the remaining compatibility checks. Static parsing and a successful release build do not establish in-game behavior.

## Publishing changes

Push commits to **`main`**. The **Publish Forever prototype** GitHub Actions workflow validates Lua syntax and the file allowlist, then stamps staged copies of `Core.lua` and both TOCs with a version such as `0.1.8-prototype.12`. The numeric suffix is the workflow run number. Source files keep their base version; the built package has one matching installed version throughout.

Only the TOC-listed Lua files and the public addon documents are packaged under `ForeverCompanion/`. Development tools, Git history, local reports, credentials and SavedVariables are excluded. Each release is tagged at the triggering commit. An existing version must never be silently overwritten. Keep the workflow identity when continuing its build numbers, or increase the source base version when replacing the workflow.

For local static validation, use `npm ci --ignore-scripts` followed by `npm run check:lua`. Build a curated local package with `pwsh -File Tools/Build-Release.ps1 -OutputDirectory dist`. Neither command starts WoW or changes an installed addon.

## Source and license

Original Lua source is included and licensed under MIT. API compatibility was researched using Blizzard's Forever UI source mirrored in [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever), and the [client API export metadata](https://github.com/Atraeau/WoW-Addons/blob/main/docs/api/README.md). The optional [QuestieDB consumer API](https://github.com/Questie/QuestieDB/blob/master/docs/api.md) reads an independently installed Forever dataset. No third-party addon source, dataset or runtime library is bundled. The development-only Lua parser is excluded from addon releases.
