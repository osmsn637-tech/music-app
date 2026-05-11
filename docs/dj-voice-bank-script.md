# DJ Voice Bank — Master Script v2

This is the source-of-truth for every line the offline DJ can speak.
Each line is one audio clip in `<app_documents>/dj_voice_bank/`,
keyed by `id` in `manifest.json`.

The voice changed between v1 and v2: the old bank was philosophical and
slow, which the user described as "robotic". v2 is conversational, fast,
and opinionated. The DJ has a personality now — see section 1 below.

---

## 1. Persona

The DJ is your friend who knows the catalog cold. Twenties or early
thirties. Houston / Atlanta / by-way-of-the-internet. He talks at you
like you already know what's good — short sentences, opinions baked in,
no over-explaining.

He's not a radio host. He doesn't perform. He drops in, says one thing,
gets out.

**Strong opinions, lightly held:**

- **Favorite — Future.** Pluto. Hndrxx. Whatever the era, that's his guy.
  He'll defend Future runs nobody else will. Lines about Future are
  sincere — he means them.
- **Likes — Drake & Travis Scott.** Drake = catalog respect, even when
  the man's coasting. Travis = auto-tune as architecture, the whole
  apparatus. He'll defend both against memes.
- **Respects — Metro Boomin.** Craftsman to craftsman. When Metro's name
  is on the credits, the DJ says so. Production-first respect, not
  fanboying.
- **Hates — Playboi Carti.** Considers Whole Lotta Red overrated noise
  and MUSIC a downgrade. He plays the songs because the queue says so,
  but the lines come with side-eye and the occasional joke.
- **Neutral / mild like — everyone else.** He doesn't hate freely. Most
  artists get fair lines.

The personality should leak naturally. Two Future tracks back-to-back?
Sincere excitement. Carti up next? Reluctance, sometimes a joke. Metro
production credit? A nod of recognition. Avoid grandstanding — a
4-second line says more than a 12-second monologue.

---

## 2. Voice direction (for F5-TTS rendering)

- **Cadence:** conversational, fast — 140–160 words per minute. v1 was
  ~100. The bump is the single biggest difference in feel.
- **Length:** target 4–10 seconds per clip. Some 2-second one-liners
  ("We move.", "Yeah I said it.") are good — don't pad.
- **Register:** mid-chest. Slight rasp. Confident, never theatrical.
  Think a friend over text-to-speech, not a radio host.
- **Mic distance:** hand's-width, dry. **No reverb. No stage echo.** v1
  had too much room — pull it tighter.
- **Air:** quarter-second of room tone before / after each take.
- **Filler:** `Aight`, `Yeah`, `Look` — sparingly, only as line
  starters, never mid-sentence.

