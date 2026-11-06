# Forever Companion real-client acceptance

Release: 0.1.11-prototype builds. **This is a walkthrough, not evidence of an in-game pass.** Static syntax and packaging results are reported in VERIFICATION.md inside the addon folder.

Use one Forever release character and one additional real client for party sharing. Reuse those two characters throughout; no device matrix or lower-level harness is required.

## Load, UI and persistence

- [ ] Enable Forever Companion, enter the world and run `/fc diagnostics`. Record actual version, build and interface; expected provisional interface is 16001.
- [ ] Open all five module tabs and Settings without Lua errors. Drag the window, close with Escape, reopen, reload, and verify its location and module switches persist.
- [ ] Toggle a module off and on. Its data remains, its behavior stops while disabled, and other modules remain usable.
- [ ] With the game closed and the suite's SavedVariables backed up, change only its schema field to a newer number. Re-enter and confirm the original root is preserved read-only. Restore the backed-up file with the game closed. Skip this destructive fixture step if a safe backup cannot be made; record the gap.
- [ ] With a separate backed-up fixture, introduce invalid records, including more than 20 invalid entries and malformed draft fields. The recovered view is read-only and the entire original SavedVariables root remains intact. Restore the backup with the game closed.

## GitHub distribution and version notices

- [ ] In WowUp, select the Forever release installation, install from the repository URL, and verify the destination and installed version. After an ordinary later main push publishes a new numbered preview, confirm Check Updates detects it. Use the named `-forever.zip` release asset for manual fallback; never use the automatic source archive as the install package.
- [ ] Run `/fc updates` and open Settings. Installed version and the fixed release link are visible. With sharing enabled, group two real clients on different supported builds: the older one eventually receives one clearly labeled member-reported newer-version notice, even without a shared checklist. Newer clients do not claim a downgrade is needed. Unchanged heartbeats, session restarts and group churn do not repeat the notice during the same login/reload.
- [ ] Pause sharing or disable Adventure Together, then join/rejoin: version traffic and notices stop along with other sharing. Combat/restrictions defer traffic. No credentials, external request, download, install, quest action or ordinary chat transmission comes from the in-game notice.

## Quest Helper — one leveling route

- [ ] With Quest Helper enabled, open the Quest and Map Log and verify the helper opens automatically. Choose Quest Log, verify the stock list stays open for the current visit, then close and reopen the log. Check that Quest Helper returns automatically and that opening native quest details still shows those details. With no watched quests, confirm Nearby is available from the tracker. Compare Nearby offers with a nearby NPC, then accept an offer and check it moves into Route. If QuestieDB Forever is available, check that two pickups from different givers can show a shared work area.
- [ ] Use accepted quests with two separate work areas. Verify the list groups by objective destination rather than by quest giver. Track an area and compare the first target with known nearby positions. Move toward another quest without finishing the current one; the target stays selected. Complete the work for one quest, check that the nearest remaining quest is selected, and check that the finished quest appears in Turn in. When only this area's work is complete, keep the quest in its other section. A quest without coordinates remains visible.
- [ ] Open quest details, place a pickup or turn-in map marker, focus a quest manually and stop the route. Verify a pre-existing user pin is retained, and prior quest guidance is restored only if Quest Helper still owns the active selection. Try native quest POIs on and off without changing unrelated settings. Collapse a Blizzard quest log section; hidden entries must not be treated as completed or abandoned.
- [ ] Open Route and Nearby from the native Objective Tracker. Use Track Area, verify the active target appears at the top of the tracker and check that objectives do not overlap the controls. Collapse and expand the tracker, open a quest detail from the helper, return to the native quest list, switch map tabs, and disable and re-enable Quest Helper. Verify the quest log search width, native quest items and ordinary objective controls remain usable after disabling and after combat.
- [ ] Reuse the same quests with a second Forever character in Adventure Together. The same route row shows updated readiness, unknown reports and the checklist link. Disable Adventure Together and verify solo routing continues; turn off Quest Helper and confirm native Adventure Together annotations resume. Record unsupported data/client cases rather than substituting a mock.

