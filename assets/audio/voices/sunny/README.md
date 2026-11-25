# Sunny's voice

Sunny, the bartender at Sunny's Pub, speaks these lines. Today they show as subtitles only (the
bubble over his head and a line at the bottom of the screen). Drop a recording in this folder,
named after its line id, and the game plays it from Sunny whenever he says that line. The
subtitle still shows. There is no synthesised voice: a line without a file stays silent.

The game looks for `<line id>.ogg`, then `.wav`, then `.mp3`, in this folder
(`res://assets/audio/voices/sunny/`). `scripts/audio/voice_lines.gd` (`VoiceLines.SUNNY`) holds
the same list, and a test checks that this file names every line.

## The lines to record

| File | Say | When |
| --- | --- | --- |
| `greeting.ogg` | Welcome to Sunny's! Come on up to the bar, friend. | You first walk into the pub |
| `come_closer.ogg` | Come up to the bar, friend. The menu's on the board. | You press the menu key away from the counter |
| `menu_open.ogg` | What'll it be? Every drink here is your own call, on the chain. | The menu opens |
| `order_taken.ogg` | Coming right up. | You press Pour (or buy the round) |
| `payment_waiting.ogg` | Just need your say-so in the wallet, friend. Take your time. | The wallet window is waiting for your signature |
| `payment_failed.ogg` | Hm. That one didn't go through. No harm done; nothing was poured. | The order was rejected, failed or reverted |
| `pour.ogg` | Watch this. | The receipt is in: Sunny starts pouring |
| `here_you_go.ogg` | Here you go. Enjoy. | He slides the glass over |
| `cheers.ogg` | Cheers! | You drink |
| `round_cheers.ogg` | A round for the house! Cheers, everyone! | You bought the round (1 Ⓐ to the QING) |
| `order_another.ogg` | Another one? The menu's right here. | The menu comes back after the drink |
| `goodbye.ogg` | Come back soon. The lights stay on. | You close the menu |
| `idle_bottles.ogg` | These bottles won't polish themselves. | Now and then, to the room |
| `idle_taps.ogg` | Every one of these taps runs straight to the chain. | Now and then, to the room |
| `idle_sunflowers.ogg` | Sunflowers face the sun. Regulars face the bar. | Now and then, to the room |
| `idle_pool.ogg` | Pool table's free, if you fancy a game. | Now and then, to the room |
| `idle_quiet.ogg` | Quiet night. I like a quiet night. | Now and then, to the room |

Numbers never go in a recording. Where the subtitle adds one (the drink's name and its block,
e.g. "Here you go. Enjoy. · Alpha Sour · block 28,145,221"), that part is read from the chain and
shown, not spoken.

## Recording tips

- **Format:** Ogg Vorbis (`.ogg`), **mono**, 44.1 kHz or 48 kHz. Quality 5–6 (about 96–128 kbps)
  is plenty for speech. WAV (16-bit PCM, mono) and MP3 also work; Ogg is smallest and loops cleanly.
- **Mono matters:** the clip plays from Sunny's position in the room (3D), and Godot only
  positions mono sound well.
- **Level:** peaks around −3 dBFS, speech averaging about −18 to −16 LUFS. Every clip at the same
  level, so no line jumps out.
- **Trim:** about 0.1 s of silence before and after. No music, no room reverb (the game is the
  room). A quiet room and a pop filter help.
- **One line per file**, named exactly as in the table (lower case, underscores).
- **Takes:** read the words as written. Small changes are fine. If you change a line a lot, change
  its words in `VoiceLines.SUNNY` too, so the subtitle matches what you say.

## Adding a recording

1. Put the file here, for example `assets/audio/voices/sunny/here_you_go.ogg`.
2. Open the project in Godot once (or run `godot --headless --import --path .`) so it is imported.
   Without the import, a loose `.ogg`/`.wav`/`.mp3` still plays when running from the project
   folder, but an exported build only carries imported files.
3. Check it: go to Sunny's Pub (TehSunFlowrScioety QING) and order. Or render the sequence:
   `screenshot.gd -- --scene=res://scenes/places/sunny_pub.tscn --view=handover` (pictures only).