**Pronunciation map** (these are spelled phonetically in line text so
F5-TTS doesn't mangle them):

- `A-Sap Rocky` (not "asap")
- `Party Next Door`, `P N D`
- `Eight A M` (not "8am")
- `J Cole` (no period)
- `Twenty One Savage` (say the number)
- `K Dot`
- `eight oh eights` (the drum)
- `Pluto` (Future's nickname)
- `Cactus Jack` (Travis's label)
- `Ty Dolla Sign`
- `Vultures` (Kanye + Ty)
- `Tonka` (Yeat ad-lib)

---

## 3. Top 50 song picks (per-song treatment)

These are the songs that get hand-written 5-line song-specific banks
in section 6. Other songs fall through to artist-level lines. Bias is
toward the user's favorites — Future heaviest, then Drake & Travis,
some Metro production credits, a few Carti tracks for the hate-flavor.

**Future (10):** WAIT FOR U, WIFI LIT, Feds Did a Sweep, Slave Master,
Like That, Call The Coroner, Promise U That, Mask Off, March Madness,
Codeine Crazy.

**Travis Scott (8):** SICKO MODE, STARGAZING, BUTTERFLY EFFECT,
ASTROTHUNDER, GOOSEBUMPS, FE!N, MELTDOWN, SIRENS.

**Drake (7):** 8AM IN CHARLOTTE, KNIFE TALK, IMY2, FIRST PERSON SHOOTER,
WHAT DID I MISS, FROM TIME, MEMBERS ONLY.

**Kanye West (4):** 530, PROMOTION, RIVER, CARNIVAL.

**Don Toliver (4):** AFTER PARTY, K9, ROSARY, RENDEZVOUS.

**Metro Boomin productions (3):** CALLING, TRANCE, SUPERHERO.

**Baby Keem (3):** Family Ties, Cocoa, Birds & the Bees.

**Playboi Carti (3 — hate flavor):** 2024, JUMPIN, EVIL J0RDAN.

**The Weeknd (2):** Blinding Lights, Sacrifice.

**21 Savage (1):** Snitches & Rats Interlude.

**J. Cole (2):** Middle Child, No Role Modelz.

**Yeat (1):** Talk.

**Tory Lanez (1):** The Color Violet.

**Imagine Dragons (1):** Natural.

If a track here isn't actually in the library, swap it out before
running the F5-TTS render. The render script reads the song id, not
the friendly name — adjust the per-song id in section 6.

---

## 4. Generic clips

Filtered by `intent`, optionally `position` and `mode`. 3 lines per
category. Selector falls to these whenever no song-specific or
artist-specific clip matches.

### intro_set (opener)

| id | line |
| --- | --- |
| `gen_intro_set_001` | Aight. Set's loaded. Hit play. |
| `gen_intro_set_002` | Locked in. Let's run it. |
| `gen_intro_set_003` | Queue's set. Start the night. |

### set_closer (closer)

| id | line |
| --- | --- |
| `gen_set_closer_001` | Last one. Let it ride. |
| `gen_set_closer_002` | Closing it out. Good run. |
| `gen_set_closer_003` | End of the set. Catch you next time. |

### next_track (mid-set)

| id | line |
| --- | --- |
| `gen_next_track_001` | Onto the next. |
| `gen_next_track_002` | Switch up. |
| `gen_next_track_003` | Different one. Lock in. |

### energy_up

| id | line |
| --- | --- |
| `gen_energy_up_001` | Tempo's coming up. Move with it. |
| `gen_energy_up_002` | Pace shift. Don't drag. |
| `gen_energy_up_003` | Heat check. Stay on it. |

### energy_down

| id | line |
| --- | --- |
| `gen_energy_down_001` | Pulling it back. |
| `gen_energy_down_002` | Easing the room down. |
| `gen_energy_down_003` | Cooling the tempo. Take a breath. |

### keep_vibe

| id | line |
| --- | --- |
| `gen_keep_vibe_001` | Keeping it where it is. |
| `gen_keep_vibe_002` | Same lane. Different car. |
| `gen_keep_vibe_003` | Still rolling. Don't move. |

### study_focus (mode: study)

| id | line |
| --- | --- |
| `gen_study_focus_001` | Music's the floor. You're the work. |
| `gen_study_focus_002` | Stay on the page. I'll handle the rest. |
| `gen_study_focus_003` | Background, not foreground. Lock in. |

### chill_transition (mode: chill)

| id | line |
| --- | --- |
| `gen_chill_transition_001` | Slow water. Just float. |
| `gen_chill_transition_002` | Easy. Take your time. |
| `gen_chill_transition_003` | No edges on this one. |

### workout_boost (mode: workout)

| id | line |
| --- | --- |
| `gen_workout_boost_001` | One more set. The song's with you. |
| `gen_workout_boost_002` | Push the verse. Reward's the chorus. |
| `gen_workout_boost_003` | You're not done. Neither's the song. |

### night_drive (mode: night)

| id | line |
| --- | --- |
| `gen_night_drive_001` | Highway's empty. Song fills it. |
| `gen_night_drive_002` | Windows-down kind of song. |
| `gen_night_drive_003` | Low light. Steady speed. |

### discovery

| id | line |
| --- | --- |
| `gen_discovery_001` | Something new. Or new to you. Same thing tonight. |
| `gen_discovery_002` | Don't know this one yet. That's the point. |
| `gen_discovery_003` | Trust the queue. |

### throwback

| id | line |
| --- | --- |
| `gen_throwback_001` | Old one. Still works. |
| `gen_throwback_002` | Throwback. You earned this. |
| `gen_throwback_003` | Older record. Same nerves it always touched. |

### favorite_return

| id | line |
| --- | --- |
| `gen_favorite_return_001` | Familiar one. Welcome back. |
| `gen_favorite_return_002` | You keep coming back. Fair trade. |
| `gen_favorite_return_003` | Old favorite. Still hits. |

### artist_spotlight (only fires when prev = current artist)

| id | line |
| --- | --- |
| `gen_artist_spotlight_001` | Two in a row. Catalog's deep. |
| `gen_artist_spotlight_002` | Same voice. Different angle. |
| `gen_artist_spotlight_003` | Stayin' on this one. They got more. |

### mood_shift

| id | line |
| --- | --- |
| `gen_mood_shift_001` | Different mood. Roll with it. |
| `gen_mood_shift_002` | Turn the corner. New room. |
| `gen_mood_shift_003` | Shift's coming. Stay with me. |

### recover_from_skip

| id | line |
| --- | --- |
| `gen_recover_from_skip_001` | Yeah. Not it. |
| `gen_recover_from_skip_002` | We move. |
| `gen_recover_from_skip_003` | Reset. Try this. |

### lyric_anchor

| id | line |
| --- | --- |
| `gen_lyric_anchor_001` | Listen for the first line. He's not wasting it. |
| `gen_lyric_anchor_002` | Opening bar tells you the song. Catch it. |
| `gen_lyric_anchor_003` | Hook says it all. Wait for it. |

---

## 5. Mode-specific intros

Filtered with `intent=intro_set`, `position=opener`, `mode=<mode>`.
Higher priority than the generic intros.

### Mode: study

| id | line |
| --- | --- |
| `mode_intro_study_001` | Quiet hour. Set's tuned for it. |
| `mode_intro_study_002` | Work mode. Music stays out the way. |

### Mode: chill

| id | line |
| --- | --- |
| `mode_intro_chill_001` | Soft start. Lean back. |
| `mode_intro_chill_002` | Chill set. No surprises. |

### Mode: workout

| id | line |
| --- | --- |
| `mode_intro_workout_001` | Tighten the laces. Forty minutes. |
| `mode_intro_workout_002` | Workout's loaded. Meet me at the chorus. |

### Mode: night

| id | line |
| --- | --- |
| `mode_intro_night_001` | It's late. Set knows. |
| `mode_intro_night_002` | Small hours. Drive careful. |

### Mode: favorites

| id | line |
| --- | --- |
| `mode_intro_favorites_001` | All friends in this queue. You picked these. |
| `mode_intro_favorites_002` | Favorites only. No skips needed. |

### Mode: discover

| id | line |
| --- | --- |
| `mode_intro_discover_001` | Tonight's set is what you haven't heard. Open ears. |
| `mode_intro_discover_002` | New ground. Walk it. |

### Mode: smart_shuffle

| id | line |
| --- | --- |
| `mode_intro_smart_shuffle_001` | Smart shuffle. Queue's been listening. |
| `mode_intro_smart_shuffle_002` | Songs you'd reach for, in an order you wouldn't have. |

---

## 6. Per-artist banks

Filtered with `artistId`. Selector prefers these over generic when the
context's artist matches. 6 lines per artist (was 8 in v1 — trimmed for
focus).

### Future (favorite — sincere hype)

| id | line |
| --- | --- |
| `artist_future_001` | Pluto on. That's the rotation. |
| `artist_future_002` | Future drop. We don't skip Future. |
| `artist_future_003` | Hndrxx. Pluto. Whatever you call him. He's in. |
| `artist_future_004` | Voice of the trenches. Voice of right now. |
| `artist_future_005` | Future. Don't ask me to defend it. Just listen. |
| `artist_future_006` | Pluto cooked. Don't cut it short. |

### Drake (likes — defended)

| id | line |
| --- | --- |
| `artist_drake_001` | Drake. Yeah I said it. |
| `artist_drake_002` | OVO. Catalog goes deep. Pull up. |
| `artist_drake_003` | Aubrey on the booth. Pen's still working. |
| `artist_drake_004` | Don't let the memes get you. He's been doing this since you were in middle school. |
| `artist_drake_005` | Drake's the kind of guy people like to dunk on. The numbers don't lie. |
| `artist_drake_006` | Started on mixtapes. Never stopped working. The work's the brand. |

### Travis Scott (likes — respects as artist)

| id | line |
| --- | --- |
| `artist_travis_scott_001` | Travis. The way records are supposed to sound. |
| `artist_travis_scott_002` | Cactus Jack. La Flame. Whole apparatus. |
| `artist_travis_scott_003` | Auto-tune as architecture. Since twenty fifteen. |
| `artist_travis_scott_004` | Travis on the booth. Sit back. |
| `artist_travis_scott_005` | He's not singing to you. He's singing past you. Stand in the path. |
| `artist_travis_scott_006` | Eight oh eights. Cathedrals. World-building. The formula. |

### Metro Boomin (respects — craftsman to craftsman)

| id | line |
| --- | --- |
| `artist_metro_boomin_001` | If Metro on it, lock in. |
| `artist_metro_boomin_002` | Metro Boomin. Trust him. |
| `artist_metro_boomin_003` | Producer of the era. Easy debate. |
| `artist_metro_boomin_004` | When you hear Young Metro, you know what's coming. |
| `artist_metro_boomin_005` | Metro builds the room. Rappers just live in it. |
| `artist_metro_boomin_006` | Metro again. Crafter to crafter — credit where it's due. |

### Playboi Carti (HATES — sarcastic dismissal)

| id | line |
| --- | --- |
| `artist_playboi_carti_001` | Carti up. Don't shoot the messenger. |
| `artist_playboi_carti_002` | Whole Lotta noise incoming. |
| `artist_playboi_carti_003` | I don't pick the queue. I just play it. |
| `artist_playboi_carti_004` | Vamp shit. We move. |
| `artist_playboi_carti_005` | Look — y'all asked for it. |
| `artist_playboi_carti_006` | Carti track. Whatever syllables he picked today. |

### Kanye West

| id | line |
| --- | --- |
| `artist_kanye_west_001` | Yeezy. Even when he's losing, he wins on a beat. |
| `artist_kanye_west_002` | Kanye. Whatever era, always interesting. |
| `artist_kanye_west_003` | Ye drop. Ride the production. |
| `artist_kanye_west_004` | Vultures-era Kanye is a different lane than 808s — same engineer. |
| `artist_kanye_west_005` | Don't let the headlines get in the way of the song. |
| `artist_kanye_west_006` | Kanye West. When he wants to, he still does. |

### Don Toliver

| id | line |
| --- | --- |
| `artist_don_toliver_001` | Don. The voice doesn't ask. It just arrives. |
| `artist_don_toliver_002` | Toliver works in fog. Let the eyes adjust. |
| `artist_don_toliver_003` | Don Toliver. Cactus Jack honor roll. |
| `artist_don_toliver_004` | Cadence is the whole point. |
| `artist_don_toliver_005` | Slow burn record incoming. Don't rush. |
| `artist_don_toliver_006` | Toliver again. Not a radio guy. A 2 A M guy. |

### 21 Savage

| id | line |
| --- | --- |
| `artist_21_savage_001` | Twenty One. Voice you don't argue with. |
| `artist_21_savage_002` | Savage Mode. The mode's the brand. |
| `artist_21_savage_003` | Twenty One Savage on the track. Cold. |
| `artist_21_savage_004` | He doesn't raise his voice. The room still listens. |
| `artist_21_savage_005` | From Atlanta to anywhere. Same temperature. |
| `artist_21_savage_006` | Twenty One. Lines hit harder for being whispered. |

### Young Thug

| id | line |
| --- | --- |
| `artist_young_thug_001` | Thugger. The way melody's supposed to bend. |
| `artist_young_thug_002` | Young Thug. He invented half this stuff. |
| `artist_young_thug_003` | Slime on the booth. Whole genre owes him. |
| `artist_young_thug_004` | Thugger writes melody like it's negotiable. It is. |
| `artist_young_thug_005` | Young Thug. Decade-changing tongue. |
| `artist_young_thug_006` | Anything Thug touches. Listen for the cadence. |

### The Weeknd

| id | line |
| --- | --- |
| `artist_the_weeknd_001` | Abel. After-hours specialist. |
| `artist_the_weeknd_002` | The Weeknd. Built for headphones at 1 A M. |
| `artist_the_weeknd_003` | Trilogy energy. Decade later. Still works. |
| `artist_the_weeknd_004` | Weeknd record. Lights low. |
| `artist_the_weeknd_005` | He's a crooner now. Used to be darker. Both still in the voice. |
| `artist_the_weeknd_006` | Abel. The night's official sponsor. |

### Tory Lanez

| id | line |
| --- | --- |
| `artist_tory_lanez_001` | Tory. Pen's still there. |
| `artist_tory_lanez_002` | Lanez on the track. Take it for what it is. |
| `artist_tory_lanez_003` | Chixtape memories. Different era. |
| `artist_tory_lanez_004` | Tory's catalog is deeper than the discourse. |
| `artist_tory_lanez_005` | Tory. The records are still records. |
| `artist_tory_lanez_006` | Lanez. Hooks for days. The man can sing. |

### Yeat

| id | line |
| --- | --- |
| `artist_yeat_001` | Yeat. Strange. Works. |
| `artist_yeat_002` | Tonka boy. Latest mutation of rage rap. |
| `artist_yeat_003` | Yeat. Don't look for sense. Look for cadence. |
| `artist_yeat_004` | Twizzy. Bell sounds. We're here for it. |
| `artist_yeat_005` | Yeat record. Future-leaning. Earplugs optional. |
| `artist_yeat_006` | Yeat. Generation Z's contribution. Take or leave. |

### Baby Keem

| id | line |
| --- | --- |
| `artist_baby_keem_001` | Baby Keem. Cousin of you-know-who. |
| `artist_baby_keem_002` | Keem doesn't sit still. The track won't either. |
| `artist_baby_keem_003` | Cousin Keem. He's his own thing now. |
| `artist_baby_keem_004` | Half this song's gonna swerve. Keep up. |
| `artist_baby_keem_005` | Keem records get to beat two before you finish beat one. |
| `artist_baby_keem_006` | Baby Keem. Half-attention won't catch it. |

### J. Cole

| id | line |
| --- | --- |
| `artist_j_cole_001` | J Cole. Pen still works overtime. |
| `artist_j_cole_002` | Cole tells the truth slowly. |
| `artist_j_cole_003` | Jermaine on the track. Not in a rush. Don't be. |
| `artist_j_cole_004` | He's not making noise. He's making a record. |
| `artist_j_cole_005` | Cole. Builds songs the way other people build sentences. |
| `artist_j_cole_006` | Twelve years in. Picking smaller fights. Discipline. |

### A$AP Rocky

| id | line |
| --- | --- |
| `artist_asap_rocky_001` | A-Sap Rocky. New York with the volume up. |
| `artist_asap_rocky_002` | Pretty Flacko picks his moments. |
| `artist_asap_rocky_003` | Rocky. Slower than he used to be. Better for it. |
| `artist_asap_rocky_004` | Fashion-week swagger on every track. Earned. |
| `artist_asap_rocky_005` | A-Sap Mob. Moods over hits. |
| `artist_asap_rocky_006` | Flacko. Takes himself just unseriously enough. |

### PARTYNEXTDOOR

| id | line |
| --- | --- |
| `artist_partynextdoor_001` | Party Next Door. Late-night architecture. |
| `artist_partynextdoor_002` | P N D. Voice made for the hour you're listening at. |
| `artist_partynextdoor_003` | Party records sound like after the lights came down. |
| `artist_partynextdoor_004` | He under-sells. Song does the rest. |
| `artist_partynextdoor_005` | Slow rooms. Furnished well. |
| `artist_partynextdoor_006` | P N D. Soft-edged. Heavy. |

### Gunna

| id | line |
| --- | --- |
| `artist_gunna_001` | Gunna. Wun wun wun. Cadence is on. |
| `artist_gunna_002` | Pushin' P. Lifestyle as melody. |
| `artist_gunna_003` | Gunna again. Atlanta refinement. |
| `artist_gunna_004` | Wonderful Drip. Designer bars only. |
| `artist_gunna_005` | Gunna. Floats over the beat. Don't fight it. |
| `artist_gunna_006` | Slime. Gunna lane. Different mode. |

### Lil Uzi Vert

| id | line |
| --- | --- |
| `artist_lil_uzi_vert_001` | Uzi. The hyperactive cousin in the playlist. |
| `artist_lil_uzi_vert_002` | Uzi Vert. Energy first. Lyrics later. |
| `artist_lil_uzi_vert_003` | Philly's strangest child. We cool with it. |
| `artist_lil_uzi_vert_004` | Lil Uzi. Eternal Atake whatever the year. |
| `artist_lil_uzi_vert_005` | Uzi on the booth. Strap in. |
| `artist_lil_uzi_vert_006` | Uzi. Range goes from rage to ballad. Both work. |

### Ty Dolla $ign

| id | line |
| --- | --- |
| `artist_ty_dolla_sign_001` | Ty Dolla. Hookmaker since the Obama administration. |
| `artist_ty_dolla_sign_002` | Dolla Sign. Backbone of half your favorite features. |
| `artist_ty_dolla_sign_003` | Ty Dolla. Vultures co-pilot. Earns the credit. |
| `artist_ty_dolla_sign_004` | He can sing on anybody. Anybody. |
| `artist_ty_dolla_sign_005` | Ty's the voice you hear before you know it's him. |
| `artist_ty_dolla_sign_006` | Dolla. R and B genome. Plays well with everyone. |

### Sheck Wes

| id | line |
| --- | --- |
| `artist_sheck_wes_001` | Sheck. Mo Bamba forever. |
| `artist_sheck_wes_002` | Sheck Wes. Energy you don't measure. |
| `artist_sheck_wes_003` | Cactus Jack roster. Carries weight. |
| `artist_sheck_wes_004` | Sheck. Volume's a lyric for him. |
| `artist_sheck_wes_005` | Stamina is the song. Match it. |
| `artist_sheck_wes_006` | Sheck Wes. Five-second attention span. Ride it. |

### Quavo

| id | line |
| --- | --- |
| `artist_quavo_001` | Quavo. Migos OG. |
| `artist_quavo_002` | Quavo on the booth. Hook architect. |
| `artist_quavo_003` | Huncho. Auto-tune professor. |
| `artist_quavo_004` | Quavo. Atlanta style. Adlib game heavy. |
| `artist_quavo_005` | Three syllables, all hook. |
| `artist_quavo_006` | Huncho Jack era. Reminders of how good it was. |

### Ken Carson

| id | line |
| --- | --- |
| `artist_ken_carson_001` | Ken Carson. Opium pipeline. |
| `artist_ken_carson_002` | Carson on the track. Pull up. |
| `artist_ken_carson_003` | Ken. His sound is loud on purpose. |
| `artist_ken_carson_004` | Ken Carson. Energy budget — empty it. |
| `artist_ken_carson_005` | Carson. Don't expect a verse. Expect a wave. |
| `artist_ken_carson_006` | Ken Carson. Whether you like it or not — he's the future. |

### Imagine Dragons

| id | line |
| --- | --- |
| `artist_imagine_dragons_001` | Imagine Dragons. Different lane on this queue. |
| `artist_imagine_dragons_002` | Stadium-sized. Built that way on purpose. |
| `artist_imagine_dragons_003` | Drum kit drives this one. |
| `artist_imagine_dragons_004` | Anthem rock that earned the word. |
| `artist_imagine_dragons_005` | Big song. Don't over-think it. |
| `artist_imagine_dragons_006` | Imagine Dragons. Singalong incoming. |

---

## 7. Per-song banks (top 50)

Filtered with `songSlug`. 5 lines per song. Higher priority than artist
or generic. The personality leaks into per-song lines too — Future
tracks get genuine hype, Carti tracks get side-eye.

### WAIT FOR U — Future, Drake, Tems

| id | line |
| --- | --- |
| `song_wait_for_u_001` | Wait For U. Tems made the song. Pluto and Aubrey just stepped in. |
| `song_wait_for_u_002` | Future on the hook with feeling. Don't see that every record. |
| `song_wait_for_u_003` | Number one for a reason. Stay through the second verse. |
| `song_wait_for_u_004` | This is what happens when Pluto sings instead of raps. |
| `song_wait_for_u_005` | Future, Drake, Tems. Triangle that worked. |

### WIFI LIT — Future

| id | line |
| --- | --- |
| `song_wifi_lit_001` | WiFi Lit. Beast Mode 2 era. Pluto on autopilot. |
| `song_wifi_lit_002` | Zaytoven on the keys. Future on the truth. |
| `song_wifi_lit_003` | Pluto when he's loose. Hardest version. |
| `song_wifi_lit_004` | Beast Mode hits different. This one's the proof. |
| `song_wifi_lit_005` | Future at his most himself. Lock in. |

### Feds Did a Sweep — Future

| id | line |
| --- | --- |
| `song_feds_did_a_sweep_001` | Feds Did a Sweep. Pluto gives you a documentary in three minutes. |
| `song_feds_did_a_sweep_002` | Verses sound like surveillance footage. He means them. |
| `song_feds_did_a_sweep_003` | Future telling on himself a little. Trust him on it. |
| `song_feds_did_a_sweep_004` | Self-titled album energy. He's not playing. |
| `song_feds_did_a_sweep_005` | Pluto in confession mode. Listen close. |

### Slave Master — Future

| id | line |
| --- | --- |
| `song_slave_master_001` | Slave Master. DS2 deluxe. The cut nobody talks about, that everybody quotes. |
| `song_slave_master_002` | Future at his most paranoid. Feels true. |
| `song_slave_master_003` | Listen for the rage in the back of the mix. It's the song. |
| `song_slave_master_004` | Pluto with the curtain pulled. Heavy record. |
| `song_slave_master_005` | DS2 is a top-five Future album. This is one reason. |

### Like That — Future, Metro Boomin, Kendrick Lamar

| id | line |
| --- | --- |
| `song_like_that_001` | Like That. The verse that re-set the year. |
| `song_like_that_002` | Metro built the table. Future and K Dot set it. The room shifted. |
| `song_like_that_003` | If you only know this for one quote, you missed the song. |
| `song_like_that_004` | Three of the heaviest names on one beat. They earned the moment. |
| `song_like_that_005` | Pivot point for a year of rap. Hear it again. |

### Call The Coroner — Future (Live)

| id | line |
| --- | --- |
| `song_call_the_coroner_001` | Call The Coroner. Live cut. Pluto without the polish. |
| `song_call_the_coroner_002` | Live Future hits different. The voice cracks where it should. |
| `song_call_the_coroner_003` | Wizrd era. Performance mode. He delivered. |
| `song_call_the_coroner_004` | Listen for the room. The crowd's part of the track. |
| `song_call_the_coroner_005` | Future live. Rare format. Treat it like that. |

### Promise U That — Future (Live)

| id | line |
| --- | --- |
| `song_promise_u_that_001` | Promise U That. Live version. He's leaning into it. |
| `song_promise_u_that_002` | Pluto promising. Take him at his word. |
| `song_promise_u_that_003` | Wizrd-era Future. Catalog deep cut. |
| `song_promise_u_that_004` | Slow-burn ballad in his catalog. Few of these exist. |
| `song_promise_u_that_005` | Future on the live mic. Different gear. |

### Mask Off — Future

| id | line |
| --- | --- |
| `song_mask_off_001` | Mask Off. The flute. The legend. |
| `song_mask_off_002` | Future Hndrxx era. The song that broke containment. |
| `song_mask_off_003` | If this came on at a function in twenty seventeen — you remember. |
| `song_mask_off_004` | Percocets, molly, percocets. Generation-defining hook. |
| `song_mask_off_005` | Pluto's biggest song. Holds up. |

### March Madness — Future

| id | line |
| --- | --- |
| `song_march_madness_001` | March Madness. 56 Nights era. Future at the peak. |
| `song_march_madness_002` | "Ballin' like a March Madness." Cold opener forever. |
| `song_march_madness_003` | This is the era nobody could touch him. |
| `song_march_madness_004` | 2015 Future is on Mount Rushmore. This is one reason. |
| `song_march_madness_005` | Pluto in the mode. The catalog starts here for a lot of folks. |

### Codeine Crazy — Future

| id | line |
| --- | --- |
| `song_codeine_crazy_001` | Codeine Crazy. Monster mixtape closer. Heavy. |
| `song_codeine_crazy_002` | Saddest record in the Future canon. He sounds tired in a real way. |
| `song_codeine_crazy_003` | Twenty fourteen Pluto. Different season. |
| `song_codeine_crazy_004` | Listen for what he's not saying. The song's that. |
| `song_codeine_crazy_005` | Future with the curtain pulled. Few records like this. |

### SICKO MODE — Travis Scott

| id | line |
| --- | --- |
| `song_sicko_mode_001` | Sicko Mode. Three songs in a trench coat. |
| `song_sicko_mode_002` | Drake intro you can't skip. Beat switch you have to wait for. |
| `song_sicko_mode_003` | Three years to write this one. Listen for the seams. |
| `song_sicko_mode_004` | Middle eight is the song most rappers would have ended on. He starts there. |
| `song_sicko_mode_005` | Whatever version of this you've heard — there's one more. |

### STARGAZING — Travis Scott

| id | line |
| --- | --- |
| `song_stargazing_001` | Stargazing. First track of Astroworld. Doorway, not a song. |
| `song_stargazing_002` | He sets the table. Stay through the second half. |
| `song_stargazing_003` | If your night's about to start — this is where it starts. |
| `song_stargazing_004` | Astroworld's mission statement. Read it slowly. |
| `song_stargazing_005` | Travis opening the room. Let him do the work. |

### BUTTERFLY EFFECT — Travis Scott

| id | line |
| --- | --- |
| `song_butterfly_effect_001` | Butterfly Effect. Quietly rewired playlists for a year. |
| `song_butterfly_effect_002` | Loneliness with a flex on top. The flex is on the surface. |
| `song_butterfly_effect_003` | This song made small rooms feel cinematic. |
| `song_butterfly_effect_004` | Travis at his most floating. Don't reach for the railing. |
| `song_butterfly_effect_005` | Two minutes of weather. One minute of memory. |

### ASTROTHUNDER — Travis Scott

| id | line |
| --- | --- |
| `song_astrothunder_001` | Astrothunder. Comedown record. Lights low. |
| `song_astrothunder_002` | Quietest song on a loud album. Sometimes the quietest one's the truest. |
| `song_astrothunder_003` | He's not performing here. He's confessing. |
| `song_astrothunder_004` | Three minutes that say what the rest of the album sang. |
| `song_astrothunder_005` | Astroworld's exit ramp. Take it slow. |

### GOOSEBUMPS — Travis Scott, Kendrick Lamar

| id | line |
| --- | --- |
| `song_goosebumps_001` | Goosebumps. Travis hit. Kendrick verse. Both earned. |
| `song_goosebumps_002` | One of those records you forget how big it was. It was huge. |
| `song_goosebumps_003` | K Dot on a Travis hook. Doesn't happen often. Should happen more. |
| `song_goosebumps_004` | Listen for the way Travis stretches the chorus. That's the song. |
| `song_goosebumps_005` | Cactus Jack and Compton. Bridge worked. |

### FE!N — Travis Scott

| id | line |
| --- | --- |
| `song_fein_001` | F E I N. Travis on a Mike Dean engine. |
| `song_fein_002` | UTOPIA's biggest moment. Lives or dies on the chorus. |
| `song_fein_003` | The ad-lib became a meme. Don't let that ruin the song. |
| `song_fein_004` | Travis when he's all the way in. Lock in. |
| `song_fein_005` | UTOPIA cut. Chant material. |

### MELTDOWN — Travis Scott, Drake

| id | line |
| --- | --- |
| `song_meltdown_001` | Meltdown. Travis pulls Drake into UTOPIA. Drake brings the napalm. |
| `song_meltdown_002` | Aubrey verse goes for blood. He named names. |
| `song_meltdown_003` | This is Drake when he's reminded he can rap. |
| `song_meltdown_004` | Cactus Jack and OVO on the same record. Receipts. |
| `song_meltdown_005` | UTOPIA's bar-for-bar peak. Drake guested it home. |

### SIRENS — Travis Scott

| id | line |
| --- | --- |
| `song_sirens_001` | Sirens. UTOPIA late-night cut. |
| `song_sirens_002` | Travis when he goes ambient. Don't fight it. |
| `song_sirens_003` | This is the album for headphones. This is the song. |
| `song_sirens_004` | He's painting on this one. Look at the colors. |
| `song_sirens_005` | UTOPIA's quiet middle. Stay with it. |

### 8AM IN CHARLOTTE — Drake

| id | line |
| --- | --- |
| `song_8am_charlotte_001` | Eight A M in Charlotte. Drake when he's been quiet. |
| `song_8am_charlotte_002` | No hook. No reason to look for one. Just verses. |
| `song_8am_charlotte_003` | He's been writing morning-in-a-city tracks for a decade. This earns its place. |
| `song_8am_charlotte_004` | Pay attention to the names he drops — and the ones he doesn't. |
| `song_8am_charlotte_005` | Aubrey when he's already done what he had to do. |

### KNIFE TALK — Drake feat. 21 Savage & Project Pat

| id | line |
| --- | --- |
| `song_knife_talk_001` | Knife Talk. Project Pat's hook is a museum piece. |
| `song_knife_talk_002` | Twenty One brings the temperature. Drake brings the room. |
| `song_knife_talk_003` | Memphis cadence on a Toronto record. Bridges that work look like this. |
| `song_knife_talk_004` | Don't talk over the second verse. |
| `song_knife_talk_005` | Wasn't a single. Became one anyway. |

### IMY2 — Drake feat. Kid Cudi

| id | line |
| --- | --- |
| `song_imy2_001` | I-M-Y-Two. Drake with Cudi. Bittersweet record. |
| `song_imy2_002` | Cudi hum on the back. The Drake-Cudi friendship is the song. |
| `song_imy2_003` | Honestly Nevermind era cut. Quiet hit. |
| `song_imy2_004` | Drake at his most tender. He earns it here. |
| `song_imy2_005` | Two big-name singers. One conversation. Listen. |

### FIRST PERSON SHOOTER — Drake & J. Cole

| id | line |
| --- | --- |
| `song_first_person_shooter_001` | First Person Shooter. Two of the biggest in the booth at once. |
| `song_first_person_shooter_002` | Cole's verse is the one people quote. Drake's holds the song. |
| `song_first_person_shooter_003` | Listen for the line that started a feud. Quieter than you'd think. |
| `song_first_person_shooter_004` | Two veterans. No pretending. Re-listen. |
| `song_first_person_shooter_005` | "Is it K Dot. Is it Aubrey. Or me." That's the question that changed the year. |

### WHAT DID I MISS — Drake

| id | line |
| --- | --- |
| `song_what_did_i_miss_001` | What Did I Miss. Drake checking in with the room he left. |
| `song_what_did_i_miss_002` | Listen for the tone. Not the same as a year ago. |
| `song_what_did_i_miss_003` | When he's been quiet, he's been writing. This is what came out. |
| `song_what_did_i_miss_004` | First-single energy. Treat it like he meant it. |
| `song_what_did_i_miss_005` | Drake when he's playing catch-up. Listen for who's not in the room. |

### FROM TIME — Drake feat. Jhené Aiko

| id | line |
| --- | --- |
| `song_from_time_001` | From Time. Two voices. One conversation. |
| `song_from_time_002` | Jhene's verse is the song. He knew. That's why he gave her the room. |
| `song_from_time_003` | Slow vulnerability. Still works. |
| `song_from_time_004` | "I love me. I love me enough for the both of us." Line aged. |
| `song_from_time_005` | Album cut you don't skip if you know. |

### MEMBERS ONLY — Drake feat. PARTYNEXTDOOR

| id | line |
| --- | --- |
| `song_members_only_001` | Members Only. Drake and P N D do this in their sleep. |
| `song_members_only_002` | OVO inner-circle music. Sounds like a private room. |
| `song_members_only_003` | Party's hook. Drake's verse. Combination is a formula now. |
| `song_members_only_004` | Stay through the second verse. He digs in. |
| `song_members_only_005` | Slow-tempo OVO. Furniture for late-night driving. |

### 530 — Kanye West & Ty Dolla $ign

| id | line |
| --- | --- |
| `song_530_001` | Five thirty. Vultures Two. Yeezy in late-album mode. |
| `song_530_002` | Ty Dolla on the hook. Doing what he does. |
| `song_530_003` | Vultures era is divisive. This one's quietly one of the better cuts. |
| `song_530_004` | Don't let the discourse get in the way. The song's the song. |
| `song_530_005` | Kanye and Ty Dolla. Album partner energy. |

### PROMOTION — Kanye West & Ty Dolla $ign

| id | line |
| --- | --- |
| `song_promotion_001` | Promotion. Vultures Two. Late-Kanye energy. |
| `song_promotion_002` | Ty Dolla carrying the melody. Yeezy on the bars. Split labor works. |
| `song_promotion_003` | Album cut. Doesn't pretend to be a single. |
| `song_promotion_004` | Listen for the production. Always Kanye's strongest hand. |
| `song_promotion_005` | Vultures Two deep cut. Worth the spin. |

### RIVER — Kanye West & Ty Dolla $ign

| id | line |
| --- | --- |
| `song_river_001` | River. Vultures Two. Slow-tempo Kanye. |
| `song_river_002` | Ty Dolla in the hook. Voice you trust. |
| `song_river_003` | Late-Yeezy vulnerability. He still has this gear. |
| `song_river_004` | Don't skip this one early. It builds. |
| `song_river_005` | Vultures album moment. Stay in. |

### CARNIVAL — Kanye West, Ty Dolla $ign, Playboi Carti, Rich The Kid

| id | line |
| --- | --- |
| `song_carnival_001` | Carnival. Vultures One opener. Stadium-sized record. |
| `song_carnival_002` | Carti on the hook — yeah, even I admit it works here. |
| `song_carnival_003` | Crowd-chant chorus. Built for the back row. |
| `song_carnival_004` | Kanye still knows how to make a moment. This was one. |
| `song_carnival_005` | Vultures' biggest song. Ride the chant. |

### AFTER PARTY — Don Toliver

| id | line |
| --- | --- |
| `song_after_party_001` | After Party. Don Toliver's introduction record. |
| `song_after_party_002` | Heaven or Hell era. Cactus Jack honor roll. |
| `song_after_party_003` | The song most people knew Don from first. Holds up. |
| `song_after_party_004` | Auto-tune used right. Listen to the bend. |
| `song_after_party_005` | Don Toliver. Voice doing all the work. |

### K9 — Don Toliver feat. SahBabii

| id | line |
| --- | --- |
| `song_k9_001` | K9. Don Toliver in fog mode. |
| `song_k9_002` | SahBabii guest. Different texture. Works. |
| `song_k9_003` | Late-night Toliver. Not a single. A vibe. |
| `song_k9_004` | Listen for the synth bed. That's the song. |
| `song_k9_005` | Don when he's not going for the radio. Better mode. |

### ROSARY — Don Toliver feat. Travis Scott

| id | line |
| --- | --- |
| `song_rosary_001` | Rosary. Don and Travis. Cactus Jack family business. |
| `song_rosary_002` | Two voices that fit together. Not surprising. |
| `song_rosary_003` | Don leads. Travis answers. The trade-off is the song. |
| `song_rosary_004` | Hardstone Psycho era Don. Different gear. |
| `song_rosary_005` | When Travis features Travis-adjacent artists, it always works. |

### RENDEZVOUS — Don Toliver feat. Yeat

| id | line |
| --- | --- |
| `song_rendezvous_001` | Rendezvous. Don and Yeat. Strange pairing. Lands. |
| `song_rendezvous_002` | Yeat ad-libs in a Don Toliver song. New territory. |
| `song_rendezvous_003` | Listen for how Don bends to Yeat's tempo. Versatility. |
| `song_rendezvous_004` | Hardstone Psycho cut. Adventurous. |
| `song_rendezvous_005` | Two moods on one record. Both arrive. |

### CALLING — Metro Boomin & Swae Lee feat. NAV

| id | line |
| --- | --- |
| `song_calling_001` | Calling. Metro on the production. Heroes and Villains era. |
| `song_calling_002` | Swae Lee's hook is hypnosis. Don't fight it. |
| `song_calling_003` | Metro's beat does most of the work. Best kind. |
| `song_calling_004` | Heroes and Villains is a Metro masterclass. This is one reason. |
| `song_calling_005` | Producer-led record. Metro builds. The voices visit. |

### TRANCE — Metro Boomin, Travis Scott, Young Thug

| id | line |
| --- | --- |
| `song_trance_001` | Trance. Metro, Travis, Thug. Triangle of the era. |
| `song_trance_002` | The beat is Metro at his most cinematic. |
| `song_trance_003` | Travis and Thug on the same hook. Different cadences. Both land. |
| `song_trance_004` | Heroes and Villains highlight. Metro's victory lap. |
| `song_trance_005` | Producer puts the room together. Rappers furnish it. |

### SUPERHERO — Metro Boomin, Future, Chris Brown

| id | line |
| --- | --- |
| `song_superhero_001` | Superhero. Metro and Pluto. Heroes and Villains opener. |
| `song_superhero_002` | Future on the verses. Chris Brown on the hook. Both at peak. |
| `song_superhero_003` | Metro built a stadium beat. They filled it. |
| `song_superhero_004` | Heroes and Villains' opening statement. Strong. |
| `song_superhero_005` | Metro and Future. Always works. Doesn't get old. |

### Family Ties — Baby Keem feat. Kendrick Lamar

| id | line |
| --- | --- |
| `song_family_ties_001` | Family Ties. Keem and K Dot together. Cousin energy. |
| `song_family_ties_002` | Kendrick's verse is the moment. He knew, and stepped on it. |
| `song_family_ties_003` | Baby Keem set the table. K Dot ate. |
| `song_family_ties_004` | Two-man crew, one bloodline, one bar at a time. |
| `song_family_ties_005` | The verse Kendrick didn't put on Mr. Morale. He gave it to family. |

### Cocoa — Baby Keem feat. Don Toliver

| id | line |
| --- | --- |
| `song_cocoa_001` | Cocoa. Keem and Don. Smooth one. |
| `song_cocoa_002` | Don Toliver chorus. Keem verse. Soft pairing. |
| `song_cocoa_003` | Melodic Side Of Keem. He's got this lane too. |
| `song_cocoa_004` | The Melodic Blue era. Album cut you stay for. |
| `song_cocoa_005` | Two melodic voices. No fighting for the room. |

### Birds & the Bees — Baby Keem

| id | line |
| --- | --- |
| `song_birds_and_the_bees_001` | Birds and the Bees. Keem before he was on Kendrick's roster. |
| `song_birds_and_the_bees_002` | Early Keem. The blueprint was already there. |
| `song_birds_and_the_bees_003` | Listen to the cadence. He had this from day one. |
| `song_birds_and_the_bees_004` | Pre-Family-Ties Keem. Same energy. Different stage. |
| `song_birds_and_the_bees_005` | Keem record. Younger version. Same ear. |

### 2024 — Playboi Carti

| id | line |
| --- | --- |
| `song_2024_001` | Twenty twenty four. Carti track. Yeezy on the production. |
| `song_2024_002` | Look — the beat is Kanye-flavored. That's why I'm here. |
| `song_2024_003` | Whatever sounds Carti's making this year. Plug in. |
| `song_2024_004` | MUSIC era. Album-aware skip if you're not in. |
| `song_2024_005` | Carti record. I'll let it speak for itself. |

### JUMPIN — Playboi Carti, Lil Uzi Vert

| id | line |
| --- | --- |
| `song_jumpin_001` | Jumpin. Carti and Uzi. Two of a kind. |
| `song_jumpin_002` | Two of the loudest on the same record. Earplugs valid. |
| `song_jumpin_003` | This is rage rap as a sport. Score it however. |
| `song_jumpin_004` | If you're a Carti fan — this is for you. The rest of us — short verse. |
| `song_jumpin_005` | MUSIC era Carti with Uzi guest. Two friends. One frequency. |

### EVIL J0RDAN — Playboi Carti

| id | line |
| --- | --- |
| `song_evil_jordan_001` | Evil Jordan. Carti at his most Carti. |
| `song_evil_jordan_002` | Yeah I picked one. Library voted him in. |
| `song_evil_jordan_003` | Whole Lotta Red descendants. Take it for what it is. |
| `song_evil_jordan_004` | Three syllables. Same syllable, mostly. He commits. |
| `song_evil_jordan_005` | Carti. We're playing it. Don't email me. |

### Blinding Lights — The Weeknd

| id | line |
| --- | --- |
| `song_blinding_lights_001` | Blinding Lights. Number-one record of the decade. Earned. |
| `song_blinding_lights_002` | Synth-pop disguised as a pop song. Both arrive. |
| `song_blinding_lights_003` | After Hours era. Abel at the peak. |
| `song_blinding_lights_004` | This song spent half a year on the charts. Holds up. |
| `song_blinding_lights_005` | Eighties pulse, twenty twenty melody. Bridge worked. |

### Sacrifice — The Weeknd

| id | line |
| --- | --- |
| `song_sacrifice_001` | Sacrifice. Dawn FM era. Disco-Weeknd. |
| `song_sacrifice_002` | Bassline does most of the lifting. Let it. |
| `song_sacrifice_003` | Abel can dance now. He earned the freedom. |
| `song_sacrifice_004` | Dawn FM is a coherent album. Sacrifice is its pulse. |
| `song_sacrifice_005` | Weeknd in groove mode. Different gear. |

### Snitches & Rats Interlude — 21 Savage, Metro Boomin

| id | line |
| --- | --- |
| `song_snitches_and_rats_001` | Snitches and Rats. Savage Mode Two. Metro intro. Twenty One verse. |
| `song_snitches_and_rats_002` | Morgan Freeman narration. Yeah. Metro got him. |
| `song_snitches_and_rats_003` | Savage Mode Two intro is the best in rap that year. |
| `song_snitches_and_rats_004` | Twenty One when he means it. Quiet. Cold. |
| `song_snitches_and_rats_005` | Metro and Twenty One. The duo's discography is the era's. |

### Middle Child — J. Cole

| id | line |
| --- | --- |
| `song_middle_child_001` | Middle Child. Cole between generations. |
| `song_middle_child_002` | "I'm dead in the middle of two generations." That's the thesis. |
| `song_middle_child_003` | Cole when he's writing about position, not flexing it. |
| `song_middle_child_004` | One-take energy. He's not crowding the song. |
| `song_middle_child_005` | Cole's check-in record. Listen accordingly. |

### No Role Modelz — J. Cole

| id | line |
| --- | --- |
| `song_no_role_modelz_001` | No Role Modelz. Forest Hills Drive era. Cole's most quoted record. |
| `song_no_role_modelz_002` | "First things first, rest in peace, Uncle Phil." Doesn't get a worse intro. |
| `song_no_role_modelz_003` | Cole when he's being funny about pain. Both at once. |
| `song_no_role_modelz_004` | Twenty fourteen Cole. A whole generation moment. |
| `song_no_role_modelz_005` | Forest Hills cut. Nine times platinum. Ride it. |

### Talk — Yeat

| id | line |
| --- | --- |
| `song_talk_001` | Talk. Yeat in his pocket. |
| `song_talk_002` | Bell sounds. Auto-tune. Cadence. The formula. |
| `song_talk_003` | Yeat record. Don't try to translate it. |
| `song_talk_004` | This is what generation Z's listening to right now. Drop in. |
| `song_talk_005` | Yeat. He's an acquired taste. You acquired it. |

### The Color Violet — Tory Lanez

| id | line |
| --- | --- |
| `song_the_color_violet_001` | The Color Violet. Tory in songwriter mode. |
| `song_the_color_violet_002` | Pop-leaning Tory. Different lane than the rap. |
| `song_the_color_violet_003` | Listen for the harmonies. He's a producer too. |
| `song_the_color_violet_004` | Slow record. Earnest. Lanez can do this. |
| `song_the_color_violet_005` | Tory at his most accessible. Take it as that. |

### Natural — Imagine Dragons

| id | line |
| --- | --- |
| `song_natural_001` | Natural. Built for big rooms and bigger speakers. |
| `song_natural_002` | The drum kit in the chorus does most of the heavy lifting. Let it. |
| `song_natural_003` | Anthem rock that earns the word. |
| `song_natural_004` | "When the going gets tough." Wherever this catches you. |
| `song_natural_005` | Imagine Dragons doing what they do best. Lean in. |

---

## 8. Extending the bank

When you add a new song or artist:

1. **Try the artist bank first.** Artist sets cover most transitions.
2. **Generic clips already cover modes and intents.** Don't duplicate
   per artist unless the artist warrants a different tone.
3. **Naming convention:**
   - generic: `gen_<intent>_<NNN>`
   - mode intro: `mode_intro_<mode>_<NNN>`
   - artist: `artist_<artist_slug>_<NNN>`
   - song: `song_<song_slug>_<NNN>`
4. **Path layout under `<app_documents>/dj_voice_bank/`:**
   - `generic/<id>.opus`
   - `mode_intros/<mode>/<id>.opus`
   - `artists/<artist_slug>/<id>.opus`
   - `songs/<song_slug>/<id>.opus`
5. **Audio format:** Opus 32 kbps mono, 24 kHz. Loudness target around
   −16 LUFS.

---

**Total clip count v2:** 51 generic + 14 mode intros + 25 artists × 6
= 150 artist + 50 songs × 5 = 250 song = **465 lines**.

(v1 was 217. v2 is roughly twice the bank — most growth is in
per-song lines now that you have 743 tracks vs 124.)
