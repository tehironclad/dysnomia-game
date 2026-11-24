# Porting this branch's features to v2 (`claude/fervent-galileo-5pzyjy`)

This branch (`claude/eager-cannon-ctzojh`) was built on the old v1 snapshot (`cfdb2be`). v2 is a rewrite, so
features have to be **re-implemented against v2's systems**, not merged. Follow v2's CLAUDE.md hard rules
(simulate → sign → verify receipt → re-read; never fabricate chain data; Multicall3, no batches; Supabase and
entropy API are gone, site API is `systm0.vercel.app`).

Port one feature per session, smallest first. For each: read the v1 files listed here as the design
reference, then build it on the v2 counterpart.

| Feature | v1 files (reference) | v2 counterpart to build on | Notes |
|---|---|---|---|
| AFFECTION ride tickets → QING keeper, measured Hypo/Epi report | `scripts/chain/affection_economy.gd`, `scripts/world/attraction_catalog.gd` | `scripts/games/arcade_pay.gd` (already 1 Ⓐ → QING, receipt-verified) | Reuse ArcadePay for tickets; prices: 1 AFFECTION each |
| Bar drinks = the visitor's own AFFECTION ops | `attraction_catalog.gd` DRINKS, `attraction_director.gd`, `scripts/ui/attraction_ui.gd` | `scripts/state/moves.gd` / `acts.gd`, `places/sunny_pub.gd` | Drinks map to Pi/Rho/Generate/Alpha/Beta/Upsilon |
| Affection Fair (tiered rides: rocket, wheel, drop, carousel) | `scripts/world/funfair/*` (+ `fair_kit.gd`), `ride_base.gd`, `tools/fair_preview.gd` | a new place/site next to `territory_core`; tier from `scripts/state/development.gd` | Self-contained; mostly needs a spawn point + `get_rides()` wiring and ArcadePay tickets |
| QING Standing (tier from activity) | `scripts/world/qing_standing.gd` | `scripts/state/development.gd` (Hypobar tiers) | v2 already tiers by Hypobar; add visitors/chat as extra inputs only if wanted |
| Community media boards (1 AFFECTION / 24 h, verified on-chain) | `scripts/world/board_feed.gd`, `media_board.gd`, `scripts/ui/board_post_ui.gd` | `scripts/state/chat_log.gd`, `places/chat_controller.gd`, ArcadePay for payment | Post = tagged QING chat line citing the payment tx; viewers verify receipts |
| Shuttle-only fast travel to joined QINGs | `scenes/main.gd` (`_on_map_territory_selected`, `_spawn_shuttle_terminal`), `scripts/ui/world_map.gd` | `scripts/core/travel.gd`, `scripts/core/warp.gd` | Rule: walk border + Join for new QINGs; shuttle only to admitted ones |
| Real-time players (guests too), name tags, chat bubbles, HAPPENING NOW moments, online counter | `scripts/multiplayer/realtime_client.gd`, `community_hub.gd`, `community_identity.gd`, `scripts/ui/community_feed.gd`, `tools/test_realtime.gd` | needs a live realtime backend — the old Supabase project is gone | Client speaks Supabase Realtime (Phoenix); point it at a new project or another relay |
| Daily quests, streaks, titles, "Things to do" (Y) | `scripts/minigames/quest_board.gd`, `scripts/ui/todo_panel.gd`, `quest_tracker.gd` | `scripts/state/opportunities.gd`, `ui/opportunities_panel.gd`, `ui/guide_panel.gd` | Feed `QuestBoard.report()` from v2 moves/acts |
| Telegram invite (K) | `scenes/main.gd` `share_invite_to_telegram()` | `ui/hud_v2.gd` | `https://t.me/share/url?url=…&text=…` |
| Dysnomia minigames (dice from entropy, WAAT slots, data trivia, contract match) | `scripts/minigames/*` | `scripts/games/*`, `scripts/arcade/*` | v2 has its own arcade; port trivia/match ideas as new carts or tables |
| Ambient NPCs (seeded suits, sit/lean, culling) | `scripts/world/npc/ambient_npc.gd` | `scripts/player/human_avatar.gd` (Quaternius rig) | Use the Quaternius clips instead of the teddy model |

v1-only fixes that may or may not apply to v2: the player was never in the `"player"` group; four shaders used
`return` in `fragment()`. Check before porting.