## Native quest log and Objective Tracker — one focused group scenario

- [ ] Track two or three quests using Blizzard's own controls before this scenario. With two addon users in one active sharing session, close the map and `/fc`: each visible watched quest in the on-screen Objective Tracker has a Group ready/roster line. Change ordinary quest progress and confirm it refreshes without opening either panel. Distinguish ready-for-turn-in from turn-in/removal, unfinished, unknown and a freshly confirmed missing quest.
- [ ] Reuse the same quests while collapsing/expanding the native tracker, changing the watched list/order, and resizing the tracker through normal client controls. Include a campaign quest if one is naturally available; its separate section shows the same group count. Hide/show the tracker with unchanged progress and confirm the lines return. Native title clicks, shift-click, quest-item buttons and any naturally available timer/progress bar retain their behavior. At the height limit, group lines reserve space and quests truncate normally; there must be no repeated layout loop, overlapping block or count on a recycled quest block.
- [ ] Enter/leave combat, disable Adventure Together while in combat, then leave combat and re-enable it. Only addon progress lines disappear; their reserved space is reclaimed after safe native relayout. End the group, pause sharing, reload when convenient, and if naturally available convert party/raid or zone into an instance. All-roster counts follow the active group; stale/left members never count as ready. Cached turn-in animations may briefly retain native spacing but must not display old group readiness. No intentional resource spending is required.

- [ ] Use the release client with two addon users in one group and at least one shared quest. Start group tracking once as leader. Open only Blizzard's quest log: group-progress lines under quest entries appear without opening `/fc` on the other client. A ready-for-turn-in member increases the numerator; actual turn-in/removal is not counted as ready. Hover preserves Blizzard's nearby-party information and shows clearly labeled member readiness in a companion tooltip.
- [ ] Scroll a populated list; collapse/expand headers; select different quests; include a long title, native quest tag and watched checkmark. Counts follow stable quest IDs and never appear on headers or overlap titles/tags/checks. Chat links, normal selection, shift-click tracking and detail/reward scrolling keep working. Group lines stay beneath each entry's native content and do not cover objectives.
- [ ] If a non-reporting member is available, verify it increases the roster denominator and unknown count. A fresh complete report without the quest shows without quest; missing/partial/stale reports remain unknown. Stop one client's reporting without unrelated game actions; after four minutes its progress becomes unknown without reopening either panel. If its complete manifest alone stops arriving, unrelated quest packets must not keep absent quests confirmed.
- [ ] Enter combat, then leave it: addon-owned native group lines/details hide and return safely. Pause sharing, disable/re-enable Adventure Together, leave the group, and reopen the log. Paused sharing explains the missing peers; disabling or going solo restores the native presentation. Re-enable while the log is already visible, and verify lazy native frame loading/reload when convenient.
- [ ] If naturally available, reuse the same clients after party/raid conversion or instance zoning: denominator follows the active group and replaced/left members disappear. Check native integration alongside the player's existing quest UI addons; unsupported/replaced frames may omit native annotations while `/fc party` remains usable. Record actual build and all unavailable cases; do not substitute a mocked client.

## Wallet

- [ ] Expand Custom gold goals for the original manual-reservation checks below; observed NPC prices are exercised separately.
- [ ] Add goals costing 1.0001 and 2 gold. Reserved total is 3g 0s 1c.
- [ ] Edit the first to 1 gold. Reserved total becomes exactly 3g; no duplicate goal appears.
- [ ] Finish the second. Reserved total becomes 1g; reopen and remove it to exercise both controls.
- [ ] Make an ordinary money-changing game action. Carried balance updates and available/shortfall agree with active goals. Reload and verify saved records.
- [ ] Negative, exponent, overprecision and excessive amounts are rejected without altering a record.

## Item advice

- [ ] Expand Manual reservations and Always keep for the existing custom-need checks below. Recipe goals are exercised separately.
- [ ] Add two goals for one carried item: quantities 10 and 20. Total needed is 30.
- [ ] Edit 20 to 15. Total needed is 25, with no duplicate goal.
- [ ] Hover different stacks. Advice always refers to total bags, not the hovered stack. Compare carried count with actual inventory.
- [ ] Add an Always keep rule, exercise a quest item and an uncached item, disable the module while its tooltip is visible, then reload and confirm stored needs.
- [ ] Check that no selling/deleting happens automatically and that the UI explains it cannot prevent sales by other addons.

## Legacy

- [ ] On an unlocked character, compare challenge names/categories, completion and criteria against Blizzard's Legacy panel. No unrelated achievements appear.
- [ ] Compare a challenge earned on another character: character completion must match Blizzard's character-earned display, not account completion alone.
- [ ] Pin a challenge, search it, switch all/next views, and open native details.
- [ ] Create a manual perk plan, edit it, reject duplicate perks/over-cap allocations, save and reload. The manual label remains visible and points are never spent automatically.
- [ ] When readable, exercise live perk names, rank limits and cap. An unavailable live read remains unavailable and permits explicit manual planning.
- [ ] Enter combat and verify restricted data is not treated as zero or silently refreshed. Repeat on a locked character only if one is readily available.

## Two-player party session

- [ ] While solo, save a draft and complete a local task. Reload; local details persist with no active shared session.
- [ ] Form an ordinary party with both updated clients. With automatic joining enabled, leader starts a session and the member joins without opening the panel or clicking Join. Receiving/joining never replaces or publishes a local draft.
- [ ] Include a long meeting point and several tasks, including non-ASCII names. Confirm complete snapshots agree on both clients; incomplete data never partially replaces a session.
- [ ] Each player checks their own readiness. Both panels converge; one player's update cannot change another player's readiness.
- [ ] Leader edits the draft and publishes. Revision increases and readiness clears. Repeated requests for the same revision preserve current readiness.
- [ ] Publish while the member is in combat so it misses the update. On leaving combat, a newer owner announcement/heartbeat or Request again recovers the complete revision and clears old readiness.
- [ ] Mark readiness before a member reloads/rejoins. Previously reported readiness converges again through sender-owned replay; never-reported values remain unknown. Repeat after the peer freshness expiry.
- [ ] Reload a member and confirm automatic recovery, then change leader, leave the party, and disable sharing. Local drafts persist and former member/leader readiness becomes unknown or is removed. During restrictions, stale participant presence expires within two minutes.
- [ ] Enter combat or a restricted chat state. Sharing pauses and status does not falsely claim delivery. Return to normal play and request/publish again if queued data expired.

## Raid and instance extension (reuse the same two clients)

- [ ] Install 0.1.2 on both clients. Add a quest-named checklist task, start/auto-join in an ordinary party, then enter and leave a dungeon together. The session, task and reported readiness remain; local drafts remain separate. Updates pause during combat and resume afterward. These are manual tasks, so quest-journal changes do not tick them automatically.
- [ ] Convert that party to a raid and back with the same leader. The checklist recovers on the new channel with no new consent/join needed and no old-channel packets. Both players can report readiness across the conversion. In a raid, wait up to one heartbeat (about 75 seconds plus queued transmission) for previously reported readiness.
- [ ] Start/join directly in a raid. If a real larger group is readily available, have a participant outside the leader's five-player subgroup join and report readiness. Use the existing clients as addon participants; do not build a mock roster. Record the verification gap if additional real members are unavailable.
- [ ] In an available instance group, leader starts and member auto-joins; publish a changed checklist and update each player's own readiness. A missed revision recovers automatically, with Request again also available. Switching from a separate home party to the instance group closes the old session and preserves the draft. Confirm the separate home party does not receive instance-group session text; mark this observation unavailable if no real home-party observer is available.
- [ ] While updates are queued, leave/re-form a group with the same leader, change leader, disable sharing and reload. Old queued checklist text must not reach the replacement group. Members auto-join only the current leader's newly started session. Repeat a group change during combat if safely possible.
- [ ] Request recovery from both clients close together with 20 tasks. Both obtain a complete revision without partial replacement or continuously restarting synchronization. Repeated unchanged recovery must preserve readiness. A full raid joining at once remains unverified unless real participants are available.

## Automatic enrollment (reuse the same two clients)

- [ ] With no saved sharing preference on a safe fresh profile, automatic joining defaults on. On an existing profile, set sharing off and reload: it stays off, no enrollment occurs, and local tasks remain usable. Do not clear real SavedVariables just to test the default; record the gap if no fresh profile is available.
- [ ] Keep the member's panel closed when the leader starts a checklist. The member joins and is counted only after its complete checklist acknowledgement. Neither player's tasks become ready merely from joining. Open the panel to confirm its local draft is unchanged.
- [ ] Reload the member, then toggle its Adventure Together module off and on. It rediscovers and joins the leader's same active session without Join or Announce again. Mark a task ready and confirm periodic announcements preserve it; late raid readiness may take one heartbeat.
- [ ] Use Leave and pause sharing, then have the leader announce and publish again. The member remains out through reload. Re-enable automatic joining and confirm recovery of the same active session. A disabled module or read-only save must not join or send discovery/checklist traffic.
- [ ] Let combat or a supported communication restriction interrupt initial enrollment or a changed revision. On resuming normal play, the member automatically receives one complete checklist. Leader ends sharing while the member is still synchronizing: the member closes the session and stops retries. Start a new leader session afterward and confirm enrollment resumes without reviving the old session.
- [ ] Reuse the maximum-checklist recovery scenario above: repeated announcements and concurrent joins must not reset a current checklist/readiness or continuously restart downloads. No ordinary chat, inventory or gold messages should be emitted.

## Automatic quest logs (reuse two real updated clients)

- [ ] With sharing off, accept a quest and open My quests: title/objective counts appear without adding a manual task. Progress changes update automatically. Collapse/expand native quest headers: coverage becomes partial when uncertain, previously seen quests become stale rather than disappearing/completing, and expanding recovers observations without altering the native collapse state automatically.
- [ ] Enable sharing on both clients. With no manual tasks or session title, leader chooses Start group tracking as leader. Member auto-enrolls. Group quests matches a shared quest by ID; Details shows each player's own counts. Advance one player, then the other: updates affect only the sender. A quest held by one player is absent/unknown for the other, never silently ready.
- [ ] Complete objectives: status is Ready for turn-in, not rewarded. Turn in or abandon a quest using normal game controls: active membership reconciles. The addon performs no quest action and does not tick optional manual tasks.
- [ ] Publish a changed manual draft, reload a member, join late, and convert the same group to a raid. Automatic progress recovers while manual readiness remains separate. New sender generations reject older observations; a delayed older removal/manifest must not resurrect an abandoned quest.
- [ ] Interrupt quest sharing with combat/restrictions, then resume. Partial/unavailable logs do not delete unseen quests or count stale ready progress. Where safely feasible, leave the panel open until peer freshness expires: stale state updates without another click, including while combat/manual synchronization blocks roster reads. Do not prolong combat just to run this check.
- [ ] Exercise the available real quest log rather than an artificial roster. Several objective changes during a larger initial sweep must still drain progress packets; late records remain waiting/unknown until complete. If over 100 quests, eight objectives or unsupported counters cannot be exercised safely, record those coverage gaps. Non-addon clients never appear to supply authoritative quest logs.
- [ ] Pause sharing and reload: local quests still update but no new quest traffic is sent. Re-enable and verify automatic recovery, then change leader/leave group/disable the module: peer quest state clears. Only quest IDs/status/counts are shared; no ordinary chat, gold, inventory or local manual draft is sent by joining.

## Recipe-driven materials (one real character)

- [ ] In your own profession window, select a simple learned recipe. Open `/fc items`, track two crafts and confirm every material/quantity against the native recipe. No material is entered individually; quantities mean crafts, not number of output items. Track the same recipe again: the existing goal updates instead of duplicating.
- [ ] Where convenient, track a second recipe sharing a material and add a small manual need for the same item. Total required is the sum of all craft/manual reservations, and carried bags are subtracted once. Gathering or normal bag changes update shortages without reducing remaining crafts.
- [ ] Perform one inexpensive craft you intended to make. Its goal decreases exactly once; the other goal stays unchanged. Verify a brief pending-bags state never advertises consumed reagents as surplus. Cancel the next cast: remaining crafts do not decrease. If a batch is practical, confirm one credit per actual completed execution, independent of output quantity; record any event delivery gap rather than assuming it works.
- [ ] Start a cast and edit/retrack/remove its goal before completion, if safely possible. That earlier cast must not credit the changed/new goal. Reload during a cast only if practical; uncertain completion must preserve demand for manual correction rather than guess from bag loss. Sales/trades/output purchases do not count as crafts.
- [ ] Reload and verify goals/counts persist. Cached requirements reserve known materials but withhold surplus until fully revalidated. Open your own profession and confirm supported goals refresh. Edit remaining to zero: requirements release. Reopen by setting a positive count, then remove the goal.
- [ ] Mark a reserved ingredient Always keep; exercise a quest or uncached item and an unavailable/linked recipe context. Neither the panel nor tooltip may advertise protected/unknown items as surplus. Unsupported optional/alternative/leveled/recraft recipes must show a reason, never partial zero requirements. Skip unavailable recipe categories and record the gap.
- [ ] Reuse the backed-up invalid-save fixture only if safe: malformed crafting records preserve the complete original save and recovered read-only data never produces surplus advice. Disable the Items module during a cast: no later event may credit its paused goal. No crafting, purchases, selling, item movement or native recipe selection is performed by this addon.

## Observed prices and automatic funding (one real character)

- [ ] Visit a vendor with an ordinary gold-priced bundle and a trainer with an unlearned service. Keep the native window open and open `/fc wallet`; compare displayed names, bundle sizes, quoted gold and trainer ranks with the native UI. A verified free service remains zero; unavailable/extended/currency/pet-point/buyback data never becomes an invented free offer.
- [ ] Budget one trainer quote and two vendor bundles without typing prices. The vendor target equals displayed bundle price times two, not price times item count twice. Repeat Budget on the same offer: the matching budget updates without duplicates. Imported vendor Edit changes bundles; a manual goal still permits a custom target.
- [ ] Reuse an older manual goal with insufficient carried gold. Add the trainer/vendor budgets and confirm ascending-ID funding: no copper funds two goals, total funded is at most carried balance, and shortfalls agree. Use an ordinary money-changing action you intended to make: income/spending changes immediately redistribute funding and the session counters reflect the observed net change.
- [ ] Finish a goal, then reopen a vendor goal while standing at that vendor. Its saved price becomes estimated until a fresh scan, which updates the matching source price and funding. Changing NPC, list order, stock, discount or bundle size must not update a different item/quantity. Trainer quotes remain historical until explicitly re-imported. A newly changed price/list is rechecked when Budget is clicked.
- [ ] Where a naturally partial catalogue exists, choose a supported visible row: exact slot/identity/price revalidation permits a labeled estimate. Do not create artificial NPC data or expand a test matrix; record the gap if no partial catalogue is available. Unreadable rows do not trigger automatic repricing.
- [ ] Close the source window, reload or toggle Wallet off/on: saved quotes remain estimates and session counters rebase. An actual unreadable-money gap marks counters partial without attributing missing gold; never manufacture restricted values with mocks. Buying/training does not auto-finish a goal, and the addon triggers no purchase, training, transfer or chat action.
- [ ] In the existing backed-up corruption fixture only if safe, malformed price metadata preserves the entire original save read-only. Recovered goals never claim exact spendable gold. Record unsupported API/source/discount cases instead of spending unintended resources to exercise them.

## Report

Record date, beta build/interface, each checked step, any Lua error context, and the results of the two-player scenario. A launch-ready label also requires rechecking the actual launch-client folder and interface. This walkthrough is not evidence of passing until executed through the real game.
