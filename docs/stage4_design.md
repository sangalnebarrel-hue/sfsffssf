# Stage 4 design: кража, защита, щит (single source of truth, rev. 2)

Designer pass, built on the four reports in this folder (`read_hooks.md`, `read_world.md`,
`read_ui_tests.md`, `research.md`), on `docs/stage3_design.md` (whose conventions this document keeps)
and on the code at commit `2f19d6d`. Implementers follow this document. Where it says nothing, the
reports, `docs/stage3_design.md` and `tools/builder/gui/STYLE.md` apply. Every number below goes into
a config ModuleScript (§2.6). Nothing is a "magic" number in code.

**Rev. 2** applies the two critiques in this folder (`critique_design.md`, items DC-nn: kid fairness and
fun; `critique_backend.md`, items BE-nn: data safety, exploits, testability). Every item and what was
done with it is listed in §11 «Решения по критике». The body below is already the revised design. The
implementation reviews add their decisions there too (§11.3 Wave 0, §11.4 Wave 1 A: the server core, §11.5 Wave 1 B: the world, and the
thief's TheftBar moved to the bottom band — §6.4 rev. 3).

**Scope.** Stage 4 only: the theft (a 3 s hold, then carrying the fish out of the plot), the owner's
alert and the flashing lamp, the dog, the alarm («сигнализация»), the lock («замок», **level 1 only**:
the levelled «Лучший замок» is Stage 5), the shield (button, cooldown, on-screen timer), the fairness
rules that keep a kid's losses small, the anti-dupe transfer, and the «ЗАЩИТА» sheet that sells the
defences. **Stage 5 is not started**: no rod, slot or lock-level purchases, no shop tabs, no UI polish
pass. Every Stage 5 hook is named in §4.12.

Paths are relative to `/home/user/sfsffssf`. Coordinates are base-local, as in the reports: `Root` at
the origin, y = 0 is the ground top, −Z points to the lagoon, the plot is x ±68 and z 18..168.

---

## 0. Decisions at a glance

| # | Question | Decision (and the short why) |
|---|---|---|
| D1 | Theft model | **Hold 3 s, then carry the fish out of the victim's plot** (Steal-a-Brainrot, and the user's reference with its «БЕЗОПАСНАЯ ЗОНА» line). The hold lifts the fish onto the thief's head. The fish **becomes the thief's when he crosses the plot edge** (≈ 44–50 studs, ≈ 3.5 s). During the hold and the carry the fish **stays in the victim's data**, so a crash in that time cannot duplicate it. Only a carry gives the dog, the owner and the alert something to do. A flag `StealConfig.Carry.Enabled = false` falls back to the spec-literal mode, where the fish moves at the end of the hold (§9 R1; server path and one test only, DC-19). The README says the rule in its first line (DC-22). |
| D2 | What ends a theft early | **Hold:** the button released, the thief left the radius (6 + 2 studs), died, left the game or reset; the owner's shield went up; the owner came within 6 studs ("tag"); the owner left; no `Triggered` arrived by `need + 1.5 s`. **Carry:** died, left the game, tagged by the owner, **the owner's shield went up (DC-01)**, 25 s timeout, the speed budget overdrawn or a teleport (§4.4), the owner left. A cancelled hold or carry puts the fish back in its display. |
| D3 | What can be stolen | Any **active** fish (not dormant, not escrowed, not already being stolen, **not caught in the last 30 s**: DC-08), Mythic included: it is the genre's prize. The victim must have **≥ 3 active fish**, so a kid is never left with fewer than 2. A stolen fish keeps **Id, Kg, Mutation and its Age (value growth)**. A theft is zero-sum, so keeping the growth creates no money. |
| D4 | The thief's full tank | **"Steal up, not down."** A free slot → the fish is stored. A full tank → the Stage 3 rule: if the loot earns more than the thief's weakest fish, the weakest is auto-sold (coins from the thief's **own** fish) and the loot takes its slot. Otherwise the steal is **refused before the hold starts** («Садок полон — эта рыба слабее твоих»). The client hides those prompts. A stolen fish is never auto-sold, so the money dupe (read_hooks G-04) cannot happen, and a rich kid cannot farm a poor kid's Commons. |
| D5 | Limits | One theft at a time **per thief** and **per victim base**. The thief waits **30 s** after a success. After a failure he caused he waits **3 / 10 / 30 s** (1st / 2nd / 3rd within 60 s; an `early` trigger → 30 s at once); after being **tagged** he cannot start on **that base** for **20 s** (DC-10, BE-19). Nothing can be stolen from an offline player: the base leaves with its owner. A thief needs his own base. (The rev. 1 pair limit is gone: the victim cap of D21 covers it, DC-06.) |
| D6 | Free protection | **Join protection 90 s** after the tank mounts; **300 s «защита новичка»** on the first session of a new save (`SaveCount == 0` at load, DC-07); **20 s** if the player left this server or was last online < 5 min ago, so a rejoin cannot farm it. The **90 s immunity** after being robbed, and the **«садок отдыхает»** rest after a 2nd loss (D21), use the same chip. **Starting a steal ends all of your own protection** (and forgets your recent losses): a thief cannot hide behind a shield. A hint says so before the hold. 15 s before join/newbie protection ends, a toast teaches the shield (DC-07). |
| D7 | Shield (щит) | **Free.** It lasts **60 s** and is ready again **240 s after activation** (60 on + 180 cooldown). The ready time is **saved** (`Upgrades.ShieldReadyAt`, `os.time`), so a rejoin does not reset it. Raising it **cancels a hold on your base and returns a fish that is being carried** (it flies home; DC-01): «Никто не украдёт 1 минуту» is literally true. It is refused only while your remaining protection is ≥ 60 s (no cooldown spent; DC-03 lets it top up a protection that is about to end) and while you are stealing. |
| D8 | Lock (замок) | `LockLevel` sets the hold time. **Stage 4 sells level 1 only** (DC-11): **$1 500, hold 3 → 4 s**, a one-time buy on the «ЗАЩИТА» sheet like the dog and the alarm. The levelled «Лучший замок» is a Stage 5 shop item: its table (levels 2–5: **5.0 / 6.0 / 7.5 / 9.0 s, $5 000 / $15 000 / $40 000 / $100 000**) is already in `DefenceConfig.Lock.Levels`, every level works at runtime, and `Lock.SaleMax = 1` is the only thing Stage 5 raises. The time is captured when the hold starts. |
| D9 | Dog (собака) | A one-time **$6 000**. Visible **only when owned** (README); then it **sleeps in the court** at (6, 58), between the fountain and the big tank (DC-05), so it reaches every starting display during a lock-0 hold. The kennel stays at the fence. It is a **logical dog on the server**: a point that runs at **24 st/s** to the active thief, only while a theft is on. Within **5 studs** the thief's WalkSpeed is **×0.5** (and it lingers 1 s). Clients animate the existing 13-part shiba from 3 attributes. It never chases visitors. |
| D10 | Alarm (сигнализация) | **Baseline for everyone** (the spec): the owner is alerted the moment a hold starts, and the lamp flashes at 2 Hz. **The $2 500 upgrade adds:** (1) an **early warning** when another player enters your plot (once per 45 s per player, never while you are protected), so you can raise the shield before the hold; (2) the thief is **marked** for everyone (a red `Highlight`, seen through walls by the owner, and a «ВОР!» tag); (3) a siren (a spinning red light and a beep loop; the bell swing and red lanterns are P2, DC-17). |
| D11 | Owner's counterplay | **Tag**: the owner's character within **6 studs** of the thief (hold or carry) → the fish goes home («Рыба спасена!»), and that thief cannot start on this base for 20 s. **«ДОМОЙ» during an alert** lands the owner on his spawn **facing the court** (not the gate). **ЩИТ** works in the hold and the carry (D7). While carrying, the thief cannot use «ДОМОЙ», start another steal or raise a shield. |
| D12 | Where defences are bought | A new third right-column button **«ЗАЩИТА» 🛡️** opens the **«ЗАЩИТА» sheet** (the Stage 3 `gui/Sheet` shell) with four cards: Щит · Собака · Сигнализация · Замок. It is built as the future shop's first page: Stage 5 renames the button to «МАГАЗИН» and adds tabs (§4.12). During an alert, while the shield is ready, the same button becomes a **one-tap «ЩИТ!»** that works even mid-minigame. |
| D13 | Anti-dupe | The Stage 3 §4.8 order, hardened: **one synchronous `TankService:StealFish`** that applies a precomputed plan (no yield, no signal before the escrow exists) → `SaveSoon(victim)` → the thief's copy is **escrowed** (not saved, not sellable, not stealable, earns nothing) until the **victim's record** commits that seq. The escrow entry is **registered before the fish enters the thief's data** and keyed by the thief's `Player`, matched by the victim's `Player` (BE-2, BE-3). A thief who leaves mid-escrow **gives the fish back to the victim**, also when the victim is already leaving (`DataService:AmendLeaving`, BE-1). Shutdown returns escrows before the close saves. A victim whose save never lands (`DataService.Released`) **voids** the thief's copy. Every path is idempotent (BE-4). **No path duplicates a fish.** The only losses (one fish, never two) are a hard crash inside the thief's ≈ 6–7 s key gap, a both-leave race narrowed to one request, and a lost write reply (§3.3). |
| D14 | Prompts | One default-style `ProximityPrompt "StealPrompt"` per display (96), created by the server: «Украсть» / «Окунь · +$4/с», `HoldDuration` from the owner's lock, **`MaxActivationDistance 6`**, `RequiresLineOfSight = false` (explicit), `Exclusivity OnePerButton`. The **server times the hold itself**. Server `Enabled = mounted and the slot holds a fish`, nothing else. The client hides a prompt by setting its **local `MaxActivationDistance = 0`** (a property the server never writes again, so replication cannot undo it; BE-14/15): on its own base and on fish it cannot steal. |
| D15 | Speed | One server **modifier stack** (`Lib/Speed`): `WalkSpeed = 16 × max(0.4, Π factors)`. The carry is ×0.85 and the dog ×0.5. `Speed` owns expiry with its own timer, and **every theft end clears every modifier** first (BE-10). The carry is checked with a **leaky distance budget** every tick, so a client that keeps `WalkSpeed 16` under the dog is caught in ≈ 2.5 s while an honest phone with a lag spike is not (BE-9). |
| D16 | Victim's UI | A **«ВОР В САДКЕ!» alert plate** in the toast slot, with a **big [🛡️ ЩИТ]** (≥ 56 px, the largest target; in the hold **and** the carry; a Slate «⏳ 1:12» while on cooldown) and [🏠 ДОМОЙ]. It is allowed during the bite and the minigame (it never takes the minigame's input), and it **outranks the catch card**: the card takes its normal close path and the plate pops in within ≈ 1 s (DC-02). Zero-layout layers: a thin Berry edge pulse, «ДОМОЙ» and «ЩИТ!» glowing, the red pier word «🚨 КРАДУТ!», 3 pings. Afterwards a result toast: «Украдено: …» + «Садок отдыхает 1:30 — никто не украдёт», or «Рыба спасена!». |
| D17 | Thief's UI | A **top banner** like the reference's «Украдите яйцо!»: «КРАДЁШЬ: ОКУНЬ» with a progress bar (the finger covers the stock ring on phones). Then «БЕГИ ЗА ОГРАДУ!» with a draining 25 s bar, a red guide beam to the nearest exit and a «🐕 СОБАКА!» chip while slowed. At the edge: the slam «ДОБЫЧА!», confetti, and the 🐟 flies into «САДОК». A failure shows «СОРВАЛОСЬ!» and the reason. |
| D18 | Shield timer | The reserved glass chip **«🛡️ 0:42»** docked at the right end of `Status.BaseBadge` (Stage 3 K-19). It shows any protection of your base: shield, join, newbie, after-theft, rest. In the world the **shield only** gets a client-local ForceField dome over the court (≤ 2 domes on phones; DC-15); every protection shows «🛡️ 0:42» on the tank sign and on the flag's `OwnerSign`, which is seen across the map. |
| D19 | Economy | Prices are set against the Stage 3 median (§3.5 there): $1.2K at 2 min, $3K at 3, $8.8K at 5, $34K at 10. The lock and the alarm come at ≈ 2.5–3 min, the dog at ≈ 4.5 min, so with the 5-minute newbie protection a median kid owns lock + alarm (and nearly the dog) before he is ever exposed. The shield is free. A theft creates no coins: the escrowed fish earns nothing until the commit, and the carried fish earns its owner nothing. |
| D20 | Kid-safe copy | Friendly, never shaming. Names appear only to the two people involved (no server-wide «X обокрал Y»). There is always an action. A defence is celebrated. One **loud** alert per (thief, victim) per 30 s; later ones update the plate quietly. No display numbers («№3»), no «чужой» (a visitor may be a friend), one tip per loss. Russian text avoids gender and case agreement («Ника крадёт: Окунь», «ДОБЫЧА!»). |
| D21 | Fairness (new in rev. 2) | The Monte-Carlo in `critique_design.md` §2 showed that a rev. 1 victim could lose 7 fish (−78 % income) in 10 min. So: **at most 2 losses per victim per rolling 10 min** (after the 2nd, «садок отдыхает» until the older loss is 10 min old; DC-06); **no stealing a fish caught < 30 s ago** (DC-08); **no robbing a much weaker player** (thief income > 3× victim's and ≥ $20/s → refused; DC-09); a 5-minute newbie protection (DC-07); and the shield covers the carry (DC-01). Every knob is in `StealConfig.Limits` / `DefenceConfig.Shield`. |

---

## 1. The loop

### 1.1 The thief (a kid on a phone)

1. He walks into a foreign base. Through the arcade ends he sees the displays, with the Stage 3 aisle
   tags «+$4/с · $45». The tank sign over the big tank shows «+$42/с · 🐠 6/6» and a third line with the
   owned defences, «🔐1 · 🐕 · 🚨», and «🛡️ 0:42» while the base is protected (DC-12).
   - **First time per session** in a foreign court with stealable fish, the top banner shows the hint
     «Зажми «Украсть» у витрины и унеси рыбу за ограду!» (PC: «Держи E у витрины…»).
2. Next to an occupied display: the stock prompt «**E Украсть** · Окунь · +$4/с». The ring takes 3 s,
   or 4 s with a lock. The prompt shows only on fish he can take (§5.1). If he cannot steal right now,
   the top banner explains why, on glass: «⏳ Снова красть через 0:24», «🛡️ Здесь щит — ещё 0:42»,
   «Садок отдыхает — ещё 6:12», «Садок полон — эта рыба слабее твоих», «У игрока мало рыбы», «Свежий
   улов — красть можно через 0:21», «Этот игрок пока намного слабее — найди соперника по силе». If he
   has protection of his own, it says «Начнёшь красть — твоя защита погаснет».
3. **The hold.** The banner «🥷 КРАДЁШЬ: ОКУНЬ» shows a bar that fills to the server's end time, «НЕ
   ОТХОДИ!». In the world the fish rises 1.6 studs and struggles, the display pulses red, and a word
   «КРАДУТ!» with a ring timer floats over it. If the owner has a dog, a «ГАВ!» pops in the court and
   the dog starts running.
4. **The hold completes.** The fish leaps out through the glass onto his head (`StolenFish`, raised arms
   if the pose fits the budget). He slows to ×0.85. The banner turns into «🏃 БЕГИ ЗА ОГРАДУ!» with a
   draining 25 s bar. A red guide beam on the ground points from him to the nearest exit (the gate, a
   side fence that can be jumped, or a back trellis arch). «ДОМОЙ» is greyed out with the lock look.
5. **The dog** (if the owner has one) catches him: «🐕 СОБАКА! МЕДЛЕННО» flashes on the banner, he walks
   at half speed, dust puffs at his feet.
6. **He crosses the plot edge** → «ДОБЫЧА!» slams into the top band, with «Окунь — в твоём садке ·
   +$4/с» under it. Confetti, a 🐟 flies from his head into «САДОК», the chip rolls 4/6 → 5/6, and his
   display gets the fish with the Stage 3 `in` splash. If his tank was full, «ЗАМЕНА!» plays and the
   coins for his own weakest fish fly in (Stage 3 replaced flow). From now on he waits **30 s** before
   the next steal.
7. **Failure** at any point: the banner blushes Berry and shakes, «СОРВАЛОСЬ!», and one plain line names
   the reason («Хозяин тебя поймал!», «Ты отошёл от витрины», «Хозяин включил щит — рыба вернулась
   домой», «Слишком долго — рыба уплыла домой»…). The fish flies back to its display. He waits 3 s,
   then 10 s, then 30 s for repeated failures he caused within a minute; after a tag he cannot start on
   that base for 20 s. A shield or the owner leaving costs him no wait (not his fault).

### 1.2 The victim (usually on his own pier, fishing; the court is behind the camera)

1. **Another player enters his plot** (only with the alarm upgrade, and only while he is not
   protected): a soft toast «👀 Ника у тебя во дворе!», the lamp blinks slowly, and the «ЗАЩИТА» button
   bobs. He can raise the shield now and nothing can be started.
2. **A hold starts on his base.** In one frame:
   - **The alert plate** «🚨 ВОР В САДКЕ!» / «Ника крадёт: Окунь» with a big [🛡️ ЩИТ] (Slate «⏳ 1:12»
     while the shield recharges) and [🏠 ДОМОЙ].
   - Three pings, a thin Berry edge pulse, «ДОМОЙ» glowing Berry, and «ЗАЩИТА» → «ЩИТ!» glowing.
   - The pier word over his bucket turns into a red «🚨 КРАДУТ!».
   - At the base: the lamp flashes red (2 Hz) and his dog starts running.
   - If a catch card is on screen, it closes through its normal path (the fish still flies into
     «САДОК») and the plate pops in about a second later (DC-02).
3. **What he can do:**
   - **ЩИТ** (one tap, from the plate or the column button, even mid-minigame), in the hold **or** the
     carry: the theft ends and the fish stays or flies home. Result: «Щит спас рыбу! 🛡️ 1:00».
   - **ДОМОЙ**: he lands on his spawn facing the court, 38–85 studs from the displays, and can run at the
     thief. Coming within 6 studs = a tag, «Вор пойман — рыба спасена! 💪» with confetti.
   - If the hold already completed, the plate changes to «🏃 ВОР УБЕГАЕТ!» / «Ника уносит: Окунь — жми
     ЩИТ!» (or «Ника уносит: Окунь» when the shield is not ready), with the same two buttons.
   - **If he is stealing himself** at that moment, the plate shows no buttons and reads «Пока крадёшь
     сам, щит не включить» (his «ДОМОЙ» is guarded and the shield is refused; DC-04).
4. **The result.**
   - Lost: a big toast «Украдено: Окунь (Ника)» + «Садок отдыхает 1:30 — никто не украдёт». The Wallet
     rate rolls down with a Berry flash, «САДОК» flashes Berry and the chip rolls 6/6 → 5/6, the display
     shows «УКРАДЕНО!» for 2 s, and the shield chip «🛡️ 1:30» shows the **90 s immunity**. After a 2nd
     loss within 10 min the chip shows the longer rest («🛡️ 6:12»). **One tip per loss**: if the
     shield was ready and unused, «Совет: жми 🛡️ ЩИТ, как только увидишь «ВОР В САДКЕ!» — он
     бесплатный»; otherwise the cheapest defence he lacks, with its price (DC-14).
   - Saved: «Рыба спасена! 💪» with the reason (tag, shield, the thief fell or ran out of time, the thief
     left the game). A hold shorter than 1 s that the thief ended (or nobody did) ends quietly (no toast,
     no pings: BE-19); the owner's own tag or shield is always celebrated, however early (D20, A2-04).

### 1.3 Bystanders

They see the fish lifted and struggling, then flying onto the thief's head, and the thief running with
it (its nameplate «🥷 Окунь $45»). They see the lamp flashing. With the victim's alarm upgrade they also
see the thief's red outline and «ВОР!», and hear the beeps when within 120 studs. They get no toast.

### 1.4 Why a carry (D1), checked against the timings

Distances are from `read_world.md` §2. Speeds: 16 studs/s, carry 13.6, with the dog 6.8.

| lock | hold | carry, no dog | from alert to loss, no dog (= the shield window) | with dog | owner via «ДОМОЙ» (≈ 1.5 s to react + 1 s to turn) |
|---|---|---|---|---|---|
| 0 | 3.0 | 3.2–3.7 | ≈ 6.5 s | ≈ 9.5–10.5 s | lands 16 studs from the gate: can tag a thief leaving by the gate |
| 1 (Stage 4) | 4.0 | same | ≈ 7.5 s | ≈ 11 s | reaches slots 1–2 early in the carry: tags a thief heading for the gate |
| 5 (Stage 5) | 9.0 | same | ≈ 12.5 s | ≈ 16 s | reaches any display during the hold |

- **The shield window is the whole column "from alert to loss"** (DC-01). The `critique_design.md` §1
  timeline: a kid mid-minigame taps at ≈ 3–3.5 s, one on an Epic card at ≈ 4.5–6 s (now ≈ 3.5 s with
  DC-02). Both are inside 6.5 s, so the free defence works for a fishing kid, not only an idle one.
- **Model A (credit at the end of the hold)** leaves the dog nothing to slow, because the thief stands
  still while holding. The alert would only report a loss.
- **Model C (carry to one's own base, SAB-exact)** means a 306–800-stud chase across the hub, and it needs
  a "drop on the ground" system.
- **Model B** gives a 3–7 s chase that kids understand at once ("run past the fence"). The spec's «если
  вор умер или вышел из радиуса, кража прерывается» stays literally true during the hold. Death also
  ends the carry.

### 1.5 Rule list (what the server enforces; §4.3 has the check order)

| rule | value | config |
|---|---|---|
| thief ≠ owner; both loaded (`CanWrite`) | — | — |
| thief has a mounted base | — | — |
| one active theft per thief / per victim base | 1 / 1 | — |
| victim's active fish | ≥ 3 | `StealConfig.Limits.MinFishToRob` |
| thief cooldown after a success | 30 s | `ThiefCooldown` |
| thief cooldown after his own failures within 60 s (`early` → the last step at once) | 3 / 10 / 30 s | `FailCooldown`, `FailWindow` |
| after being tagged, on that base | 20 s | `TagCooldown` |
| victim immunity after a loss (`after`) | 90 s | `VictimImmunity` |
| victim cap (`rest` after the 2nd loss, until the older loss is 600 s old) | ≤ 2 losses / 600 s | `VictimMax`, `VictimWindow` |
| a fish just caught | not stealable for 30 s | `FreshCatch` |
| a much weaker victim | refused when thief income ≥ $20/s and > 3 × the victim's | `RichMin`, `RichRatio` |
| join protection | 90 s; 300 s on a new save; 20 s on a quick rejoin (< 300 s) | `DefenceConfig.Shield.JoinProtect`, `JoinProtectFirst`, `QuickRejoin`, `QuickRejoinProtect` |
| prompt reach / server reach | 6 / 6 + 2 studs (3D from `PromptAttachment.WorldPosition`) | `StealConfig.Prompt.MaxDistance`, `Slack` |
| owner tag | 6 studs, horizontal, HRP ↔ HRP | `StealConfig.Tag.Range` |
| carry timeout | 25 s | `StealConfig.Carry.Timeout` |
| carry speed | leaky budget (§4.4) | `StealConfig.Carry.Speed` |
| plot exit | outside x ±(68 + 2) or z ∉ [18 − 2, 168 + 2], on a tick with the budget ≥ 0 | `MapConfig.PlotHalfWidth/PlotFront/PlotDepth` + `Carry.ExitMargin` |
| the fish | active, not escrowed (`fresh`), not new (`new`), not dormant, the slot's `FishUid` | — |
| the thief's tank | free slot, or the loot's `Income10` > the thief's weakest active fish | `TankRules.ChooseReplacement` |

---

## 2. Defences, prices and the config modules

### 2.1 The dog

- **Owning it.** `Upgrades.Dog = true` (bought once, $6 000). On mount (and right after the purchase)
  `DefenceService` shows the base's `Dog`:
  - every BasePart gets `Transparency = 0` and `CastShadow = true` on Body, Head and the kennel Walls/Roof;
  - the kennel `Walls` and `Roof` get `CanCollide = true`; the pup stays non-colliding (it never blocks
    anyone);
  - **the pup moves to its guard spot in the court** (DC-05): one server `Dog.Pup:PivotTo` to
    `Dog.Rest` (base-local (6, 58), between the fountain basin and the big tank, facing the gate). It
    replicates once. The kennel stays at the front fence as the "this base has a dog" sign;
  - `Dog:SetAttribute("Unlocked", true)`.

  Unmount restores the template state exactly, including the pup's template pivot (`stage1_bases` pins
  it on a fresh base; BE-27).
- **Builder change (0 parts):** the 13 pup parts move into a sub-model `Dog.Pup` (PrimaryPart `Body`).
  `Dog.PrimaryPart` stays `Body`. The server and the client move the pup with one `Pup:PivotTo` and the
  kennel stays put.
- **The brain** (`Lib/DogBrain.luau`, server, pure steps). One state per base: `Pos` (base-local, on the
  ground), `State` (`Sleep` / `Alert` / `Chase` / `Return`), `Target` (the thief).
  - Asleep at `Dog.Rest`. From the gate every view crosses the court, so the dog is seen.
  - A theft starts on the base → `Alert` for 0.4 s («ГАВ!»), then `Chase` at `RunSpeed` 24 st/s towards
    the thief, in a straight line: the arcade's court side is open between its posts (`read_world` §2),
    and the pup never collides. One waypoint remains for a dog that is **in front of the arcades**
    (z < 54.5, for example after a chase out of the gate) while the thief is inside an aisle: it first
    runs to that aisle's open end (±27, 54) (`StealRules.DogWaypoint`).
  - Leash: clamped to the plot rect + 4 studs. At the fence it stops and barks.
  - Bite: horizontal distance ≤ `BiteRange` 5, **only while `TheftOn(base)` is live and its thief is this
    dog's target on that tick** (BE-10) → `Speed.Set(thief, "Dog", 0.5, now + SlowLinger 1)`, refreshed
    every tick while in range. A refresh writes no attribute. The Player attribute `Slowed` is a
    **boolean**, written by `Lib/Speed` only when the `Dog` key appears or disappears (BE-11).
  - The theft ends → `Return` at 10 st/s → `Sleep` at the rest spot. A dog in `Return` never bites.
  - It is ticked at 10 Hz by StealService's watcher only while it is awake (§4.4).
  - Replication on the `Dog` model: `DogState`, `DogPos` (a world Vector3, written only when the dog
    moved more than `MoveEpsilon` 0.25 studs since the last write and at most every 0.2 s; BE-23),
    `DogTarget` (the thief's UserId or nil).
  - **Unmount** (BE-27): `Pos` back to the rest spot, `Sleep`, `Target = nil`, attributes cleared, the
    dog hidden.
- **Effect in numbers:** during the hold the dog arrives and sits barking (the thief stands still).
  Arrival from the rest spot, `AlertDelay` included: **1.3 / 1.5 / 1.8 s** at slots 2 / 4 / 6 and
  **1.8 / 1.9 / 2.2 s** at slots 1 / 3 / 5, all under the 3.0 s lock-0 hold (from the rev. 1 kennel
  spot the west slots took 3.2–4.3 s). Stage 5's back slots 7–12 take ≈ 2.1–3.2 s, still in time for the
  carry. (The straight run to slot 5 grazes the big tank's front-west corner: R7.) On the carry it keeps up (24 > 13.6), so the thief walks at 6.8 st/s and the 44–50 studs take
  ≈ 6.5–7.4 s instead of 3.5. That is the owner's window.
- **P2:** the awake dog trots after a visitor in the plot (DC-05, "the dog is watching me").

### 2.2 The alarm («сигнализация»)

| | baseline (every base: the spec) | with `Upgrades.Alarm` ($2 500) |
|---|---|---|
| when the owner hears | at the **hold start** | also when **another player enters the plot** (DefenceService, 1 Hz, only bases with the alarm; once per 45 s per player; **not while the base is protected**) |
| alert | the plate + pings + edge pulse + pier word (§1.2) | + the early «👀 Ника у тебя во дворе!» |
| lamp | `Alarm.Lamp` flashes Neon red ↔ `LampOff` at 2 Hz, a red PointLight (client, from the base attribute `AlarmState = "theft"`) | + a spinning red SpotLight (siren) and an `electronicpingshort` beep loop within 120 studs; `AlarmState = "intruder"` flashes at 1 Hz. (The bell swing and the red court lanterns are P2: DC-17.) |
| the thief | his fish is visible over his head | + a red `Highlight` (AlwaysOnTop on the owner's client, Occluded for others) and a «ВОР!» billboard, for everyone, during the hold and the carry |

The lamp flashes during the hold and the carry, then for `StealConfig.Alarm.Linger` 3 s more.

### 2.3 The lock («замок»)

- `PlayerData.LockLevel` (exists, default 0). The hold time: `StealRules.HoldTime(level) =
  DefenceConfig.Lock.Levels[level].Hold`, or `Lock.BaseHold` 3 for level 0. A level above `#Levels`
  (from a newer server) is kept verbatim in the data and counts as `#Levels` at runtime (Stage 3 B-6
  rolling-update rule). Every level works at runtime; **only levels ≤ `Lock.SaleMax` (1) are sold**
  (DC-11).
- The server writes `HoldDuration` on the 12 prompts of the base on mount and on a purchase, **except a
  prompt that is being held**, which gets the new value at the end of its theft (BE-18). Base
  attributes `LockLevel` and `HoldTime`. The hold captures `need` when it starts.
- **Visible lock, 0 parts:**
  - the prompt's own ring (a longer fill);
  - the big tank sign `FxTankSign`: «🔐1» in its defences line (client, §5.3);
  - the «ЗАЩИТА» card.

  **Never a bare 🔒 on the displays**: «🔒 Закрыто» already means "slot not bought" (`read_world` #4).

### 2.4 The shield and the free protections

- **One protection state per base**, owned by DefenceService:

  ```
  ProtectUntil = max(ShieldUntil, JoinUntil, AfterUntil, RestUntil)
  ProtectKind  = the kind that ends last ("shield" | "join" | "newbie" | "after" | "rest")
  ```

  Base attributes `ProtectUntil` (AttrTime) and `ProtectKind` (nil once expired).
- **Expiry:** one `task.delay` per base with a generation token (never more than one pending per base).
  At expiry: clear the attributes, fire `DefenceService.ProtectionChanged(base)`, send the owner «Щит
  погас» (shield kind only).
- **Activation** (`ShieldActivate`, §4.10) is accepted while the remaining protection is **below
  `Shield.StackBelow` (60 s)** (DC-03: a kid whose immunity ends in 2 s can still raise the shield):
  - `ShieldUntil = now + 60`.
  - `ShieldReadyAt = now + 240`. The Player attributes `ShieldUntil` and `ShieldReadyAt` (AttrTime).
  - `Upgrades.ShieldReadyAt = os.time() + 240`, then `SaveSoon`.
  - `ProtectionChanged` → StealService ends a theft on the base: a hold is cancelled, a **carry is
    returned** (reason `shield`, the fish flies home, no fail cooldown for the thief; DC-01).
- **On load:** `readyIn = clamp(Upgrades.ShieldReadyAt − os.time(), 0, Duration + Cooldown)`. The
  attribute is `serverNow + readyIn`. The active shield is **not** saved: it ends with the session, and
  the join protection covers the rejoin.
- **What the join protection needs is read at `DataService.Loaded`**, before any save of the session
  rewrites `LastOnline` and `SaveCount` in the live data (BE-25): DefenceService keeps
  `loadInfo[player] = { SaveCount, LastOnline }`.
- **Join protection** is set on the first mount of the session (`TankService.Mounted`), first match
  wins:
  1. **quick rejoin** → `QuickRejoinProtect` 20 s, kind `join`: `LastOnline` at load is less than
     `QuickRejoin` 300 s ago, **or** this server's time-bounded `leftAt[userId]` is (it also covers Memory
     mode, where `LastOnline` stays 0);
  2. **a new save** (`SaveCount == 0` at load) → `JoinProtectFirst` 300 s, kind `newbie` («Защита
     новичка 5:00 🛡️ — лови спокойно!»; DC-07);
  3. otherwise → `JoinProtect` 90 s, kind `join`.

  `EndingWarn` 15 s before a `join` or `newbie` protection ends, the client shows «Скоро воры смогут
  красть. Увидишь «ВОР В САДКЕ!» — жми 🛡️ ЩИТ!» and the «ЗАЩИТА» button bobs. This is where a kid
  learns the shield, before he needs it.
- **After a loss** (at the credit, `GiveAfterTheft(victim)`): the time goes into `losses[victimUserId]`
  (a time-bounded list, `VictimWindow` 600 s, keyed by UserId so a rejoin does not reset it).
  `AfterUntil = now + VictimImmunity` 90. If the list now holds at least `VictimMax` (2) entries,
  `RestUntil = (the VictimMax-th newest) + VictimWindow` (kind `rest`, «Садок отдыхает 6:12 — никто не украдёт»; DC-06).
  The first mount of a later session re-applies, from the same list, an `after` (latest loss + 90) or a
  `rest` that is still running, so leaving and rejoining never shortens them.
- **`EndProtection(player, "stealing")`** at the start of his hold clears every kind **and his `losses`
  list**, with the toast «Твоя защита снята: ты пошёл на дело!». `ShieldReadyAt` is unchanged: no refund.
  (Otherwise being robbed twice by a friend would buy 10 minutes of safe stealing.)
- **Studio knob** (DC-20): when `RunService:IsStudio()` and `DefenceConfig.Debug.StudioProtect` is a
  number (10), the join, newbie, after and rest durations are clamped to it; the shield is untouched.
  DefenceService `print`s one line at Init (not `warn`: the suites assert no warnings). RbxSim answers
  `IsStudio() == true`, so `tests/stage4_kit` boots with `Debug.StudioProtect = false` and only the
  knob's own test turns it on. Live servers are never Studio.

### 2.5 Where they are bought: the «ЗАЩИТА» sheet (why)

- The shop is Stage 5, but the spec's Stage 4 lists «улучшения защиты» and a «кнопка … щит». The README
  plan puts «замок» in Stage 4 too.
- A minimal sheet on the existing `gui/Sheet` + `Controllers/Sheet` shell costs one builder file and one
  controller. Stage 5 keeps it as the shop's first tab, so nothing is thrown away.
- The hub market was rejected: kids are 300+ studs away on their pier, and the shield must be one tap
  away.
- Purchases go through `EconomyService:SpendMoney` (the ledger, `Stats.Spent`), then `SaveSoon`.

### 2.6 Config modules (every number on its own line, so tests can patch it; Russian headers)

`src/ReplicatedStorage/Shared/Config/StealConfig.luau` (pure):

```lua
Prompt = {
  Action = "Украсть",
  MaxDistance = 6,        -- displays are 11 apart: one step back from the cabinet cancels
  Slack = 2,              -- server reach 8 (< 10: never through the arcade back wall)
},
Hold = {
  Tolerance = 0.5,        -- a Triggered this early still counts; the server finishes at t0 + need
  Deadline = 1.5,         -- no Triggered by need + this → cancelled ("deadline")
  Grace = 0.3,            -- a HoldEnded at ≥ need − Tolerance waits this long for its Triggered
  NoReply = 1.0,          -- client: no Hold/Denied this long after HoldBegan → InputHoldEnd (BE-16)
},
Carry = {
  Enabled = true,         -- false: the spec-literal mode, the fish moves at the end of the hold
  SpeedFactor = 0.85,
  Timeout = 25,
  ExitMargin = 2,         -- studs outside the plot rect
  Speed = {               -- the leaky distance budget of §4.4 (BE-9)
    Rate = 1.15,          -- refill per second = allowed speed × Rate
    CapSeconds = 1.5,     -- cap = allowed × CapSeconds + CapSlack: a 1.5 s stall, then the catch-up
    CapSlack = 6,
    Debt = 4,             -- budget below −Debt → returned "speed"
    Teleport = 24,        -- one tick moving more than this (studs) → returned "speed"; a tick longer
                          -- than Tick allows an allowed walker's extra path on top (A2-05)
    Start = 6,            -- the budget at the carry start (not full: a 2× hack never reaches a fence; A2-01)
    FactorGrace = 0.5,    -- allowed = the highest speed factor of the last 0.5 s (WalkSpeed latency)
  },
},
Tag = { Range = 6 },
Tick = 0.1,               -- watcher period while any theft or dog is awake (no loop otherwise)
Limits = {
  ThiefCooldown = 30,
  FailCooldown = { 3, 10, 30 }, -- the 1st / 2nd / 3rd+ failure he caused within FailWindow; "early" → the last
  FailWindow = 60,
  TagCooldown = 20,       -- a tagged thief cannot start on that base for this long
  VictimImmunity = 90,    -- "after"
  VictimMax = 2,          -- losses per victim per VictimWindow; the 2nd starts "rest" (DC-06)
  VictimWindow = 600,
  MinFishToRob = 3,
  FreshCatch = 30,        -- a fish caught this recently cannot be stolen (DC-08)
  RichRatio = 3,          -- refused when thief income > RichRatio × victim income… (0 = off; DC-09)
  RichMin = 20,           -- …and the thief earns at least this ($/s)
  StartBurst = 3,         -- token bucket for HoldBegan
  StartRate = 0.5,
  DeniedEvery = 2,        -- the same Denied reason again within 2 s is sent Quiet (no banner text)
  AlertCoalesce = 30,     -- one LOUD victim alert per (thief, victim) per 30 s; later ones are Quiet
  QuietSavedUnder = 1,    -- a hold shorter than this ends without the victim's toast and pings
                          -- (not a tag or the shield: the owner's save is always loud; A2-04)
},
Alarm = { Linger = 3 },
Speed = { MinFactor = 0.4 },
Texts = { … §6.10 … },
```

`src/ReplicatedStorage/Shared/Config/DefenceConfig.luau` (pure):

```lua
Shield = {
  Price = 0,
  Duration = 60,
  Cooldown = 180,         -- counted from the end: ready again 240 s after activation
  StackBelow = 60,        -- activation is accepted while the remaining protection is below this (DC-03)
  JoinProtect = 90,
  JoinProtectFirst = 300, -- the first session of a new save (SaveCount 0 at load): «защита новичка»
  QuickRejoin = 300,      -- LastOnline (or this server's leftAt) newer than this → the short protection
  QuickRejoinProtect = 20,
  WarnLast = 10,          -- the chip pulses in the last 10 s
  EndingWarn = 15,        -- «Скоро воры смогут красть…» this long before join/newbie protection ends
},
Dog = {
  Price = 6000,
  Rest = { X = 6, Z = 58 }, -- base-local guard spot in the court, facing the gate (DC-05)
  AlertDelay = 0.4,
  RunSpeed = 24,
  HomeSpeed = 10,
  BiteRange = 5,
  Slow = 0.5,
  SlowLinger = 1,
  Leash = 4,
  Replicate = 0.2,        -- attribute writes at most 5 Hz…
  MoveEpsilon = 0.25,     -- …and DogPos only after moving this far (studs)
},
Alarm = {
  Price = 2500,
  IntruderEvery = 1,      -- the visitor check, only for bases with the alarm
  IntruderCoalesce = 45,  -- one early warning per (visitor, base) per 45 s; none while protected
},
Lock = {
  SaleMax = 1,            -- the highest level sold now (0 = the card is hidden); Stage 5 raises it
  BaseHold = 3,
  Levels = {              -- every level works at runtime; Stage 5 sells 2..5
    { Hold = 4, Price = 1500 },
    { Hold = 5, Price = 5000 },
    { Hold = 6, Price = 15000 },
    { Hold = 7.5, Price = 40000 },
    { Hold = 9, Price = 100000 },
  },
},
Requests = { Burst = 4, Rate = 1 },    -- ShieldActivate + DefenceBuy
World = {
  LampPeriod = 0.5,                    -- 2 Hz (≤ 3 Hz, photosensitivity)
  IntruderPeriod = 1,
  LampOn = Color3.fromRGB(255, 64, 52),
  LampLight = { Range = 32, Brightness = 3 },
  SirenSpin = 1.2,                     -- s per turn
  BeepRange = 120,
  Dome = {
    Kinds = { shield = true },         -- only the shield gets a dome (DC-15)
    PhoneMax = 2,                      -- at most this many domes on touch devices (the nearest)
    Center = Vector3.new(0, 0, 88), Radius = 58, Transparency = 0.15, Inside = 0.8, Range = 260, Fade = 0.4,
  },
  StealWordRange = 90,                 -- «КРАДУТ!» over a display: the owner arriving from the spawn sees it
},
Panel = { Margin = 16, MaxWidth = 900, MaxHeight = 420, Header = 0.2, TallFrom = 600, CardAspect = 0.78, CardMin = 96 },
Debug = { StudioProtect = 10 },        -- Studio only: join/newbie/after/rest clamped to this; false = off (DC-20)
Texts = { … §6.10 … },
```

`UIConfig` gains:

- the token `Guard = swatch("#8FB4FF", "#3D6BFF", "#0A1A57")`. Royal blue is distinct from Sky (cyan),
  Water (teal) and Grape (purple); check it in the `defence_button` render;
- `ToastKinds.theft = { Token = "Berry", Icon = "🚨", Big = true, Life = 4.5, Priority = 4 }` (above
  danger);
- `ToastKinds.saved = { Token = "Leaf", Icon = "💪", Priority = 2 }`;
- `ToastKinds.shield = { Token = "Guard", Icon = "🛡️", Priority = 2 }`;
- a `Theft` block with the widget numbers of §6 (edge pulse size per device, banner and plate heights,
  the plate's shield button minimum 56 px and 35 % width, timings).

`DataConfig.Limits.OriginMax` 24 → **32**: `"<UserId>:<uid>"` is up to 11 + 1 + 12 characters, and
`AddFish` silently drops a longer Origin, which would disable the dedupe for big UserIds (BE-7).

`MapConfig.PartBudget.RuntimeReserve.Theft = 60`. The display fish is destroyed during the carry, so the
`StolenFish` (≤ 20) is already covered by `TankFish`. The 60 covers ≤ 8 client shield domes (≤ 2 on
phones), ≤ 20 for the return-arc clone, and slack. Peak: 26 373 + 60 = 26 433 ≤ 26 500.

### 2.7 Prices against the economy (Stage 3 §3.5 medians)

| item | price | median kid can afford at | why |
|---|---|---|---|
| Щит | free | always | the spec calls it a button with a cooldown; the main kid-safe defence |
| Замок (level 1) | $1 500 | ≈ 2.5 min | the first purchase ever, right after the tank fills (1:41), inside the newbie protection (5:00) |
| Сигнализация | $2 500 | ≈ 3 min | early warning: shield before the hold |
| Собака | $6 000 | ≈ 4.5 min | the strongest passive defence |
| Замок levels 2 / 3 / 4 / 5 (**Stage 5**, config only now) | $5 000 / $15 000 / $40 000 / $100 000 | ≈ 4 / 7.5 / 13 / 22 min | ≈ +1 s each (≈ 16 studs of owner running) |

A stolen fish is worth ≈ 10–12 s of its income as a sale; its real prize is the income stream, and a
kid's best fish is ≈ 40 % of his income (`critique_design.md` §2). With the limits of §1.5 one victim
loses **at most 2 fish per 10 min** whatever the number of thieves (unless he steals himself, which
ends his protection), and one thief takes at most one fish per ≈ 37 s (the 30 s cooldown plus the hold
and the carry). In the critic's simulation from minute 10 that keeps a robbed kid at $114/s instead of
rev. 1's $40/s (untouched: $180/s). Stage 5 may rescale every price; the table lives in config.

---

## 3. Data and persistence

### 3.1 PlayerData additions (`src/ServerScriptService/Lib/PlayerData.luau`, no `V` bump)

| field | type / rule | owner (DataService header field list) |
|---|---|---|
| `LockLevel` | exists: an integer ≥ 0, unknown high levels kept verbatim | **DefenceService** |
| `Upgrades.Dog` | boolean, or a finite number ≥ 0 (a newer server's level), kept verbatim; anything else → removed, issue. **Owned = `PlayerData.Owned(v)`** = `v == true or (number and v > 0)`, the only predicate DefenceService uses (HasDog, the attribute, the `owned` check), so a newer server's level is never sold again or overwritten with `true` (Stage 3 B-6; W0-02) | DefenceService |
| `Upgrades.Alarm` | the same as `Upgrades.Dog` | DefenceService |
| `Upgrades.ShieldReadyAt` | integer `os.time()` ≥ 0 (non-finite → removed); DefenceService clamps it at load | DefenceService |
| other `Upgrades.*` keys | kept verbatim (Stage 5 / newer servers) | — |
| `Stats.Stolen` / `Stats.Lost` | integers ≥ 0, in `STAT_NUMBERS` / `KNOWN_STATS` / Template; a return or a void takes them back (floor 0; BE-4) | TankService (`StealFish`) |
| `Tank[i].Origin` | exists, ≤ `DataConfig.Limits.OriginMax` **32** (BE-7); **Sanitize now dedupes**: two fish with the same `Origin` → keep the first, drop the rest with an issue (G-09) | TankService |

`Reconcile` fills the new stats on old saves. `Serialize` already keeps `Upgrades` JSON values.
Nothing new is saved for the fairness rules: the loss list, the cooldowns and the tag waits are
server-memory maps keyed by UserId (§4.11), and the newbie rule reads the existing `SaveCount`.

### 3.2 The transfer protocol (TankService owns all of it; StealService only calls `StealFish`)

```
at the plot exit (StealService watcher tick, inside xpcall, no yields anywhere below):
  res = TankService:StealFish(victim, thief, victimUid, token)
    CHECK → a complete PLAN (nothing mutated yet; BE-3):
      CanWrite(victim) and CanWrite(thief); both runtimes mounted;
      the victim's fish is active and fish.Steal.Token == token and fish.Steal.Phase == "carry";
      place = PreviewAdd(thief, fish.Income10)   -- "stored" | "replaced" | nil (escrow/steal/dormant fish excluded)
      place == nil → return nil, "full"
      plan = { victimSlot, thiefSlot,
               newUid = TankRules.UidOf(thiefData.NextUid)   -- peeked, not yet taken
               replaced = { Uid, Price (HomeRatePct) }?,       -- the thief's weakest, for "replaced"
               row = { Id, Kg, Mutation, Age = clamp(serverNow − fish.GrowFrom, 0, Growth.Time), Slot,
                       Origin = "<victimUserId>:<victimUid>" } }
      every price finite; no row in the thief's tank already has that Origin
    COMMIT, fixed order — table and attribute writes only; no signal, no remote before step 5:
      0 entry = { Victim = victim, VictimUserId, VictimUid, Seq = math.huge }
        escrows[thief][plan.newUid] = entry
        -- from here every serialize of the thief skips the uid, and no Committed can match the entry
      1 victim: detach the fish (data.Tank dense remove, runtime, BySlot); slot fields nil → State "empty"
        → Event "<n>|stolen|<thiefUserId>"; refresh income; Stats.Lost += 1
      2 thief: NextUid += 1; "replaced" → the planned weakest row removed (no money yet);
        insert the planned row (Uid = plan.newUid, CaughtAt = os.time()); its runtime is created with
        FishRt.Escrow = entry; slot attrs (Escrow = true) → Event "in" / "swap";
        refresh income (the escrowed fish is EXCLUDED from Income10Sum); Stats.Stolen += 1
      3 entry.Seq = DataService:SaveSoon(victim)
        -- with latency 0 the victim's save may run inline here; its Committed cannot match Seq = huge
      4 if DataService:Mode() ~= "DataStore" or DataService:CommittedSeq(victim) >= entry.Seq → clearEscrow now
      5 side effects, the escrow already in force: "replaced" → AddMoney(thief, plan.replaced.Price,
        "autosell"), Stats.Sold += 1; signals SlotChanged ×2, FishRemoved(victim, copy, "stolen"),
        FishAdded(thief, copy, "stolen"); TankEvent("Stored", TankResult + { Fish = clean FishData (Id, Kg,
        Mutation, Rarity, Value, Income) }) to the thief
    return { Result = TankResult, Fish = clean, ThiefUid, VictimUid }

clearEscrow(thief, uid):     -- from DataService.Committed / Released (committed ≥ entry.Seq) or step 4
  remove the map entry FIRST (a second caller finds nothing); FishRt.Escrow = nil; slot Escrow = nil;
  refresh income (it starts earning); DataService:SaveSoon(thief)
```

**The escrow map** `escrows: { [thief: Player]: { [thiefUid]: Entry } }` lives at **module level in
TankService** and is keyed by the thief's `Player` object (BE-2). That object stays a valid key after
TankService drops the thief's runtime, so the `OnSerialize` hook still works for his last save:
`skipUid = function(uid) local e = escrows[player] return e ~= nil and e[uid] ~= nil end`, for every save
of that player, whether a runtime exists or not. Entries are matched to the victim's **record**, never
to a UserId: a victim who leaves and rejoins this server has two records with one UserId, and their
`seq` counters both start at 0.

- `DataService.Committed(player, seq)` → clear every entry with `entry.Victim == player and seq >=
  entry.Seq`.
- `DataService.Released(player, committed)` (fired once per record) → **every** entry whose `Victim ==
  player`: `committed >= entry.Seq` → clear, else → **void**. No entry outlives its victim's record,
  even if a `Committed` handler threw.
- **No escrow is ever cleared on a timeout.** That would be the one path that can duplicate a fish
  (BE-6). The TankService header says so.

**While escrowed**, a fish:

- is not serialized;
- cannot be sold (`TankSell` → `Denied escrow` «Рыба ещё в пути — пара секунд!»);
- is not a replacement candidate (`Candidate.Locked = true`);
- cannot be stolen (`Denied fresh` «Эту рыбу только что украли»);
- earns nothing;
- has the slot attribute **`Escrow = true`** (BE-21), so the tank panel shows «В ПУТИ…» up front and the
  thief's own client prompt filter mirrors `PreviewAdd` exactly.

It is shown normally on the thief's display. Typical escrow: 0 s (no save in flight) to the 6.05 s gap
plus latency.

**Return, void and the uid guard** (BE-4): every path (F7 void, F8 return, F9 close, `Committed`) first
removes its entry from the map, then acts, so the four can run in any order. `returnToVictim` and the
`AmendLeaving` reinsert refuse when the victim's data already holds a row with that `Uid` (`Sanitize`
would renumber a duplicate uid into a second real fish, not drop it). A return takes back
`Stats.Lost` (victim) and `Stats.Stolen` (thief); a void takes back `Stats.Stolen`.

### 3.3 Every failure path (none duplicates; the right column says what is lost)

| # | situation | what the code does | result |
|---|---|---|---|
| F1 | crash or shutdown during the **hold or carry** | the fish never left the victim's data, and its saves include it | victim keeps it ✔ |
| F2 | the **victim leaves** during hold/carry | StealService cancels (reason `victim`); his final save includes the fish | victim keeps it ✔ |
| F3 | the **thief leaves or dies** during hold/carry | cancelled/returned; nothing was transferred | victim keeps it ✔ |
| F4 | either side not writable at the exit | `StealFish` returns nil → `Returned` | victim keeps it ✔ |
| F5 | normal escrow | the victim's commit → `Committed` → clear → `SaveSoon(thief)` | thief has it ✔ |
| F6 | the **victim leaves during the escrow** | his release save carries the removal; `Committed` fires before `release` (DataService `:514-519`) → clear | thief has it ✔ |
| F7 | the victim's save **never lands** (lost lock → kick; the final save fails for 15 s) | `Released(victim, committed < Seq)` → **void**: remove the escrowed fish from the thief (data, runtime, slot Event `"<n>\|void\|"`, quiet), toast «Рыба вернулась к хозяину» | the victim's store still has it ✔ if it was ever committed there (the thief keeps the coins of his own weakest fish, if one was replaced); a fish the victim himself received through an uncommitted clear or return (a chained theft) is lost with his other unsaved progress — voiding is the only safe choice, clearing could duplicate (A1-03). **If the last write landed but its reply was lost** (`quiet`, or an error after the write) → one fish lost (BE-6), never two |
| F8a | the **thief leaves during the escrow**, the victim can still write | TankService `PlayerRemoving(thief)`, synchronously: the entry is gone first, then **strip** it from the thief's live `data.Tank` (a throw after this loses one fish, never leaves two), then **return** each escrowed fish to the victim (the original uid; the original slot if free, else the lowest free; **none free** — the victim caught into the display the theft freed — the AddFish full-tank rule: a weaker unlocked fish is sold for coins and the returned one takes its display, otherwise the returned fish itself is sold for the victim, «Вор ушёл — садок полон, рыба продана: $N»; never dormant, A1-01), `SaveSoon(victim)`, the toast «Вор ушёл — рыба вернулась!» (`Returned { …, Result, Price }`). The final save's transform always runs after a yield, so it cannot see the fish | the victim has it (or its coins) ✔ |
| F8b | the same, but the victim is already `Leaving` and his final snapshot is not taken | strip from the thief; `DataService:AmendLeaving(victim, reinsert)` puts the row back into the victim's live `data.Tank` (BE-1). It writes only `Tank` (no coins for a leaving player): with a full tank the row keeps its `Slot` and sleeps until a load finds that display free (Stage 3 `PlayerData.Layout`) or Stage 5 `SetSlots` wakes it | the victim has it ✔ (dormant if his tank was full) |
| F8c | the same, but the victim's final snapshot is already taken | strip; the amendment waits in `rec.PendingAmends` (A1-02): if that attempt **fails**, it is applied before the retry, which carries the fish | **one fish lost only if that final write lands**. The window runs from the victim's final transform to its reply: about one request (a failed attempt clears `FinalTaken` and applies the waiting amendments, so the retries neither widen nor drop it; §4.6) |
| F9 | **shutdown**, BindToClose first | `DataService:OnClose(fn)` hooks run **synchronously at the very start** of the close callback, before any record goes `Leaving`; TankService returns every escrow as in F8a, then the close saves run | the victim has it ✔ |
| F9' | shutdown with the **players removed first** (Roblox guarantees no order) | per pair: F8a, F8b or F8c, in the order Roblox removes them | as F8a/b/c |
| F10 | a **hard server crash** (no BindToClose) between the victim's commit and the thief's commit, **or** the thief's saves never land before he leaves (a failing DataStore) | nothing can run / the final save gives up after `LeaveSaveWindow` | **one fish lost**, never two. The crash window is the thief's key gap: ≈ 6–7 s per theft; the failing-store case is unsaved progress, like a fresh catch (A1-03) |
| F11 | a third player steals the escrowed fish | refused (`fresh`) | — |
| F12 | two thieves on one fish/base | one theft per base; `SetSteal` holder tokens | — |
| F13 | an old dupe already in a save (impossible by design) | Sanitize keeps one per `Origin` | defence in depth |
| F14 | two paths try to finish the same entry (F8 + F9, F7 + F8, `Committed` + `Released`) | map-first removal and the uid guard | one row; no Sanitize issue on reload |

Closing F10 would need a cross-key transaction. The alternative was considered and rejected: saving the
fish into the thief's key as "pending" and resolving it on load by reading the victim's key. It races
with a lock steal (the old server returns the fish to the victim while the new server keeps the pending
copy) and so can **duplicate**. That is worse than the rare loss. The lost-reply case of F7 can be
closed later with a write token in every save (BE-6 step 3: P2, §9).

### 3.4 Invariants (the tests assert these, §7)

1. At any moment a fish exists live in **exactly one** runtime: hold/carry = the victim's, after the
   commit = the thief's.
2. Across all saved keys, an `Origin` appears **at most once**, and a victim's uid is never both in the
   victim's key and as an `Origin` in a thief's key **after both commits**.
3. `StealFish` never yields, never half-commits and fires nothing before its escrow entry exists (an
   error after the CHECK block is a bug: it is wrapped so that the watcher logs and the theft is
   returned).
4. The ledger holds for both sides (`Money == Start + Earned − Spent`). Autosell coins only come from the
   thief's own fish.
5. `_debugSizes()` of TankService, StealService and DefenceService: the per-player tables are zero 10 s
   after the last player leaves; the time-bounded maps (cooldowns, fail and tag waits, alert coalescing,
   `LeftAt` for `QuickRejoin` 300 s, victim losses for `VictimWindow` 600 s) are zero once their windows
   pass. They are pruned on every write, on every `PlayerRemoving` and inside `_debugSizes()` itself, so
   an idle server reports zeros after `Advance(VictimWindow)` with no writes (BE-26).
6. Clear, void and return are idempotent, and no uid is inserted twice into one tank.
7. No escrow is cleared by a timer.

---

## 4. Server

### 4.1 Modules and boot order

`Main.server.luau` `ORDER = { "MapService", "BaseService", "DataService", "EconomyService",
"MarketService", "FishingService", "TankService", "DefenceService", "StealService" }`.

| module | owns | requires |
|---|---|---|
| `Shared/StealRules` (new, pure, client + server) | `HoldTime(level)`, `LocalOf(base pivot, pos)`, `InPlot(local, margin)`, `NearestExit(local) -> local point`, `DogWaypoint(dog, thief)`, `DogStep(pos, target, dt, speed, leash)`, `ProtectState(now, attrs)`, `CanStealView(view) -> reason?` (the client's prompt filter: it runs the rows of `TheftChecks` marked `Client`), `FormatClock(s)` «0:42», `NextLock(level, saleMax) -> (hold, price)?` | configs, TankRules, TheftChecks |
| `Shared/TheftChecks` (new, pure; BE-28) | the ordered check table of §4.3 over a plain `view` struct: `Check(view) -> (reason?, quiet?)`; each row is tagged `Client = true` when a client can evaluate it from replicated state, so the server and the client filter never drift. Every Denied row is testable headless | StealConfig |
| `Lib/CarryGuard` (new, pure; BE-28) | the carry's leaky distance budget and exit gate (§4.4), with `dt` as an input: `CarryGuard.new(cfg, allowed)`, `:Step(dt, displacement, allowed) -> "ok" \| "speed"`, `:CanCredit() -> boolean` | StealConfig |
| `Lib/Speed` (new) | the WalkSpeed modifier stack and its expiry timer (§4.7) | — |
| `Lib/DogBrain` (new) | per-base logical dog (§2.1); pure steps + attribute writes | StealRules, DefenceConfig |
| `Lib/HeldRig` (new, extracted from `FishingService.holdFish`) | `HeldRig.Build(character, fish, name) -> (model, scale)?`: the clone, scale, weld to the head, massless, attributes | FishingConfig |
| `Lib/Bucket` (new) | a generic token bucket `Bucket.new(burst, rate)` → `:Take(player)`, `:Forget(player)`, `:Size()`; it creates no entry for a player whose `Parent ~= Players` (the `TankRequests.luau:31-34` pattern; BE-20). TankRequests stays as is | — |
| `DefenceService` (new) | `LockLevel`, `Upgrades.Dog/Alarm/ShieldReadyAt`; purchases; shield; protections (join/newbie/after/rest); `loadInfo`, `losses`, `leftAt`; base attributes `ProtectUntil/ProtectKind/HasDog/HasAlarm/LockLevel/HoldTime`; dog show/hide (and the pup's rest pivot); the intruder loop; the Studio knob; remotes `ShieldActivate`, `DefenceBuy`, `DefenceEvent` | Base, Data, Economy, Tank (**not** Steal: it asks through `SetStealProbe`, BE-8) |
| `StealService` (new) | 96 `StealPrompt`s; the theft state machine; server hold timing; the watcher; carry (`CarryGuard`), exit, tag; `StolenFish`; speed modifiers; the dog brains; alerts; cooldowns, fail and tag waits; `AlarmState` / `Thief`; remote `StealEvent`; the home guard | Base, Data, Tank, Defence, Fishing (HeldRig, `DropHeldFish`), TheftChecks, CarryGuard |
| `TankService` (changed) | `SetSteal`, `StealFish`, the escrow (map, hook, clear, void, return), read API, sell denials, `Stats.Stolen/Lost`, `SlotChanged`, the slot `Escrow` / `FreshUntil` attributes, the unmount cleanup of the steal channel | + DataService.Released / OnClose / AmendLeaving |
| `DataService` (changed, small) | `Released` signal (once per record), `OnClose(fn)` hooks, `AmendLeaving(player, fn)` + `rec.FinalTaken`, field-ownership lines | — |
| `BaseService` (changed, small) | `SetHomeGuard(fn)` | — |
| `FishingService` (changed, mechanical) | uses `HeldRig`; `FishingService:DropHeldFish(player)` | — |
| `Lib/Notify` | unchanged API (the client turns `StealEvent` into widgets and toasts) | — |

Every new script has a Russian header (what it does, its API, attributes, remotes). Per-player state
lives in maps keyed by `Player` with an identity check (Stage 3 B-3) and is cleaned in PlayerRemoving.
Each new service guards every cross-service call with `type(X.fn) == "function"` (stub tolerance, Stage 3
§4.1). Each exposes `_debugSizes()`. **No service requires a service that requires it back** (a Roblox
`require` cycle errors); a static test in `stage4_rules` checks the require graph (BE-8).

**APIs of the two new services** (Wave 0 writes the signatures; Wave 1 A the bodies):

| DefenceService | what |
|---|---|
| `IsProtected(player) -> (kind?, until?)` | the base protection (§2.4) |
| `EndProtection(player, reason)` | clears every kind and the player's `losses` list (no cooldown refund) |
| `GiveAfterTheft(victim)` | the 90 s `after`, plus `rest` on the 2nd loss in 600 s (§2.4) |
| `HasDog(player)`, `HasAlarm(player) -> boolean` | from `Upgrades` |
| `LockLevel(player) -> number`, `HoldTime(player) -> number` | runtime level is `min(LockLevel, #Levels)` |
| `SetLockLevel(player, n) -> boolean` | behind `CanWrite`; writes `LockLevel` and the Player/base attributes, then fires `LockChanged` (StealService, the only prompt writer, rewrites `HoldDuration` on the prompts that are not held); Stage 5's shop calls it too |
| `SetStealProbe(fn: (Player) -> boolean)` | StealService registers `IsStealing` in its `Init`; the default probe returns false (the `FishingService.SetCatchSink` pattern, `TankService.luau:1073`). The replicated `Stealing` attribute is never the server's truth |
| `ProtectionChanged`, `LockChanged` | Signals `(player, base)` |
| `_debugSizes()` | `Protections`, `Buckets`, `LoadInfo`, plus the time-bounded `Losses`, `LeftAt`, `IntruderSeen` |

| StealService | what |
|---|---|
| `IsStealing(player) -> "hold" \| "carry" \| nil` | |
| `TheftOn(base) -> { Thief, Victim, Slot, Phase }?` | |
| `Cancel(player, reason)` | used by BindToClose and tests |
| `TheftStarted`, `TheftEnded` | Signals `(thief, victim, result)`; `result` = "credited" \| a cancel reason |
| `_debugSizes()` | `Thefts`, `Buckets`, plus the time-bounded `Cooldowns`, `Fails`, `Tags`, `Alerts` |

### 4.2 The theft state machine (StealService)

```
            HoldBegan + checks §4.3                     Triggered ok (≥ need − 0.5)
  Idle ───────────────────────────────► Hold ─────────────────────────────────► Carry ──exit plot──► Credited
                                          │  released / far / died / left /         │  died / left / tag / shield /
                                          │  shield / tag / victim left /           │  timeout 25 s / speed budget /
                                          │  deadline need+1.5 / fish changed       │  victim left / StealFish nil
                                          ▼                                         ▼
                                       Cancelled (fish stays)                    Returned (fish flies home)
  Carry.Enabled = false: Hold ──Triggered ok──► StealFish at once ──► Credited (no carry, no StolenFish)
```

`Theft` record (one per active theft):
`{ Id, Token, Thief, Victim, Base, Slot, Uid, Prompt, Character, Phase = "hold" | "carry", T0 (os.clock),
Need, HoldEnd (server time), CarryEnd, Finishing (bool), Ended (bool), Guard (CarryGuard), LastPos,
Trove }`. Maps: `byThief[Player]`, `byBase[Base]`.

**Begin** (after §4.3):

1. `TankService:SetSteal(victim, uid, token, "hold", { By = thief.UserId, End = HoldEnd })`.
2. `DefenceService:EndProtection(thief, "stealing")`.
3. The theft's Trove gets its **first** cleanup: `Speed.ClearAll(thief)` (which also clears `Slowed`),
   so it runs even if a later cleanup throws (BE-10).
4. Base `Thief = thief.UserId` and `AlarmState = "theft"`; Player `Stealing = "hold"`. No prompt
   `Enabled` writes: clients hide the base's other prompts from `Thief` (BE-15).
5. The dog wakes, if `DefenceService:HasDog(victim)`.
6. `StealEvent("Hold", …)` to the thief, `StealEvent("Alert", …)` to the victim (coalesced, §4.9).
7. Start the watcher if it is idle.

**Hold → carry:**

1. `SetSteal(…, "carry", { End = CarryEnd })`. The fish leaves the victim's income.
2. `FishingService:DropHeldFish(thief)`, then `HeldRig.Build(character, fish, "StolenFish")` with
   attributes `FishId, Rarity, Mutation, Kg, Value, Scale, Owner = victim.UserId`.
3. `Speed.Set(thief, "Carry", 0.85)`; `Guard = CarryGuard.new(cfg, Speed.Allowed(thief))` at a full
   budget; `LastPos` = the HRP position; Player `Stealing = "carry"`.
4. `StealEvent("Carry")` to the thief and `StealEvent("Alert", { Phase = "carry" })` to the victim (his
   plate keeps the ЩИТ button: DC-01).

**Credit:**

1. `StealFish`. `nil` → Returned (reason `full` or `busy`).
2. Destroy `StolenFish`.
3. `DefenceService:GiveAfterTheft(victim)`.
4. Cooldown = now + 30.
5. `StealEvent("Done", { Fish, Result, Name = victim.DisplayName })` to the thief and `StealEvent("Lost",
   { Fish, Name = thief.DisplayName, Until, Kind })` to the victim (`Until`/`Kind` = his protection now:
   `after` or `rest`).
6. End (below).

**Cancel / return:**

1. `SetSteal(victim, uid, token, nil)`: the slot steal attrs are cleared, income resumes. A no-op when
   the victim's runtime is gone.
2. Destroy `StolenFish`.
3. A wait for the thief when the reason is his own (BE-19, DC-10):
   - `released`, `far`, `died`, `timeout`, `speed`, `deadline`, `tag` → the next step of `FailCooldown`
     (3 / 10 / 30 s by the count in `fails[userId]` within `FailWindow` 60 s);
   - `early` (the exploit signal) → the last step (30 s) at once;
   - `tag` also sets `tagged["thief:victim"] = now + TagCooldown` 20;
   - `shield`, `victim`, `full`, `busy`, `left` → no wait (not his fault).
4. `StealEvent("Cancel", { Reason, Text, Phase })` to the thief, if he is still here.
5. `StealEvent("Saved", { Reason, Slot, Quiet })` to the victim, if he is still here and it was not his
   leave. `Quiet = true` when the hold lasted less than `QuietSavedUnder` 1 s (no toast, no pings) and
   the reason is not the owner's own `tag` or `shield` (those are always loud; A2-04).
6. End.

**End:** `Ended = true` first, so a second `Cancel`/`End` does nothing, and every deferred callback (the
`Finishing` `task.delay`, the `AlarmState` linger) checks the theft token and `Ended` before it acts
(BE-10). Then `Trove:Destroy()` (the speed reset runs first); clear `byThief` / `byBase`; Player
`Stealing = nil` (last); base `Thief = nil`, `AlarmState` nil after `Linger` (token-checked
`task.delay`); the held prompt gets the base's current `HoldDuration` (BE-18); the dog → Return.

### 4.3 Prompts and the server checks

**Creation** (StealService:Init, after BaseService created the bases). Under each
`Tank.Slots.Slot_K.Pedestal.PromptAttachment`: `ProximityPrompt` named `StealPrompt` with `ActionText`
«Украсть», `ObjectText` "", `HoldDuration` 3, `MaxActivationDistance` 6, `RequiresLineOfSight = false`,
`Exclusivity = OnePerButton`, `KeyboardKeyCode E`, `GamepadKeyCode ButtonX`, `ClickablePrompt = true`,
`Style = Default`, `Enabled = false`. `promptInfo[prompt] = { Base, Slot, Attachment }`. **The server
never writes `MaxActivationDistance` again**: that property belongs to the client filter (§5.1, BE-14).

**Refresh** (`refreshPrompt(base, index)`), driven by `TankService.SlotChanged(base, index)` (BE-22),
plus mount/unmount and `LockChanged`. No per-slot attribute connections on the server.

- `Enabled = mounted and State == "fish"`. Nothing else (BE-15): protection, a theft on the base, an
  escrowed or fresh fish are hidden by the client filter and denied by the checks below. `Enabled` then
  changes only on a catch, a sale, a theft credit and a mount, about 22 fewer property replications per
  theft for every client.
- `ObjectText = ShortName .. " · " .. FormatRate(Income10)` («Окунь · +$4/с»). It is written only on
  change. Income never grows, so it needs no 1 s ticking.
- `HoldDuration = HoldTime(owner LockLevel)`, skipping a prompt that is being held (BE-18).

**Connections:** one set on `ProximityPromptService` (`PromptButtonHoldBegan`,
`PromptButtonHoldEnded`, `PromptTriggered`), filtered by `promptInfo`. No per-prompt connections.

**HoldBegan checks, in this order** (the rows of `Shared/TheftChecks`; the first failure is the reason;
synchronous). A failure is answered with `StealEvent("Denied", { Reason, Text, Quiet?, BaseIndex,
Slot })` whenever the reply bucket allows; the same reason again within `DeniedEvery` 2 s goes out with
`Quiet = true` (no banner text) instead of being dropped, so the client always learns which prompt to
end (BE-16). «client» marks the rows the client filter also evaluates (§5.1).

| # | check | reason | client text (StealConfig.Texts.Denied) | client |
|---|---|---|---|---|
| 1 | a known `StealPrompt` | — (silent) | | |
| 2 | not a repeat: `byThief[thief].Prompt ~= prompt` (a double tap or an Exclusivity switch on the prompt he already holds) | — (ignored: no token, no reply; BE-17) | | |
| 3 | `startBucket:Take(thief)` (Burst 3, 0.5/s) | — (silent; the client's `NoReply` ends the ring) | | |
| 4 | thief ≠ owner | — (silent) | | ✔ |
| 5 | `CanWrite(thief)` | `loading` | «Загружаем твой садок…» | |
| 6 | thief has a mounted base | `nobase` | «Сначала дождись своей базы» | ✔ |
| 7 | `CanWrite(victim)`, the victim mounted on this base | `busy` | «Сейчас нельзя» | |
| 8 | thief alive, the same `Character`, HRP ≤ 6 + 2 studs (3D) from the attachment | `far` | «Подойди ближе к витрине» | |
| 9 | thief not in a theft | `stealing` | «Ты уже крадёшь» | ✔ |
| 10 | thief not waiting: no success/fail cooldown, not tagged on this base | `cooldown` / `tagged` | «Красть снова можно через {t}» / «Хозяин тебя поймал! Здесь красть снова через {t}» | ✔ (`StealCooldownUntil`) |
| 11 | the victim's base not protected | `shield` / `join` / `newbie` / `after` / `rest` | «Здесь щит — ещё {t}» / «Игрок только пришёл — подожди {t}» / «Новичок под защитой — ещё {t}» / «Этого игрока недавно обокрали — подожди {t}» / «Садок отдыхает — ещё {t}» | ✔ |
| 12 | no theft on this base | `taken` | «Здесь уже кто-то крадёт» | ✔ (base `Thief`) |
| 13 | owner's HRP > 6 studs from the thief's | `owner` | «Хозяин рядом!» | |
| 14 | victim active fish ≥ 3 | `few` | «У игрока мало рыбы — пусть подрастёт» | ✔ |
| 15 | not a much weaker victim: thief `Income10Sum` < `RichMin` × 10, or ≤ `RichRatio` × the victim's (DC-09) | `weak` | «Этот игрок пока намного слабее — найди соперника по силе» | ✔ (Player `Income`) |
| 16 | the slot's fish active, `FishUid` matches, not Steal / Escrow / Dormant, not caught less than `FreshCatch` 30 s ago (DC-08) | `missing` / `fresh` / `new` | «Этой рыбы уже нет» / «Эту рыбу только что украли» / «Свежий улов — красть можно через {t}» | ✔ (`StealPhase`, `Escrow`, `FreshUntil`) |
| 17 | `TankService:PreviewAdd(thief, income10)` ≠ nil | `full` | «Садок полон — эта рыба слабее твоих» | ✔ (own slots' `Income`, `Escrow`) |

The rev. 1 pair row (`pair`, «Хватит красть у этого игрока…») is gone: the victim cap (`rest`, row 11)
bounds one bully as well as many (DC-06).

On a Denied (quiet or not), the thief's client calls `InputHoldEnd()` on the prompt the payload names,
and shows the text on the banner unless `Quiet`.

**Timing** (`read_hooks` #9, `research` §3.2):

- `T0 = os.clock()` at HoldBegan. `Need = HoldTime(level)` captured then; `HoldEnd = AttrTime(serverNow +
  Need)`.
- `Triggered` from the same thief on the same prompt:
  - `elapsed ≥ Need − 0.5` → `Finishing = true`; if `elapsed < Need`, finish at `T0 + Need`
    (`task.delay`, token-checked), re-running checks 7–8, 11 (shield only) and 13 at that moment;
  - earlier → cancel `early` (a suspicion log line, no kick; the 30 s wait).
- `Triggered` without a record → ignored, with one rate-limited log line (`fireproximityprompt` exploit).
- `HoldEnded` → **classified by the state at that moment** (BE-13), because a stock prompt ends the hold
  on the client (and in RbxSim) before the server watcher sees a death or the radius:
  - the character is not alive, or `player.Character ~= theft.Character` → `died`;
  - the 3D distance from the attachment is more than `Prompt.MaxDistance` → `far`;
  - otherwise `released`;
  - unless `Finishing` (Roblox fires HoldEnded after a completed hold too). A `released` that arrives with
    `elapsed ≥ Need − Tolerance` but before `Triggered` (the two client events may reach the server in
    either order) waits `Hold.Grace` 0.3 s for `Triggered` before it cancels.
- No `Triggered` by `Need + 1.5` → cancel `deadline`.

### 4.4 The watcher (one loop, only while needed)

`task.spawn` a loop when the first theft begins or a dog wakes:
`while next(thefts) or DogBrain.AnyAwake() do task.wait(Tick) … end`. It ends by itself, so an idle server
does no per-frame work (no Heartbeat). Each step runs per theft inside `xpcall` with a rate-limited
`warn`. Nothing yields.

**Hold:**

- `alive` (Humanoid health > 0, `player.Character == Character`);
- the radius (3D ≤ 8);
- the victim is still writable and mounted;
- the base is not protected (the shield also cancels at once through `ProtectionChanged`);
- tag (owner within 6 studs);
- the deadline.

**Carry** (every tick):

- `alive`, the victim writable;
- the base is not protected → Returned `shield` (DC-01; `ProtectionChanged` does it at once, the tick is
  the backstop);
- tag;
- `CarryEnd`;
- **the speed budget** (`CarryGuard`, BE-9) on the horizontal HRP displacement `d` since the last tick:

  ```
  allowed = Speed.Allowed(thief, FactorGrace)     -- 16 × the highest factor in the last 0.5 s
  cap     = CapSeconds × allowed + CapSlack        -- 1.5 s of walking + 6 studs
  budget  = Start (6) at the carry start           -- not full (A2-01): the stall reserve is earned walking
  budget  = min(cap, budget + allowed × dt × Rate) − d      -- Rate 1.15
  d > Teleport (24) + allowed × Rate × max(0, dt − Tick) in one tick  → Returned "speed" (A2-05)
  budget < −Debt (4)                               → Returned "speed"
  ```

  | case | effect |
  |---|---|
  | honest carry, 13.6 st/s (6.8 under the dog) | the budget never drains |
  | a client that keeps `WalkSpeed 16` under the dog | drains ≈ 8 studs/s → returned in ≈ 2.5 s (the dog chase lasts 6.5–7.4 s) |
  | a 2× speed hack in the carry (from the start) | returned in ≈ 0.9 s (≈ 24 studs), before the nearest fence (≈ 44 studs from a display); 2.5× in ≈ 0.6 s (A2-01) |
  | a 2× speed hack started mid-carry, on a full budget | returned in ≈ 2.7 s |
  | a 1.33× hack (≈ 18 st/s) | reaches the nearest fence about as the budget hits 0: accepted at the margin |
  | `WalkSpeed 16` kept in the carry without the dog (only the ×0.85 ignored) | 18 % faster, never caught: accepted (`Rate` 1.05 would catch it in ≈ 25 s, at the cost of honest lag) |
  | a phone with a 1.5 s network stall, then the catch-up (≈ 20 studs in one tick) | under `Teleport` and inside the cap: not returned (also at the carry start: the stall refills the budget) |
  | a server hitch: one 2 s watcher tick while an honest thief walks 27 studs | the jump limit grows with dt: not returned (A2-05) |

  Nothing counts strikes, so two lag bursts over a long carry cannot add up.
- **exit**: `StealRules.InPlot(LocalOf(base, HRP), ExitMargin)` false **on a tick that ends with the
  budget ≥ 0** (`Guard:CanCredit()`) → credit. A teleport out of the plot is returned or must wait for
  the budget, never credited early.

**Dogs:** `DogBrain.Step(base, dt, thiefPos?)` for each awake dog. A bite sets the Speed modifier (§2.1).
The attributes are written at most every `Replicate` 0.2 s and only after a real move.

### 4.5 TankService additions (API; the header and `docs` updated)

| function | what |
|---|---|
| `SetSteal(owner, uid, token: number, phase: "hold" \| "carry" \| nil, info?) -> boolean` | Holder semantics: false if another token holds the fish, or if the fish is unknown, dormant or escrowed. `nil` releases (only the same token). It sets `FishRt.Steal = { Token, Phase }`, which also makes `Locked` true. Slot attributes `StealBy` (UserId), `StealEnd` (AttrTime), then **`StealPhase` last**; release clears them with `StealPhase` last. `carry` excludes the fish from `Income10Sum`. The old `SetLocked(owner, uid, bool)` stays as a thin wrapper (token `-1`, no attributes), so Stage 3 tests keep passing. |
| `StealFish(victim, thief, uid, token) -> (StealResult?, reason?)` | §3.2 |
| `PreviewAdd(player, income10) -> "stored" \| "replaced" \| nil` | pure on the runtime: `ChooseReplacement` over active, non-Locked, non-Escrow fish |
| `SlotFish(base, index) -> (owner: Player?, view?)` | `view = { Uid, Id, ShortName, Rarity, Mutation?, Value, Income10, Steal?, Escrow, FreshUntil? }` |
| `ActiveCount(player) -> number` | active fish (carried ones included) |
| `IsMounted(player) -> boolean` | |
| `EscrowCount(player) -> number` | tests |
| `TankService.Mounted`, `TankService.Unmounted` | new Signals `(player, base)`, fired at the end of `mount` / `unmount`. DefenceService (join protection on the first mount of the session, a running `rest` re-applied, the dog shown, `LockLevel`/`HoldTime` and `HasDog`/`HasAlarm` copied to the base) and StealService (prompt refresh, cancel the base's theft on unmount) listen to them, so neither re-implements the "loaded AND has a base, whichever comes second" rule. |
| `TankService.SlotChanged` | new Signal `(base, index)`, fired after every slot write (catch, sale, theft, void, return, mount, unmount); StealService refreshes that prompt from it (BE-22) |

Changes inside:

- `onTankSell` check 6: `Steal` → `Denied locked` with the text «Её сейчас крадут!». A new check 6b:
  `Escrow` → `Denied escrow`.
- `ChooseReplacement` candidates: `Locked = rt.Locked or rt.Steal ~= nil or rt.Escrow ~= nil`.
- The `OnSerialize` hook returns the escrow `skipUid` (§3.2).
- `AddFish` with reason `catch` sets the runtime `FreshUntil = now + FreshCatch` and the slot attribute
  `FreshUntil` (AttrTime); stolen and returned fish get none (DC-08).
- **The steal channel never outlives a mount** (BE-5): `showEmpty` also clears `StealBy`, `StealEnd`,
  `Escrow` and `FreshUntil`, then `StealPhase` last; `unmount` sets `fish.Steal = nil` on every fish
  **before** `rt.Base = nil`. StealService's unmount handler then only cleans its own state.
- `onPlayerRemoving(player)`: (1) return its escrows to the victims (F8a/b/c) and strip them; (2) nothing
  as a victim (his removal is in his final save); (3) the old runtime drop. `escrows[player]` is empty
  afterwards.
- `DataService.Committed` / `Released` / `OnClose` handlers as in §3.2 and §3.3.
- `_debugSizes()` gains `Escrows`.

### 4.6 DataService and BaseService additions (small, exact)

- `DataService.Released = Signal.new()`, fired in `release(rec)` as `(rec.Player, rec.Committed)` before
  the record is dropped (also for kicks and memory-mode leaves), **once per record**: `release` returns
  at once if `rec.State` is already `"Released"` (`recover()` can reach it after `process` released the
  record, `DataService.luau:806-808`; BE-2).
- `DataService:OnClose(fn)`: hooks stored in a list. In the BindToClose callback they are called
  **first**, synchronously, each in `pcall`, before any record goes `Leaving`.
- `DataService:AmendLeaving(player, fn) -> boolean` (BE-1): runs `fn(rec.Data)` synchronously only
  while `rec.State == "Leaving"` and `not rec.FinalTaken`, and returns whether it ran. While
  `FinalTaken` is set (that attempt is in flight) `fn` waits in `rec.PendingAmends` and the call returns
  false: a failed attempt applies the waiting list to `rec.Data` before the retry; a committed, quiet or
  lost result (or the window running out) drops it (A1-02). `saveOnce`'s
  transform sets `rec.FinalTaken = true` where it takes the snapshot of a `releaseLock` save, and a
  **failed** release attempt clears it again before the retry (that snapshot is void; the retry takes a
  new one, with the amendment; W0 review). A lost reply cannot duplicate: the retry finds `Session` empty
  and writes nothing ("quiet"), which is the F8c loss again, never a second copy. It is the
  **only** write allowed past `CanWrite`; only TankService calls it, and only on `Tank`. The header
  says so. Why it cannot duplicate: the thief's copy is stripped and its entry dropped in the same
  synchronous step, and the victim's store either never committed the removal (it still has the fish)
  or commits the amended final save (it has it once).
- The header field-ownership list gains DefenceService (`LockLevel`, `Upgrades.Dog / Alarm /
  ShieldReadyAt`) and TankService (`Stats.Stolen`, `Stats.Lost`), and the rule "an escrow is never
  cleared by a timer" (BE-6).
- `BaseService:SetHomeGuard(fn: (player) -> (string?, CFrame?))`. In the `RequestHome` handler the guard
  runs **before** `homeCooldown:TryUse`:
  - a string → `Notify(player, text, "warning")`, no teleport, no cooldown spent;
  - a CFrame → `TeleportHome` lands there.

  StealService's guard:
  - carrying → «Сначала унеси рыбу за ограду!»;
  - the player's own base has a live theft → `CFrame.lookAt(spawn, spawn + the base's +Z)` (facing
    the court, whatever the spawn pad's own rotation; §11.4).

### 4.7 Speed modifiers (`Lib/Speed`)

```lua
Speed.Set(player, key: string, factor: number, untilClock: number?)
Speed.Clear(player, key)        Speed.ClearAll(player)        Speed.Forget(player)   -- PlayerRemoving
Speed.Factor(player) -> number  -- Π of live factors, ≥ MinFactor
Speed.Allowed(player, grace: number?) -> number -- CharacterWalkSpeed × the highest Factor of the last `grace` s
-- every change writes humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed × Factor (the only WalkSpeed writer)
```

- **Speed owns expiry** (BE-10): one `task.delay` per player to the earliest `untilClock`, with a
  generation token; it drops the expired keys and rewrites `WalkSpeed`. Nothing is dropped lazily "on
  read", so a slow can never outlive its key because nobody read it.
- Every modifier belongs to a theft, and every theft End clears them all first (§4.2). A new character
  starts at 16 by itself. Nothing connects to `CharacterAdded`.
- `Slowed` (Player attribute, **boolean**) is set when the `Dog` key appears and cleared when it goes,
  by Speed itself, never per tick (BE-11).
- **Clocks:** `os.clock` stays internal (cooldown maps, `untilClock`). Every time that becomes an
  attribute is server time through `AttrTime` (`StealCooldownUntil`, `StealEnd`, `ProtectUntil`, …).
- MarketService's jump check reads `WalkSpeed`: a slowed thief only gets a stricter check (`read_hooks`
  §4), and the End reset means it never sticks.

### 4.8 The carried fish

- `HeldRig.Build` is the same rig as the catch trophy: a clone ×`HeldScale`, welded to the Head,
  massless, no collisions. It uses the distinct name **`StolenFish`**.
- `HeldFish` is not reused: eight client modules react to that name (FishingController's hint,
  MoneyController, NotifyController, AmbientWater, FisherAnimController, TankWorldController,
  FishingFxController), and FishingService owns its own `HeldFish` timer.
- It replicates to every client (server instance). It is destroyed on every theft end.
- Its life (bob) and nameplate «🥷 Окунь $45» come from `TheftWorldController` (§5.4).

### 4.9 Alerts (server side)

- **Victim alert**: `StealEvent("Alert", { Phase, Thief = UserId, Name = DisplayName, Slot, FishId,
  Rarity, Mutation?, Short, Income10, End, Quiet? })` at hold start and at carry start. **Loud** at most
  once per (thief, victim) per `AlertCoalesce` 30 s, measured from the last loud one; the others go
  with `Quiet = true` (the client updates the plate silently: no pings, no shake). A griefer looping
  hold/release gets one loud alert per 30 s and the escalating waits of §4.2 (DC-10, BE-19).
- **Intruder** (alarm upgrade only): DefenceService's 1 Hz loop runs only while ≥ 1 mounted base has the
  alarm. For each non-owner player whose HRP is inside that plot, **while the base is not protected**:
  once per `IntruderCoalesce` 45 s per (intruder, owner) UserId pair, `StealEvent("Intruder", { Thief,
  Name })` to the owner and base `AlarmState = "intruder"` for 5 s (unless "theft").
- **Results**: `Saved { Reason, Slot, Text, Quiet? }`, `Lost { … }`, as in §4.2. **Nothing is broadcast
  to other players** (kid-safe).

### 4.10 Remotes (add to `RemoteNames.Events` and the header protocol)

| name | dir | payload | validation / limits (in this order) |
|---|---|---|---|
| `StealEvent` | S→C | `(kind, data)` | kinds: thief `Denied { Reason, Text, Quiet?, BaseIndex, Slot }`, `Hold { Slot, BaseIndex, Uid, FishId, Rarity, Mutation?, Short, Income10, End, Need }`, `Carry { End }`, `Cancel { Reason, Text, Phase }`, `Done { Fish, Result, Name }`; victim `Alert { … Quiet? }`, `Saved { Reason, Slot, Text, Quiet? }`, `Lost { Fish, Name, Until, Kind }`, `Intruder { Thief, Name }`; void/return `Returned { Fish, Text, Result?, Price? }` (F7/F8 toasts; the victim's return names `Result` "stored" / "replaced" / "sold" and the coins of a full tank, A1-01) |
| `ShieldActivate` | C→S | `()` (args ignored) | 1) the `DefenceRequests` bucket (Burst 4, 1/s; empty → silent); 2) `CanWrite` (`loading`); 3) a mounted base (`nobase`); 4) not stealing, asked through the steal probe (`stealing` «Сначала закончи кражу»); 5) the remaining protection < `StackBelow` 60 s (`protected` «Ты и так под защитой — ещё {t}»); 6) `now ≥ ShieldReadyAt` (`cooldown` «Щит перезаряжается — ещё {t}»). OK → state, attributes, `SaveSoon`, `ProtectionChanged` (StealService cancels a hold or returns a carry on the base), `DefenceEvent("Shield", { Until, ReadyAt })` |
| `DefenceBuy` | C→S | `(item: "Dog" \| "Alarm" \| "Lock")` | 1) `typeof == "string"` and a known item (else silent); 2) the bucket; 3) `CanWrite`; 4) a mounted base; 5) `Dog`/`Alarm` already owned → `owned` «Уже куплено»; `Lock` at `#Levels` → `max` «Замок уже лучший»; `Lock` at `SaleMax` → `soon` «Сильнее замки — скоро в магазине»; 6) the price from config only; `SpendMoney(player, price, "defence:" .. item)` false → `money` «Не хватает: нужно {$}»; 7) apply (`Upgrades` or `SetLockLevel`, base attributes, the dog shown; `LockChanged` → StealService rewrites `HoldDuration`), `SaveSoon`, `DefenceEvent("Bought", { Item, Level?, Price })` |
| `DefenceEvent` | S→C | `(kind, data)` | `Bought`, `Denied { Item?, Reason, Text }`, `Shield { Until, ReadyAt }` |

There are no RemoteFunctions. Clients never send prices, levels, slots, uids or positions. No handler
yields between its check and its mutation. Steal has no client→server remote at all: it is prompts only.
With `SaleMax = 1` every Stage 4 item is a one-time buy, so "50 buys in a frame → one purchase" holds per
item; a test that patches `SaleMax` checks "≤ Burst levels, each paid" instead.

### 4.11 Replicated state (what clients read)

**Player attributes:**

- `Stealing` = "hold" | "carry" (written last);
- `StealCooldownUntil` (AttrTime; the wait is kept by UserId, so `TankService.Mounted` writes it again on
  a rejoin while it runs, A2-03), `Slowed` (boolean);
- `ShieldUntil`, `ShieldReadyAt` (AttrTime). They stay **public** (BE-24, decided): a cheat client could
  read a victim's shield timing, which is genre-normal, but no UI ever shows another player's shield
  readiness (the tank sign and the flag show only active protection; DC-12);
- `HasDog`, `HasAlarm` (bool), `LockLevel` (int); the Stage 3 `Income` ($/s) feeds the `weak` filter.

**Base model** (`Workspace.Bases.Base_N`):

- `ProtectUntil` (AttrTime), `ProtectKind`;
- `AlarmState` ("theft" | "intruder");
- `Thief` (UserId);
- `HasDog`, `HasAlarm`, `LockLevel`, `HoldTime`.

All of them are cleared on unmount, in one place (`TankService.Unmounted`, before the base can be given
to someone else; BE-27), together with the dog's state, the protection generation and the prompts'
`HoldDuration` (back to `Lock.BaseHold`) and `ObjectText ""`.

**Slot model:** `StealBy`, `StealEnd` (AttrTime), `StealPhase` (last); `Escrow` (bool, on the thief's
slot while escrowed); `FreshUntil` (AttrTime, after a catch). A separate channel from `Event` (do not
overload it). Clients listen to `StealPhase`, `Escrow` and `FreshUntil` and read the rest. The new slot
events are `"<n>|stolen|<thiefUserId>"` (the detail now carries the thief) and `"<n>|void|"` (quiet).

**Dog model:** `Unlocked`, `DogState`, `DogPos`, `DogTarget`. **Character:** `StolenFish`.

**Time-bounded maps** (server memory, reported apart in `_debugSizes`). They are keyed by **UserId**, so
a rejoin does not reset a wait, a loss or a quick-rejoin mark, and they are pruned on every write, on
every `PlayerRemoving` and inside `_debugSizes()` (BE-26):

- StealService: `cooldowns[userId]` (until), `fails[userId]` (times within `FailWindow`),
  `tagged["thief:victim"]`, `alertCoalesce["thief:victim"]`;
- DefenceService: `losses[userId]` (times within `VictimWindow`), `leftAt[userId]` (within
  `QuickRejoin`), `intruderSeen["intruder:owner"]` (UserIds, not bases, so a freed base keeps nothing).

Per-player maps keyed by `Player` (cleaned on PlayerRemoving): `loadInfo`, the buckets, `byThief`.

### 4.12 Stage 5 hooks (named, not built)

| need | Stage 4 provides |
|---|---|
| the shop sells lock levels («Лучший замок») | `DefenceConfig.Lock.Levels` (Hold, Price) for all 5 levels, every level working at runtime; `DefenceBuy("Lock")` already sells any level ≤ `Lock.SaleMax`; `DefenceService:SetLockLevel(player, n)`; the Lock card. Stage 5 raises `SaleMax` to 5 and gives the card its level pips |
| the shop page | `HUD.DefencePanel` on the sheet shell = the shop's «ЗАЩИТА» tab; `RightButtons.DefenceButton` becomes «МАГАЗИН» (the 3rd column slot is now used, so the shop **replaces** this button; a 4th square does not fit in 0.6 H) |
| prices rescale | every price in `DefenceConfig`; `EconomyConfig.IncomeScale` |
| the shield in the shop | the Shield card + `ShieldActivate`; the alert quick action stays |
| more defence levels (dog speed, alarm range) | `Upgrades` accepts any JSON; `Upgrades.Dog / Alarm` keep a newer server's number ≥ 0 (§3.1), and `DefenceService` reads ownership only through `PlayerData.Owned(v)` = `v == true or (number and v > 0)` already today, so levels are a migration-free change (W0-02) |

---

## 5. World

### 5.1 The steal prompt

- It uses the **stock prompt UI** (it matches the reference; touch, keyboard and gamepad come for free).
  It sits at the attachment, knee height (y 2.6), in the lower middle of the screen from the follow
  camera. No `UIOffset` in Stage 4; check it in Studio.
- `RequiresLineOfSight = false` is explicit (the Roblox default is true, and the sim ignores LOS). A
  static test checks every `Instance.new("ProximityPrompt")` in `src` (§7.1).
- **Client-local hiding** (TheftController; BE-14). A hidden prompt gets the **local**
  `MaxActivationDistance = 0`; showing it again restores `StealConfig.Prompt.MaxDistance`. The server
  writes that property only at creation, so no replication can undo the local value, whatever the
  server does with `Enabled` (in rev. 1 a server `Enabled` write overwrote the local hide for a frame,
  and a missed re-apply showed «Украсть» on the owner's own fish). The filter is
  `StealRules.CanStealView` (the `Client` rows of `TheftChecks`), re-run on the attribute changes that
  feed it and on one `task.delay` to the earliest expiry (cooldown, protection, `FreshUntil`). It hides:
  - every prompt on the own base, and every prompt while the player has no base;
  - while `Stealing` is set or `StealCooldownUntil > now`;
  - the whole base while it is protected (`ProtectUntil`) or has a live theft (`Thief`);
  - a slot whose fish is being stolen (`StealPhase`), escrowed (`Escrow`) or fresh (`FreshUntil > now`);
  - a victim with fewer than 3 fish, or much weaker than the player (the Player `Income` attributes);
  - fish the player cannot take: own tank full and loot ≤ own weakest non-escrowed income.

  **Never the prompt the local player is holding**: a prompt that goes out of range ends its hold on the
  client, so the held one is ended only by the server (`Cancel` / `Denied` → `InputHoldEnd`). After the
  hold completes (the carry) every prompt may hide.

  The server re-checks everything. (P2: the Stage 3 `TankPrompt` hide in `TankWorldController` can move
  to the same trick.)

### 5.2 Displays during a theft (TankWorldController + TankDisplay; client only)

They are driven by the slot's `StealPhase`, read on its change and on the first build of a base.

- **Hold:**
  - the display fish rises 1.6 studs over 0.3 s, tilts 12° toward the aisle and struggles. The life tween
    is swapped for a faster one at ≤ 3 Hz (STYLE: nothing flashes faster);
  - a red client PointLight pulses at the LightBar (the `TankDisplay.flash` recipe, Berry, 2 Hz);
  - **«КРАДУТ!»**: a BillboardGui on a client Attachment over the display front at LightBar height (in
    front of the glass, like `FxTankTag`), `MaxDistance` 90, a Berry word with a `UiFx.ringTimer` to
    `StealEnd`. Its letters are capped like the Stage 3 tags. The aisle tag of that slot hides meanwhile.
    `AlwaysOnTop` (like «УКРАДЕНО!»; B1-06): the arcade lanterns hang at its height and cut the ring and
    the letters from the court mouth and the spawn; the Stage 3 tags stay depth-tested.
- **Hold → carry:** a client clone of the display fish arcs out **through the front face** (apex ≤ 12.5,
  under the ceiling at 13.15) to the thief's head in 0.35 s, then disappears as `StolenFish` takes over.
  The display fish is **destroyed** (so the part budget holds). «КРАДУТ!» → «УНОСЯТ!».
- **Cancelled during the hold:** the fish drops back with the Stage 3 `in` splash.
- **Returned during the carry:** a clone arcs from the thief's head (or from the last known spot if he is
  gone) back into the display, then the display fish is rebuilt with the `in` splash.
- **Event `stolen`:** a red «УКРАДЕНО!» word pops at the display and fades in 2 s, red sparks
  (`sparkles_main`, Berry), and the empty display as in Stage 3. A thief UserId in the detail lets the
  sparks aim at him.
- **Event `void`:** quiet removal.
- Budget: ≤ 2 emitters per player (Stage 3 rule), ≤ 1 clone in flight per theft, nothing per frame while
  idle: arcs and struggles are tweens with their cancel in the slot's Trove.

### 5.3 The base: lamp, siren, dome, sign (TheftWorldController; client only, 0 server parts)

- **Lamp** (`Alarm.Lamp`, server part, never written by the server):
  - while `AlarmState` is set, one looping tween (`RepeatCount −1`, `Reverses`, half of `LampPeriod`
    0.5 s; `IntruderPeriod` 1 s for "intruder") on its `Color` with `Material = Neon`, from a dark
    `LampDim` to a hot `LampOn` (dark ↔ bright, not red ↔ red: the base and the mast are red too; B1-05);
  - plus a client `PointLight` (Range 32, Brightness 3 ↔ 0, `Shadows = false`) on a client Attachment
    under the cap;
  - restored exactly when the state clears or the base drops out of the 260-stud range.
- **Siren** (`HasAlarm` and `AlarmState == "theft"`):
  - two red `SpotLight`s back to back, **pitched down `Siren.Pitch` 38°** (a red pool sweeps the yard and
    the court; level beams reached the ground only ≈ 32 studs out, where the falloff is ≈ 0), and along
    each a `Beam` (`BeamLength` 14, `BeamWidth0` 0.6 → `BeamWidth1` 5, `LightEmission` 1, `LightInfluence`
    0: seen by day and on phones that drop local lights), all on an invisible client spinner part in the
    lamp (1 part, `Theft` reserve) spun by one looped CFrame tween (half a turn per `SirenSpin / 2`: a
    turn per 1.2 s; B1-03);
  - a looped `electronicpingshort.wav` (0.6 s period) within `BeepRange` 120;
  - (P2, DC-17: the bell swing ±18° and the red court lanterns. The owner on his pier never sees them,
    and the thief already has enough signal.)
- **The thief marked** (`HasAlarm` and base `Thief`):
  - one `Highlight` on the thief's character (Berry fill 0.7, outline Berry): `DepthMode = AlwaysOnTop`
    on the owner's client, `Occluded` on others;
  - a «ВОР!» BillboardGui over his head;
  - created on start and destroyed on end (no `Enabled` toggling: disabled Highlights still use slots).
- **Shield dome** (`ProtectKind` in `World.Dome.Kinds`, i.e. **the shield only**; DC-15):
  - one client Part `Shape = Ball`, Ø 116, at base-local (0, 0, 88), `Material = ForceField`, colour
    `Guard.Bottom`, Transparency 0.15; 0.8 (`Inside`) when the camera **or the own character** is inside,
    lerped between them within `Dome.Near` 16 studs outside the skin (B1-02: the owner on his spawn pad
    is inside the dome while his follow camera is outside — the whole court was seen through the dome's
    face, a full-screen overdraw on his phone);
  - `CanCollide/CanQuery/CanTouch/CastShadow = false`;
  - only for bases within 260 studs of the camera, and on touch devices only the `PhoneMax` 2 nearest; a
    0.4 s fade in and out; checked on the 0.5 s chain.
  - Join, newbie, after and rest get no dome: at server start all 8 bases are protected at once, and 8
    transparent spheres are heavy overdraw on phones (and would make the shield look ordinary).
- **Tank sign** (`FxTankSign`, owned by TankWorldController), a third line for every viewer, **on top of
  «+$42/с»** (the sign grows up; growing down put it behind the fountain statue from the gate and the
  spawn; B1-04): «🛡️ 0:42» (Guard) while protected, then the owned defences «🔐1 · 🐕 · 🚨» (only the owned icons; DC-12). The
  defences deter and show off a purchase; whether the **shield is ready** is never shown (it would hand
  thieves the timing). The 1 s chain updates the countdown only while protected.
- **Flag** (`Flag.Pole.SignAttachment.OwnerSign`): a client-local label «🛡️ 4:12» **over** the owner sign
  while the base is protected, any kind (0 parts; the sign's own `MaxDistance`), so thieves see
  protection across the map without a dome. The sign's layout has no room: a sibling client
  BillboardGui on `SignAttachment` of its size, raised `Flag.Raise` of its height (under it the label
  sat on the flag cloth — Guard blue on the blue, cyan and purple bases; over it there is only sky;
  B1-10).
- **Pier word** (`FxPierTank`, own base): while the own base has `AlarmState == "theft"` it reads «🚨
  КРАДУТ!» (Berry, 2 Hz pulse; no display number: DC-14). It shows during the bite and the minigame
  too. It still hides during `CounterHold` and the own trophy, where the trophy nameplate stands.

### 5.4 The dog and the carried fish (TheftWorldController)

- **The dog render.**
  - When `Unlocked` is true: within 200 studs, follow `DogPos` with an exponential lerp
    (α = 1 − e^(−12·dt)) on a RenderStepped connection that exists **only while `DogState` ≠ "Sleep"** and
    the base is in range (connected on wake, disconnected on sleep).
  - The pup faces its motion, with a hop bob of 0.35 studs at 4 Hz while running, its paws on the ground
    under `DogPos` (one downward ray per `DogPos` change, the base's `Grounds` / `Arcades` only: the
    arcade deck and the crosswalk paving are above the base point; B1-09).
  - «ГАВ!» pops (the "words in the world" style) on `Alert` and when a bite starts, adorned to the pup's
    body so it rides with the running dog (B1-08); «ВОР!», the carried plate and «ГАВ!» share one range
    `World.WordRange` 120 and the HUD rule (`TankWorldController.TrackWord`; B1-07).
  - `smoke_main` puffs at the slowed thief's feet (within the emitter budget).
  - Asleep: the server's rest pose (the pup pivot the server set at `Dog.Rest`), raised on this client so
    its paws stand on the crosswalk paving (the template height sank them ≈ 0.45 studs), cached on wake
    and restored with `PivotTo` on sleep; a still «💤» over it (`World.Dog.Sleep`, `SleepRange` 60; no
    tween: an idle base does no per-frame work; B1-09).
- **The carried fish.**
  - `StolenFish` gets the Stage 2 life on a looped tween (bob ±0.15 and a sway; `FishLife` if its API
    fits).
  - A Berry nameplate «🥷 Окунь $45» (the trophy nameplate recipe, capped letters).
  - `FisherAnimController`: treat `StolenFish` like `HeldFish` for the arms-up hold pose (one name check in
    its existing child handlers) **if `compile_limits` keeps ≥ 24 spare registers**; else P2.

### 5.5 Budget summary

| item | parts | where |
|---|---|---|
| prompts, lamp, Highlight, words, sounds, PointLights, the siren's SpotLights and Beams, the flag label | 0 | — |
| siren spinner (B1-03) | 1 invisible part per siren in range (one base's theft at a time near you), client | `Theft` |
| dog shown | 0 (17 already counted, hidden) | template |
| `StolenFish` | ≤ 20 per theft, replaces the destroyed display fish | `TankFish` reserve |
| arc clone | ≤ 20, ≤ 0.4 s, client | `RuntimeReserve.Theft` 60 |
| dome | 1 per **shielded** base in range (≤ 8; ≤ 2 on phones), client | `Theft` |
| new template parts | **0** (`Dog.Pup` is a Model) | — |

---

## 6. UI («Симулятор», mobile first, never covering the own fisher)

### 6.1 Widgets and owners (contract names; tests and controllers find them by name)

| widget | built by | driven by |
|---|---|---|
| `HUD.RightButtons.DefenceButton` (`Theme.simButton` "square", token **Guard**, Icon 🛡️, Caption «ЗАЩИТА», Tier Small, LayoutOrder 80 (above «САДОК» 90), `SimOpts.stroke 5`) → `Badge` («!», hidden), `Cooldown` + `Drain` + `CooldownText` (Home's veil recipe) | `gui/Hud.luau` | `DefenceController` |
| `HUD.Status.BaseBadge.ShieldChip` (glass stadium overhanging the badge's right end, Small tier) → `Icon` 🛡️, `Label` «0:42» (italic) | `gui/Hud.luau` | `DefenceController` (the badge itself stays HudController's) |
| `HUD.TheftBar` (the bottom band, centred; §6.4 rev. 3) → `Plate` (sim, Night / Berry / glass), `Icon` (socket 🥷/🏃/⏳), `Title`, `Bar.{Track, Fill}` (siblings: Fill drawn over Track), `Time` (italic), `Sub`, `DogChip` (Sun «🐕 СОБАКА!», hidden) | new `gui/Steal.luau` | `TheftController` |
| `HUD.TheftTitle` (top band) → `Title` («ДОБЫЧА!» / «СОРВАЛОСЬ!», `Theme.title`), `Sub` | `gui/Steal.luau` | `TheftController` |
| `HUD.TheftAlert` (toast slot) → `Plate` (Berry sim), `Icon` 🚨, `Text.{Title, Sub}`, `Buttons.{Shield (Guard «🛡️ ЩИТ», the largest target), Home (Grape «🏠 ДОМОЙ»)}`, `Compact` (pill variant: `Label`, `Shield`, `Home`) | new `gui/Alert.luau` | `AlertController` |
| `HUD.DefencePanel` on the sheet shell → `Panel.{Strip, Header.{Icon 🛡️, Title «ЗАЩИТА», Money}, Close, Cards.{ShieldCard, DogCard, AlarmCard, LockCard}}`; each card: `Icon` (sim disc), `Name`, `Effect`, `State`, `Buy` (button: `Label`, `Price`). (No lock pips in Stage 4: the levelled lock is Stage 5's.) | `gui/Sheet.luau` (shell, unchanged) + new `gui/Defence.luau` | `DefenceController` + `Controllers/Sheet` |
| the tank-panel Sell button's labels «КРАДУТ!» / «В ПУТИ…» (no new widget) | — | `TankPanelController` / `TankCards` |
| `FishingController.HurryCard()` (new public function; DC-02) | — | called by `AlertController` |

There is **no alert pointer** in Stage 4 (DC-16): the victim acts with ЩИТ, or with «ДОМОЙ», which lands
him facing the court; the thief has the red beam. `NotifyController.Point` is not built.

`ClientMain` ORDER gains `"DefenceController", "AlertController", "TheftController",
"TheftWorldController"` (after `TankWorldController`, before `FishingController`). New logic goes in new
controllers (register budgets, `read_ui_tests` §8). FishingController and FishingFxController are only
touched inside existing functions, plus the one `HurryCard` function.

### 6.2 The «ЗАЩИТА» button and the one-tap shield

- **Where:** the right column's 3rd slot (top), measured to fit on all 5 screens (phone 776..836 ×
  88..144). It shows when the base is assigned and the data loaded, with a pop-in after «САДОК» in the
  intro chain (badge → Wallet → САДОК → ЗАЩИТА, 0.3 s apart). Never animate the column's Position.
- **Press** → `DefenceController.Toggle()` (open/close the sheet). The sheet's Busy rules apply: refused
  with a `wiggle` during the bite, the minigame or the card.
- **Alert mode** (the HUD attribute `AlertPhase` = "hold" **or "carry"** (DC-01), written by
  AlertController from `StealEvent("Alert")` and cleared with the theft, and `now ≥ ShieldReadyAt`, and
  the player is not stealing himself):
  - the caption becomes «ЩИТ!», the face recolours to Berry → Guard pulse (`UiFx.glowRing` loop, Berry,
    its stop in a Trove), and the Badge shows «!»;
  - a press fires `ShieldActivate` **directly**, without the sheet. It works during the minigame: the
    minigame's input is the ActionButton only (`FishingController :7474`).
- **Cooldown look:** while `ShieldReadyAt > now` the `Cooldown` veil drains (one linear tween over the
  remaining time) and `CooldownText` shows «2:59» on a 1 s chain, only while the sheet is closed and the
  veil visible. When ready: «ГОТОВ!» `popIn` on the caption for 1.5 s.
- **Badge «!»** also shows **once per session** when the first defence becomes affordable (≈ 2.5 min
  for the median kid, inside his newbie protection; DC-13), and the button bobs at the protection's
  `EndingWarn` (§2.4).
- **Trophy chip on phones** (`read_ui_tests` §2.2): with 3 column buttons and a HUD < 600 px tall,
  NotifyController places the chip **left of the column** at the column's top (x = column left − 16 −
  chip width). Tablet and desktop are unchanged.

### 6.3 The victim's alert (AlertController; never covers the fisher, never takes the minigame)

**Layers, always (no layout cost):**

- a thin Berry `UiFx.edgeVignette` pulse: size 0.06 on phones and 0.10 elsewhere, period 0.5 s,
  opacity ≤ 0.35 (photosensitivity: no full-screen flash);
- `HudController.HomeAlert(true)`: a Berry glow ring on «ДОМОЙ», caption «ДОМОЙ!»;
- the «ЗАЩИТА» alert mode (§6.2);
- the pier word (§5.3);
- 3 pings (`electronicpingshort`, 0.18 s apart), unless `Quiet`.

**The plate** `HUD.TheftAlert`:

- **Content:**
  - hold: Title tier «ВОР В САДКЕ!», Small «Ника крадёт: Окунь»;
  - carry: «ВОР УБЕГАЕТ!» / «Ника уносит: Окунь — жми ЩИТ!» (while the shield is ready) or «Ника
    уносит: Окунь»;
  - buttons [🛡️ ЩИТ] and [🏠 ДОМОЙ] in both phases (on Home's cooldown it shows the veil);
  - **shield on cooldown:** the ЩИТ button stays, as a Slate «⏳ 1:12» (a tap wiggles it), so the kid
    sees *why* (DC-04);
  - **the victim is stealing himself:** no buttons, and Sub reads «Пока крадёшь сам, щит не включить»
    (his «ДОМОЙ» is guarded and the shield refused, so the buttons would be dead taps).
- **Layout** (DC-04): text on the left, buttons on the right of the same row. **ЩИТ is the plate's
  largest target: ≥ 56 px tall and ≥ 35 % of the plate width**; ДОМОЙ ≥ 44 px. Width ≤ min(0.62 W,
  520 px), inside the toast column. Phone height ≈ 72 px. «Крупные кнопки» in the spec: 44 px is the
  floor, not the goal for the one tap that matters.
- `popIn` with a shake (not for `Quiet` updates). It sits at the top of the toast column:
  `NotifyController.Reserve("alert", px)` shifts the toasts below it.
- **When:**
  - idle, walking, Bite and Reeling (like today's P3 danger toast, which may show then): the full plate;
  - on phones, if the plate's rect intersects `FishingLayout.fisherBox()` → the **Compact** pill
    (≈ 56 px: «🚨 ВОР! Окунь» + the ЩИТ button, or [🏠] when the shield is not ready) placed by
    `FishingLayout.clearOf` at the first free spot (≥ 16 px from Jump, the column, the status stack);
  - **the alert outranks the catch card** (DC-02): when AlertController sets `AlertPhase` it calls
    `FishingController.HurryCard()`. A visible card takes its **normal close path**, as if «ЗАБРАТЬ!»
    was tapped, so the Stage 3 flight into «САДОК» still plays; a card still in its beats or in the
    Epic+ delay closes as soon as it settles, and a rarity slam in progress may finish (≤ 0.9 s). The
    plate pops in when the card is closed and `CounterHold` clears (≈ 1 s), if the theft is still live.
    In rev. 1 a Mythic card held the plate for ≈ 6 s, longer than the whole lock-0 theft.
- **Ends** with the theft. The result toast follows (`theft` kind for a loss, `saved` for a save; none
  for a `Quiet` save). Buttons answer at once: ЩИТ shows ⏳ until `DefenceEvent("Shield")` or `Denied`.
- Bound by name in Start; connections in a Trove; idle = no frame jobs (the vignette and glow are timer
  loops; STYLE §6.6).
- **The intruder toast** (alarm): `NotifyController.Show("Ника у тебя во дворе!", "warning", { icon =
  "👀" })` and the «ЗАЩИТА» button bobs (`badgeBob`) for 5 s. The server sends none while the base is
  protected.

### 6.4 The thief's banner and celebration (TheftController)

- **Where (rev. 3, B1-01, §11.5):** the **bottom band**, centred, its top at ≈ 0.74 H, ≥ 16 px from the
  thumbstick and Jump (`FishingLayout.clearOf`; on phone_small that caps it at ≈ 400 px), under the
  thief's character and the stock «Украсть» prompt (≈ 0.5–0.7 H). While `HUD.Stealing` is set,
  **`HUD.Status` hides** (badge, wallet, shield chip: none of them can change during a theft; it pops
  back after `done` / `fail`, before the «ДОБЫЧА!» flight into «САДОК»). Why: from the thief's follow
  camera the robbed display — the lifted, struggling fish, «КРАДУТ!» with its ring, the red pulse —
  fills the top-centre band x ≈ 0.36–0.64 W, y ≈ 0.10–0.45 H on every device
  (`TankWorldController.StealRect(base, slot)`; tools/builder/DESIGN.md), exactly where Status and the
  toast column are: rev. 2's top banner (the reference's «Украдите яйцо!») hid the very thing the hold
  is about (renders `steal_hold_thief_hud` vs the mocked rule `steal_hold_thief_rule`). The carry
  keeps the same place (the fish on his head and its plate are then in that band). The bar no longer
  needs `NotifyController.Reserve("theft", px)`; the victim's TheftAlert keeps the toast column (§6.3),
  so a thief who is robbed meanwhile sees both without stacking.
- **Size:** width ≤ min(0.62 W, 520 px), phone height ≈ 0.15 H (≈ 50 px), Title tier ≥ 20 px on
  phone_small.
- **States:**

  | state | plate | content |
  |---|---|---|
  | `hint` (in a foreign plot, not stealing; a 0.5 s `task.delay` chain tests `StealRules.InPlot` only while the character exists) | glass | ⏳ / 🛡️ / 🐠 + one line (the reasons of §1.1 step 2; the first-time hint) |
  | `hold` | Night, Berry bar | 🥷 «КРАДЁШЬ: ОКУНЬ» + `Bar` filling to `End` (`UiFx.timerBar`, a frame job only while holding) + `Time` «1,8 с» + `Sub` «Не отходи!» |
  | `carry` | Berry | 🏃 «БЕГИ ЗА ОГРАДУ!» + `Bar` draining to the carry `End` + `Sub` «Не попадись хозяину»; `DogChip` «🐕 СОБАКА!» pops in while `Slowed` |
  | `fail` | Berry, shake | «СОРВАЛОСЬ!» (TheftTitle, smaller) + the reason line; 2.2 s, then gone |
  | `done` | — | TheftTitle «ДОБЫЧА!» slam (`Theme.title`, a Gold/Leaf gradient), Sub «Окунь — в твоём садке · +$4/с», `confetti(hud, { origin = the StolenFish on screen })`, a 🐟 `flyTo` from that point into «САДОК» |

- **Carry guide:** a client `Beam` (the `FishingGuide` recipe, Berry, `FaceCamera`, width 0.3 → 0.8)
  from the HRP to `StealRules.NearestExit` (gate centre (0, 16), the nearest side-fence point (±70, z
  clamped 20..121), or the nearest back arch (±40, 170)), recomputed on the 0.25 s chain. No screen
  pointer (DC-16).
- **Hold arrival:** «САДОК» must not play the `Stored` arrival at 0.05 s. TheftController sets the HUD
  attribute **`TankIncoming`** before the flight, and TankButtonController waits for it to clear (not
  `CounterHold`: that one also means "catch on screen" to four modules). "Replaced" →
  `MoneyController.Celebrate(price, TankButton)` after the arrival (Stage 3 flow).
- **`HUD.Stealing`** attribute (= the phase) for the others:
  - FishingController's "where to go" hint and guide beam yield while it is set (one attribute check
    inside the existing hint function, 32 spare registers);
  - HudController greys «ДОМОЙ» with the lock look while `Player.Stealing == "carry"` (a press shows the
    server's guard text), and hides `HUD.Status` while `HUD.Stealing` is set (the band rule above).
- **Denied:** `InputHoldEnd()` on the prompt the payload names (`BaseIndex`, `Slot`), then the `hint`
  state with the text for 2.5 s (no text for `Quiet`). A `Cancel` in the hold phase also calls
  `InputHoldEnd()` on the held prompt: the server no longer disables prompts, so this is how a shield
  or a tag ends the client's ring (BE-15).
- **No reply** (BE-16): if neither `Hold` nor `Denied` arrives within `Hold.NoReply` 1.0 s of the local
  `PromptButtonHoldBegan`, TheftController calls `InputHoldEnd()` and the banner says «Подожди
  секунду», so a silently dropped request never leaves a full ring with nothing happening.

### 6.5 The shield chip

- `Status.BaseBadge.ShieldChip`, the glass stadium reserved in Stage 3 K-19.
  - Shown while the own base `ProtectUntil > now`, any kind (shield, join, newbie, after, rest).
  - «🛡️ 0:42» italic (minutes for long ones: «🛡️ 6:12»): the shield kind on a solid Guard plate
    (`UiFx.setCandy`), the others on glass with a Guard icon.
  - 1 Hz `task.delay` chain; the last 10 s pulse Sun (Home's cooldown rule); at the end a `popOut` and,
    for the shield kind, the toast «Щит погас».
- **Width:** ≤ 90 px at the Small tier, within the measured free row (phone_small 124 px).
- **Intro:** hidden while `HUD.BaseBanner.Visible`; pops in after the badge. The join protection starts
  at mount, so it is the first thing a new kid sees, with the toast «Защита новичка 5:00 🛡️ — лови
  спокойно!» (`newbie`) or «Твой садок под защитой {t}» (`join`).
- **Ending:** `EndingWarn` 15 s before a `join`/`newbie` protection ends: «Скоро воры смогут красть.
  Увидишь «ВОР В САДКЕ!» — жми 🛡️ ЩИТ!», and the «ЗАЩИТА» button bobs (DC-07).
- Must be added to `FishingController.statusBoxes()` / `dockBand()`, `FishingFxController
  boxes("Status")` and `TankWorldController.hudRects()` the way `FlagSocket` is (inside existing
  functions).

### 6.6 The «ЗАЩИТА» sheet (DefenceController + `Controllers/Sheet`)

- **The sheet shell** as in Stage 3 (placement, glass on phones, Night plate on tablet and desktop,
  closes for fishing, hides `HUD.Fishing` under it). Its `Layout` is `DefenceConfig.Panel`. The header
  shows 🛡️ «ЗАЩИТА» and the Wallet's «💵 $12 345» (glass chip).
- **One sheet at a time** (`read_ui_tests` §0.5): `Controllers/Sheet.luau` keeps a module-level `current`.
  Opening one closes the other with reason "switch" (no hide animation, no Toasts ZIndex or
  `HUD.Fishing` restore in between).
- **Cards** (one row; on phones 0.23 of the cards window, ≥ `CardMin` 96 px, Aspect 0.78; phone_small
  scrolls the 4th card, with an explicit `CanvasSize`). The effect lines speak in "time to save your
  fish", which a kid can value (DC-13):

  | card | icon | name (CAPS) | effect line (sentence case) | button states |
  |---|---|---|---|---|
  | ShieldCard | 🛡️ | ЩИТ | «Никто не украдёт 1 минуту» | Guard «ВКЛЮЧИТЬ» whenever activation would be accepted (DC-03) → active glass «🛡️ 0:42» → Slate «⏳ 2:59» with `ringTimer`; protected ≥ 60 s by another kind: glass «ТЫ ПОД ЗАЩИТОЙ» |
  | DogCard | 🐕 | СОБАКА | «Вор с рыбой бежит вдвое медленнее» | Gold «💵 $6 000» → two-tap «КУПИТЬ?» → Leaf stamp «КУПЛЕНО» |
  | AlarmCard | 🚨 | СИГНАЛИЗАЦИЯ (СИГНАЛКА on cards < 120 px; width-tested) | «Узнаешь о воре, как только он войдёт» | the same as Dog |
  | LockCard | 🔐 | ЗАМОК | «Вору держать 4 с вместо 3» | the same as Dog («💵 $1 500» → «КУПЛЕНО»); bought: Sub «Сильнее замки — скоро в магазине» (DC-11); `SaleMax = 0` hides the card |

- **Buying:** the Stage 3 two-tap confirm (first tap → «КУПИТЬ?» + 3 s ring; a second tap counts after
  `ConfirmArm` 0.4 s; mash-proof). Then `DefenceBuy(item)` and the button shows ⏳.
  - `Bought` → `MoneyController.Spend(price, card.Buy)` (new: Berry count-down on the Wallet, 💵 fly
    out of the Wallet into the card, «−$6 000» float), the card's stamp, confetti on the card, for the
    dog a «ГАВ!» toast «Собака охраняет твой двор!».
  - `Denied` → card wiggle + a warning toast over the sheet.
  - Not enough money: the price button is Slate with the price kept readable, and a tap shows
    «Не хватает: нужно $6 000».
- **Live values:** one 1 s chain while open (shield timer, affordability).
- **Budgets:** phone fill ≤ 2.5×, ≤ 60 temp GUI objects, `activeJobs() == 0` after juice, connections
  back to baseline after close. `checks.py` `CONTAINERS` / `SHEETS` gain `HUD.DefencePanel`.

### 6.7 The tank panel during a theft (TankPanelController / TankCards)

Trimmed to the minimum (DC-18). `watchSlots` also listens to `StealPhase` and `Escrow`:

- **hold / carry:** the card's Sell button is disabled with the label «КРАДУТ!» (a tap gives the
  server's «Её сейчас крадут!»).
- **stolen:** the normal Stage 3 card removal.
- **escrow** (the thief's own fresh fish): the Sell button reads «В ПУТИ…» (Slate) while the slot's
  `Escrow` is set (BE-21).

(P2: the Berry «🚨 КРАДУТ!» pill with a timer bar, the «УКРАДЕНА!» stamp, and scrolling to the card when
an alert fires.)

### 6.8 Wallet and «САДОК» on a theft

- **Victim:** the rate rolls down with the Berry flash at the carry start (the fish leaves his income;
  Stage 3 already flashes any `Income` drop). At the credit, «САДОК» does a Berry `rimFlash` + `wiggle`
  and the chip rolls down (TankButtonController tells a theft from a sale by `StealEvent("Lost")`).
- **Thief:** the `Stored` arrival after the flight (§6.4). The rate rises when the escrow clears, with
  the Stage 3 gold flash (the fish starts earning).

### 6.9 Layout per device (contract for the renders and the layout pass)

| widget | phone 844×390 | phone_small 667×375 | tablet 1024×768 | desktop 1280×720 |
|---|---|---|---|---|
| DefenceButton | 776..836 × 88..144 | 603..660 × 88..141 | 910..1014 × 174..278 | 1163..1267 × 356..460 |
| ShieldChip | right of the badge, ≤ 90 px, inside 558..760 | inside 463..587 | inside 720..894 | inside 848..956 (16 px to the player list) |
| TheftBar (bottom band; Status hidden while stealing) | 162..682 × 303..353 | 133..533 × 292..340 | 252..772 × 583..667 | 380..900 × 547..631 |
| robbed display (StealRect, the hold; nothing of the thief's HUD in it) | 351..492 × 39..174 | 265..401 × 38..168 | 373..650 × 77..344 | 510..769 × 72..322 |
| TheftAlert | toast column 186..658, from y 152 | 147..520, from y 148 | 225..799 | 444..836 (≤ 512 px: chat) |
| TheftAlert ЩИТ button | ≥ 56 px tall, ≥ 35 % of the plate | the same (the tightest column) | the same | the same |
| trophy chip | left of the column (phones) | left of the column | unchanged | unchanged |

All rects are ≥ 16 px from Jump, thumbstick, column, status, chat and player list (`FishingLayout.clearOf`,
the layout checker's `MIN_GAP` 16), scale-based (`UDim2.fromScale`), with text never < 12 px.

### 6.10 Text inventory (Russian; all in `StealConfig.Texts` / `DefenceConfig.Texts`)

Rules (D20, DC-14): no display numbers, no «чужой», no gender or case agreement, never shaming.

- **Prompt:** «Украсть» / «{Short} · +$4/с».
- **Thief banner:**
  - «КРАДЁШЬ: {SHORT}», «Не отходи!»;
  - «БЕГИ ЗА ОГРАДУ!», «Не попадись хозяину», «🐕 СОБАКА!»;
  - «ДОБЫЧА!», «{Short} — в твоём садке · {rate}»;
  - «СОРВАЛОСЬ!»; «Подожди секунду» (no reply).
- **Thief hints:**
  - «Зажми «Украсть» у витрины и унеси рыбу за ограду!» (touch), «Держи E у витрины и унеси рыбу за
    ограду!» (keyboard);
  - «Начнёшь красть — твоя защита погаснет»;
  - «Твоя защита снята: ты пошёл на дело!».
- **Cancel reasons** (`Cancel.Text`):
  - released «Ты отпустил кнопку»;
  - far «Ты отошёл от витрины»;
  - died «Ты упал — рыба вернулась домой»;
  - shield «Хозяин включил щит — рыба вернулась домой»;
  - tag «Хозяин тебя поймал!»;
  - deadline / early «Не получилось — попробуй ещё раз»;
  - timeout «Слишком долго — рыба уплыла домой»;
  - speed «Слишком быстро — рыба выскользнула»;
  - victim «Хозяин ушёл из игры»;
  - full «Садок полон — эта рыба слабее твоих»;
  - busy «Сейчас нельзя».
- **Denied:** the table in §4.3 (incl. `tagged`, `newbie`, `rest`, `weak`, `new`). Home guard «Сначала
  унеси рыбу за ограду!».
- **Victim alert:**
  - «ВОР В САДКЕ!», «{Name} крадёт: {Short}»;
  - «ВОР УБЕГАЕТ!», «{Name} уносит: {Short} — жми ЩИТ!» / «{Name} уносит: {Short}»;
  - «Пока крадёшь сам, щит не включить»;
  - buttons «ЩИТ», «⏳ {t}», «ДОМОЙ»; compact «ВОР! {Short}».
- **Victim results:**
  - lost (theft kind, Big): «Украдено: {Short} ({Name})» + «Садок отдыхает {t} — никто не украдёт»;
  - saved:
    - tag «Вор пойман — рыба спасена!»;
    - shield «Щит спас рыбу!»;
    - thief failed «Кража сорвалась — рыба дома»;
    - thief left «Вор ушёл — рыба вернулась!»; the tank full and the returned fish the weakest
      «Вор ушёл — садок полон, рыба продана: {price}» (`Result.LeftSold`, A1-01);
  - void «Рыба вернулась к хозяину».
- **Tips** (one per loss, DC-14):
  - the shield was ready and unused: «Совет: жми 🛡️ ЩИТ, как только увидишь «ВОР В САДКЕ!» — он
    бесплатный»;
  - otherwise the cheapest defence not owned: «Совет: замок — вору держать дольше ($1 500)», «Совет:
    сигнализация предупредит заранее ($2 500)», «Совет: собака замедлит вора ($6 000)».
- **Intruder:** «{Name} у тебя во дворе!».
- **Shield and protections:**
  - «Щит включён на 1:00», «Щит погас», «Щит снова готов!»;
  - «Защита новичка {t} 🛡️ — лови спокойно!» (newbie), «Твой садок под защитой {t}» (join);
  - «Скоро воры смогут красть. Увидишь «ВОР В САДКЕ!» — жми 🛡️ ЩИТ!» (ending);
  - «Ты и так под защитой — ещё {t}», «Щит перезаряжается — ещё {t}», «Сначала закончи кражу».
- **Sheet:**
  - «ЗАЩИТА», «ЩИТ», «СОБАКА», «СИГНАЛИЗАЦИЯ» / «СИГНАЛКА», «ЗАМОК»;
  - effect lines (§6.6);
  - «ВКЛЮЧИТЬ», «КУПИТЬ?», «КУПЛЕНО», «ТЫ ПОД ЗАЩИТОЙ», «Сильнее замки — скоро в магазине», «Замок
    ур. {n}»;
  - «Собака охраняет твой двор!», «Сигнализация включена!», «Замок: вору держать {s} с».
- **Purchase denied:** «Уже куплено», «Замок уже лучший», «Не хватает: нужно {$}», «Сильнее замки — скоро
  в магазине».
- **World:** «КРАДУТ!», «УНОСЯТ!», «УКРАДЕНО!», «ВОР!», «ГАВ!», «🥷 {Short} {$}», «🚨 КРАДУТ!», «🛡️ {t}»,
  «🔐{n} · 🐕 · 🚨».
- **Tank panel:** «КРАДУТ!», «В ПУТИ…»; Denied locked «Её сейчас крадут!», escrow «Рыба ещё в пути — пара
  секунд!».
- **Studio** (Output, not a GUI): «[DefenceService] Studio: защита сокращена до 10 с
  (DefenceConfig.Debug.StudioProtect)».

A `stage4_rules` case fills every string with the longest name, fish and price and checks it with
`UiFx.textWidth`:

- toasts ≤ 300 px at 12 px;
- banner and plate titles fit their box at their tier on phone_small;
- card names fit at the Small tier (picks «СИГНАЛКА» if needed).

---

## 7. Tests (RbxSim) and renders

Runner: `/opt/tools/l11/lune run tools/run_tests.luau [filter]`. Every file < 600 s, nearly every test
ends with `AssertNoErrors({ warnings = true })`. Money < 2^24 in tests (float32 attributes). Times through
`AttrTime`. The Stage 3 helpers apply: `boot(t, patches)`, `restart`, the gap assertion, the ledger, the
`_debugSizes` zeros.

### 7.0 Sim additions (Wave 0; `tools/sim` + README + `sim_selftest_players`)

| # | change | the bug class it exposes |
|---|---|---|
| S1 | holds read `Enabled` **and `MaxActivationDistance`** through the **holding client's overlay** (`input.luau:330`) | a client-hidden prompt still stealable in tests (BE-14, BE-31) |
| S2 | a server write of a property **drops that key from every client overlay** and fires the change there (`proxy.luau:569`) | Roblox overwrites a local value on a server write: proves the filter must use a property the server never writes |
| S3 | `sim:FirePromptEvent(p, prompt, kind)` with `kind` = "HoldBegan" / "HoldEnded" / "Triggered" / "TriggerEnded": from the client context, to the server only, no validation (the exploit), call order kept (BE-29; replaces rev. 1's `TriggerPrompt`) | `fireproximityprompt`, a HoldBegan from 200 studs, HoldEnded before Triggered |
| S4 | `DataStore:FailKey(key, count, message?, ops?)` and `DataStore:SetKeyLatency(key, seconds)` | one side's save failing or slow while the other's succeeds |
| S4b | `FailKey(…, { after = true })`: the write lands, then the call errors (BE-34) | the ambiguous commit: one fish lost, never two |
| S5 | (static test, no sim change) every `Instance.new("ProximityPrompt")` in `src` sets `RequiresLineOfSight = false` | LOS default true in Roblox, ignored by the sim |
| S6 | `sim:Shutdown({ order = "playersFirst" })`: `PlayerRemoving` for everyone before the BindToClose callbacks (BE-33; today BindToClose always runs first, `init.luau:666-688`) | F9' and the `AmendLeaving` path |
| S7 | `Sim.new({ removingOrder = "reverse" })`: `Players.PlayerRemoving` handlers in reverse connection order (BE-32; today FIFO, `signal.luau:190-205`) | handler-order assumptions in F2–F9 |
| S8 | the four prompt events go through the client→server `remoteLatency` like RemoteEvents (BE-30; today they arrive in the same frame, `input.luau:378-385`) | `Tolerance`, `Grace`, `Deadline` never exercised under latency |

Not needed: `PromptShown/Hidden`, `Exclusivity`, LOS emulation (the default prompt style; checked in
Studio). Note: RbxSim answers `RunService:IsStudio() == true`, so the stage 4 kit boots with
`DefenceConfig.Debug.StudioProtect = false` (§2.4).

### 7.1 `tests/stage4_rules.test.luau` (pure; Wave 0)

- **StealRules:**
  - `HoldTime` 0..5 and above the max;
  - `InPlot` / `ExitMargin` corners;
  - `NearestExit` (gate, side, back);
  - `DogWaypoint` (in front of the arcades vs in the court);
  - `DogStep` (speed, overshoot, leash clamp);
  - `ProtectState` (all five kinds, the last-ending wins);
  - `CanStealView` reasons;
  - `FormatClock` (0:42, 6:12);
  - `NextLock` with `SaleMax`.
- **TheftChecks:** every row of §4.3 headless over a view struct (17 rows, the order, the `Client`
  tags, `Quiet` for a repeat).
- **CarryGuard:** the §4.4 table with `dt` steps: honest at 13.6 and 6.8; `WalkSpeed 16` under the dog →
  "speed" within 3 s; a 2× hack; a 1.2 s and a 1.5 s stall + catch-up → "ok"; a 30-stud hop → "speed";
  `CanCredit()` false right after an overdraft.
- **PlayerData:** `Stats.Stolen/Lost` template, reconcile and serialize; `Upgrades` typed keys (bad
  Dog/Alarm types removed, a newer server's number ≥ 0 kept, a future key kept; `PlayerData.Owned`); `LockLevel` 9 kept; **Origin dedupe**; an Origin with an
  11-digit UserId and a 12-character uid survives (`OriginMax` 32).
- **Config invariants:**
  - lock holds strictly increase, prices strictly increase, `Hold ≤ 10`, `1 ≤ SaleMax ≤ #Levels`;
  - `Prompt.MaxDistance + Slack < 10` (the back-wall reach) and `Prompt.MaxDistance ≤ 6` (at the exact
    midpoint between two displays, 5.5 studs, both prompts are in range and `OnePerButton` picks one;
    one step towards a cabinet decides);
  - `Carry.Timeout > the longest exit / (16 × 0.85 × 0.5)`;
  - `Carry.Speed.Rate × 16 × 0.85 × 0.5 < 16 − 1` (a `WalkSpeed 16` cheat under the dog drains the
    budget) and `16 × 0.85 × 1.5 < Teleport < CapSeconds × 16 × 0.85 + CapSlack` (a 1.5 s stall is no
    teleport, and a teleport is more than the cap);
  - `Shield.Duration < Shield.Cooldown`, `StackBelow ≤ Duration`, `JoinProtectFirst ≥ JoinProtect >
    QuickRejoinProtect`;
  - `LampPeriod ≥ 1/3` (≤ 3 Hz);
  - `Dog.RunSpeed > 16 × Carry.SpeedFactor`;
  - **fairness (DC-21):** `VictimMax ≤ 3`; `FreshCatch ≥ max(UIConfig.CatchCardTime) + 1`; the dog's
    arrival from `Dog.Rest` (with `AlertDelay`) to every slot unlocked at the start is < `Lock.BaseHold`;
    `FailCooldown` strictly increases and `TagCooldown > FailCooldown[1]`; `AlertCoalesce ≥ 2 ×
    (BaseHold + FailCooldown[1])`.
- **Text widths** (§6.10). **Static S5.** **Service API presence** (StealService, DefenceService incl.
  `SetStealProbe`, the new TankService and DataService functions incl. `AmendLeaving` and
  `SlotChanged`, `FishingController.HurryCard`). **The server require graph has no cycle** (BE-8).

### 7.2 `tests/stage4_theft.test.luau` (server, real place; light clients only where a hold needs one; Wave 1 A)

- **State machine:**
  - hold → carry → exit → credit: both tanks, slot attributes in order (`StealPhase` last), `Event
    stolen|<id>`, `Origin`, the Age kept (± 1 s), stats, cooldown, the victim's `after`;
  - `Carry.Enabled = false` → credit at the hold end (the only test of that mode; DC-19).
- **Every cancel reason:**
  - released; far (`Teleport` 9 studs → `HoldEnded` classified `far`, not `released`; BE-13); died
    (`KillCharacter` → `died`); thief leaves; victim leaves;
  - shield in the hold; **shield in the carry → Returned `shield`, the fish back in its display, thief
    speed 16, no fail wait** (DC-01);
  - tag (owner `Teleport` to 5 studs) → the fail step + `tagged` 20 s on that base, another base allowed
    after the fail step;
  - deadline (the test raises the prompt's server `HoldDuration` to 10 right after HoldBegan, so the sim
    never triggers; the server captured 3 and cancels at 4.5); early (`FirePromptEvent Triggered` at 1 s
    after HoldBegan) → 30 s; carry timeout;
  - speed, with `Kit.drive` (BE-9, BE-35): (a) 16 st/s under the dog → returned within 3 s; (b) an
    honest walk with the dog plus a 1.2 s freeze and the catch-up → **not** returned; (c) a 30-stud hop
    → returned; (d) a teleport straight out of the plot → returned, never credited;
  - `StealFish` nil at the exit (patch the thief's tank full of stronger fish mid-carry).
- **Hold-end ordering:** `HoldEnded` delivered just before `Triggered` (`FirePromptEvent` in that order)
  → still credited (the `Grace` window).
- **Every Denied reason** of §4.3 (17 rows), with a hold or `ignoreDistance` / `ignoreEnabled`, incl.:
  `tagged`; `newbie`; `rest`; `weak` (thief $100/s vs victim $20/s → refused; $40/s → allowed; DC-09);
  `new` (a catch → refused → allowed at 30 s; DC-08); the same reason twice within 2 s → the 2nd is
  `Quiet`; `Denied` names the slot (BE-16); a repeated HoldBegan on the held prompt → ignored, the theft
  goes on (BE-17).
- **Lock:** level 1 → the 12 prompts `HoldDuration 4`; a 3 s hold does not trigger; 4 s works; a purchase
  mid-hold leaves the held prompt's `HoldDuration` alone and the theft **credits** (BE-18).
- **Speed:** carry 13.6, dog 6.8, restored 16 after every end, after death (a new character) and on leave
  (no leftover); **the dog bites at the exit → credit → `WalkSpeed == 16` at +0.1 s and still at +5 s,
  `Slowed == nil`**; a Dog key expiring mid-carry → 13.6 within `SlowLinger + 0.1` (BE-10); `MinFactor`.
- **Client hiding** (S1, BE-14): on the owner's client the server toggles `Enabled` false/true 20 times in
  random frames (theft begin and end, shield, catch); in every frame `MaxActivationDistance == 0` there
  and `HoldPrompt(owner, …)` fails with "out of range".
- **Home guard:** carry → denied, no cooldown spent; own live theft → lands facing +Z.
- **Exploits:**
  - `FirePromptEvent Triggered` with no hold → nothing; a HoldBegan from 200 studs → `far`;
  - 100 HoldBegan in one frame → ≤ Burst records, ≤ the Denied cadence;
  - a hold on the own base with `ignoreEnabled` → nothing;
  - two thieves on one base; one thief on two prompts (the sim lets him) → only one theft;
  - a HoldBegan fired after `RemovePlayer` → `_debugSizes().Buckets == 0` (BE-20).
- **Griefing** (DC-10, BE-19): start/cancel ×5 in 30 s → one loud alert and waits of 3 / 10 / 30 s; 10
  release loops in 60 s → at most 3 loud victim toasts; holds under 1 s → `Saved` with `Quiet`.
- **Victim cap** (DC-06): 4 thieves against 1 victim for 10 virtual minutes → exactly 2 losses, then the
  `rest` kind until the older loss is 600 s old; a steal by the victim clears `rest` and his losses.
- **Unmount** (BE-5): the victim leaves mid-carry → no `StealBy`/`StealEnd`/`StealPhase`/`Escrow`/
  `FreshUntil` on any of the 12 slots of the freed base; a new owner mounts → no theft visuals.
- **Leaks:** connections back to baseline after both leave; `_debugSizes` zero after
  `Advance(VictimWindow)` **with no further writes** (pruned inside `_debugSizes`; BE-26); the watcher
  thread ends (no loop while idle).
- **BindToClose** during hold and carry → the fish home, once.

### 7.3 `tests/stage4_data.test.luau` (headless where possible; `StealFish` driven directly; Wave 1 A)

- **F5** escrow: the thief's autosave during the escrow lacks the fish (`Peek`), then has it after the
  victim's commit; the thief's income excludes it until then; the slot `Escrow` attribute set and
  cleared.
- **Inline save** (BE-3): a test-only `MoneyChanged` handler calls `SaveSoon(thief)` synchronously with
  `DataStore:SetLatency(0)` and a forced "replaced" → `Peek(thief)` never holds the loot before the
  victim's commit.
- **Memory mode** → cleared at once.
- **F6** victim leaves mid-escrow → thief commits with the fish.
- **F7** `FailKey(victim)` until the leave window passes / `Poke` a foreign Session (lost lock) → void on
  the thief; `restart` → the victim has the fish, the thief does not. **F7 lost reply** (S4b `after =
  true` on the victim's final save) → at most one copy across all keys (the documented loss).
- **F8a** thief leaves mid-escrow (`SetKeyLatency(victim, 4)`) → the fish is back in the victim's tank
  (original uid), the thief's final save lacks it; `restart` → exactly one copy, the victim's.
- **F8b** (BE-1): the victim leaves, the thief leaves 1 s later, `SetKeyLatency(victim, 4)`, `restart` →
  the fish is in the victim's key exactly once. **F8c** documented: the victim's final snapshot already
  taken → zero copies, never two.
- **F9** `Shutdown()` with 2 escrows → each fish exactly once, in the victim's key. **F9'**
  `Shutdown({ order = "playersFirst" })` with 2 escrows and the victims removed first → the same.
- **F10** documented: a "crash" (`restart` from a snapshot taken between the commits) → zero copies, never
  two.
- **Seq collision** (BE-2): the victim rejoins the same server during an escrow (the old record's entry
  Seq 3, the new record commits seq 3) → exactly one copy after `restart`.
- **F14** (BE-4): the thief leaves and `Shutdown` runs in the same frame → one row in the victim's tank,
  no Sanitize issue on reload, the stats taken back. `Released` fires once per record (`recover` after
  `process`).
- **Both handler orders** (S7): F2–F9 run with `removingOrder = "reverse"` too.
- **Chaos:** `SetFailRate(0.3)`, 4 players stealing from each other in a loop for 10 virtual minutes,
  leaves and rejoins, then `Shutdown` + `restart` (once per handler order) →
  - no `Origin` twice across all keys;
  - no fish both in its victim's key (by uid) and as an `Origin` elsewhere;
  - fish total ≤ initial + catches;
  - the ledger holds everywhere;
  - the gap respected per key.
- **Sanitize** dedupe on load.

### 7.4 `tests/stage4_defence.test.luau` (server; Wave 1 A)

- **Shield:**
  - activate → `ProtectUntil` 60 s, the client filter hides the prompts, a live hold cancelled, **a
    live carry returned**;
  - refused while ≥ 60 s of protection remain (no cooldown spent); **accepted with 30 s of `after` left
    → `ProtectUntil = now + 60`** (DC-03); refused while stealing (through the probe); on cooldown;
  - ready again at 240 s;
  - persisted: leave → `restart(+100 s)` → rejoin → still 140 s to ready.
- **Join protection** (DC-07, BE-25): a fresh save → 300 s `newbie`; a second session → 90 s; a rejoin
  within 5 min → 20 s (by `LastOnline`, and in Memory mode by `leftAt`); a player queued 10 s behind a
  full server → 90 s at mount, not 20; starting a steal ends it (and a manual shield, with no refund);
  the `EndingWarn` toast at 15 s left.
- **After / rest:** 90 s after a loss; the 2nd loss within 600 s → `rest` until the older loss + 600; a
  later session re-applies a running rest.
- **Studio knob** (DC-20): `Debug.StudioProtect = 10` with `IsStudio` → join/newbie/after/rest 10 s, the
  shield still 60 s, one `print`, no warning; `false` → the real timers.
- **Purchases:**
  - Dog/Alarm/Lock (level 1): money down by the price, `Stats.Spent`, the ledger, `SaveSoon`, attributes;
  - the dog shown on the base at `Dog.Rest` (parts T 0, kennel collides) and hidden, with the template
    pivot back, on unmount;
  - Lock at `SaleMax` → `soon`; every Denied reason; 50 buys in a frame → one purchase per item.
- **Dog brain:** from `Dog.Rest` the dog reaches the thief at each of slots 1–6 before `BaseHold`
  (DC-05); it slows him within 5 only while the theft is live, lingers 1 s, is leashed at the fence,
  returns and never bites in `Return`; `DogPos` writes ≤ 5 Hz and none while standing; nothing ticks
  when asleep.
- **Alarm intruder:** a visitor in the plot → one `Intruder` per 45 s, none without the alarm, none while
  protected, the loop stops when no alarmed base is mounted.
- **Unmount reset** (BE-27): owner A leaves mid-theft, owner B mounts the same base → base, slot, dog and
  prompt state equal a fresh base, compared against the `stage1_bases` pin.
- **No cycle:** DefenceService works with a stub StealService (the default probe).

### 7.5 `tests/stage4_world.test.luau` (client with faked attributes; Wave 1 B)

- **Displays:** lift/struggle on `StealPhase = hold`; destroyed on carry; rebuilt on return; «КРАДУТ!» /
  «УНОСЯТ!» / «УКРАДЕНО!» words appear and are cleaned; stolen event FX; ≤ 2 emitters.
- **Lamp:** a tween `LampDim` ↔ `LampOn` while `AlarmState` (luminance contrast ≥ 4), the colour and
  material restored exactly after.
- **Siren** (two SpotLights pitched down `Siren.Pitch`, a Beam along each, + beep) **and Highlight** only
  with `HasAlarm`; the Highlight destroyed on end; the bell and the lanterns untouched (P2).
- **Dome:** shield only (join protection → no dome; shield → a dome); in range only; ≤ 2 on touch;
  inside transparency for the camera **or the own character** (camera outside), in between in the
  `Near` band; fades.
- **Tank sign** lines «🛡️ 0:42» and «🔐1 · 🐕 · 🚨» on top (the sign grows up); the flag label «🛡️ 4:12»
  over the owner sign for any kind.
- **Pier word** «🚨 КРАДУТ!» red during the bite, hidden under `CounterHold`.
- **Dog:** asleep on the paving with a still «💤»; follows `DogPos` on the ground (the arcade deck); the
  RenderStepped connection exists only while awake; «ГАВ!» on its body; back to the rest pose asleep.
- **StolenFish** nameplate and life; «ВОР!» and the nameplate fade under the HUD (`TrackWord`).
- **Idle:** no RenderStepped/Heartbeat connections, `activeJobs() == 0`, everything gone after the base
  is released.

### 7.6 `tests/stage4_hud_thief.test.luau` (Wave 2 C) and `tests/stage4_hud_alert.test.luau`, `tests/stage4_panel.test.luau` (Wave 2 D)

Client tests stub the server services with `return {}` and fake `StealEvent` / `DefenceEvent`, the
Player, base and slot attributes (Stage 3 pattern; `sim:ServerEventsFor(p, "ShieldActivate")`).

- **Thief (C):**
  - prompts hidden locally (`MaxActivationDistance 0`) on the own base and still hidden through server
    `Enabled` writes (S1/S2);
  - hidden on weaker fish when full, during cooldown, while carrying, under protection, on a live theft
    base, on fresh and escrowed fish, on a much weaker victim;
  - the banner states on 5 screens (no overlaps, ≥ 16 px, scale-based);
  - Denied → `InputHoldEnd` on the named slot + hint; `Quiet` → no text; no reply within 1.0 s →
    `InputHoldEnd` + «Подожди секунду»;
  - done → «ДОБЫЧА!», the flight, `TankIncoming` holds the arrival;
  - fail → reason;
  - the beam to the nearest exit;
  - the FishingController hint yields;
  - «ДОМОЙ» greyed in carry;
  - **`FishingController.HurryCard()`** (C owns FishingController; DC-02): a Mythic card up → closed
    within 1 s, the flight and the «САДОК» arrival still play; a card in its Epic+ delay closes as soon as
    it settles;
  - idle jobs 0 after.
- **Alert (D):**
  - the full plate idle and during Bite/Reeling;
  - Compact on phones when it hits `fisherBox`;
  - an alert during a catch card → AlertController calls `HurryCard` (a spy) and the plate shows once
    the card is closed and `CounterHold` cleared;
  - ЩИТ from the plate and from the «ЩИТ!» column button during the minigame, **in the hold and in the
    carry**, fires `ShieldActivate` **without** breaking the minigame (its ActionButton still answers);
  - the ЩИТ button ≥ 56 px tall and ≥ 35 % of the plate on 5 screens; Slate «⏳» on cooldown; no
    buttons while stealing (DC-04);
  - coalesced `Quiet` alerts: no pings, no shake;
  - the trophy chip left of the column on phones;
  - the ShieldChip on 5 screens (fits, 16 px), the newbie/rest copy, the pulse in the last 10 s, gone at
    0, the `EndingWarn` toast;
  - the «ЗАЩИТА» badge once when the first defence becomes affordable;
  - the edge pulse ≤ 0.35 opacity.
- **Panel (D, sheet):**
  - names, 4 cards, states (the Lock card as a one-time buy, then «КУПЛЕНО» + «Сильнее замки — скоро в
    магазине»);
  - two-tap buy (0.15 s ignored, 0.5 s fires);
  - `Bought` → `Spend` juice + stamp;
  - `Denied` → wiggle;
  - one sheet at a time with the tank panel (open A, open B, close B → `ВЗЯТЬ` and `Toasts.ZIndex`
    restored);
  - phone_small scroll;
  - fill ≤ 2.5×;
  - tank-panel Sell labels «КРАДУТ!» / «В ПУТИ…» from the slot attributes.

### 7.7 `tests/stage4_e2e.test.luau` + `stage4_e2e_defence.test.luau` (real server + 2–3 clients; Wave 3 E)

New Kit helpers in `tests/stage4_kit.luau` (Wave 0):

- `Kit.boot(t, patches)`: the Stage 3 boot with `DefenceConfig.Debug.StudioProtect = false`;
- `Kit.seed(id, { tank, money, lock, upgrades, saveCount })` via `pokeSave`;
- `Kit.stealPrompt(sim, owner, slot)`;
- `Kit.steal(t, sim, thief, owner, slot, { cancel = "release" | "walk" | "die" | "tag" | "leave" | "shield", exit = "gate" | "side" })`;
- `Kit.drive(p, to, speed)`: moves the HRP every frame at a chosen speed, whatever the WalkSpeed (RbxSim
  cannot speed-hack otherwise; BE-35);
- `Kit.theftEvents(sim, p, kind)`;
- `Kit.exitPoint(base, kind)`.

1. **Happy path (phone thief, tablet victim, desktop bystander):**
   - the victim has 4 fish including a Legendary aged 200 s; the thief has 3 weaker;
   - walk in, hold 3 s → the victim's plate, the bystander's lamp tween, the thief's banner;
   - carry: `StolenFish`, WalkSpeed 13.6, the red beam;
   - walk out of the gate → «ДОБЫЧА!»; both «САДОК» chips; the victim's chip «🛡️ 1:30»;
   - both saves: the victim's commit before the thief's key has the fish (the DataStore call log);
   - `restart` → exactly one copy, the age kept.
2. **Defence:**
   - the victim taps the «ЩИТ!» column button during the thief's hold → cancelled, the thief «Хозяин
     включил щит — рыба вернулась домой», the dome on the bystander;
   - **the victim taps the plate's ЩИТ during a carry → the fish flies home** (DC-01);
   - the victim taps «ДОМОЙ», lands facing the court, walks to the carrier → tag → the fish home.
3. **Dog + alarm:**
   - the victim buys both from the sheet (money, stamps);
   - the thief enters the plot → «Ника у тебя во дворе!»;
   - hold → the dog runs from the court and arrives during the hold → the thief at 6.8; the exit takes
     ≈ 2×; the Highlight on the bystander.
4. **Lock:** the victim buys the lock → the thief's ring takes 4 s; 3 s fails.
5. **Full thief tank:** stronger fish only → no prompts, a server Denied with `ignoreEnabled`; one weaker
   → «ЗАМЕНА!» + coins.
6. **Rejoin / save:** the thief leaves 1 s after the credit with `SetKeyLatency(victim, 4)` → the fish
   back with the victim (toast) → `restart` → one copy.
7. **Timeline** (DC-21): the victim is in the minigame; the hold starts; he taps the column «ЩИТ!» at
   hold end + 1 s (in the carry) → «Щит спас рыбу!», the minigame still answers, the thief
   «СОРВАЛОСЬ!».
8. **Catch card** (DC-02): the victim lands a Mythic and a hold starts on his base while the card is up
   → the card closes within 1 s, the plate shows, his ЩИТ tap saves the fish.
9. **The happy path with `remoteLatency 0.15`**, the prompt events delayed too (S8).

### 7.8 Existing tests to update

- `stage3_tank`: the `SetLocked` wrapper semantics are unchanged; the new Denied texts.
- `stage3_rules`: the API presence list, the Event kinds (`void`).
- `stage1_bases`: the dog hidden and the pup at its template pivot on a fresh base (with `Dog.Pup`).
- `hud_style` names: DefenceButton, ShieldChip, TheftBar, TheftTitle, TheftAlert, DefencePanel; the
  column with 3 buttons.
- `fishing_ui_style` / `stage3_hud`: the docked catch card under the taller column, the trophy chip on
  phones.
- `compile_limits`: FishingController keeps ≥ 24 spare registers with `HurryCard`.
- `tools/preview/gui_dump.luau`:
  - stub list + StealService, DefenceService;
  - harness `h:steal(phase, data)`, `h:alert(data)`, `h:shield(until, readyAt, kind)` (all five kinds),
    `h:defence({ dog, alarm, lock })`, `h:stealEvent(kind, data)`;
  - the default join: no protection, so the old scenarios do not change.

### 7.9 Renders (5 devices; `gui_render.py --all` clean: layout, ≥ 12 px text, phone fill ≤ 2.5×)

**GUI:**

- thief: `steal_court_hint`, `steal_hold`, `steal_carry` (+ `DogChip`), `steal_done`, `steal_fail`;
- victim: `theft_alert_idle`, `theft_alert_bite` (phones), `theft_alert_compact` (phones, fisherBox),
  `theft_alert_catch` (the card closing → the plate; DC-02), `theft_alert_carry` (ЩИТ in the carry),
  `theft_alert_cooldown` (Slate «⏳»), `theft_alert_while_stealing` (TheftAlert in the column, TheftBar
  in the bottom band; phone_small is the tightest), `theft_lost_toast`, `theft_saved_toast`;
- shield: `shield_chip`, `shield_chip_join`, `shield_chip_rest`, `newbie_protect_ending`;
- defence: `defence_button`, `defence_button_alert` («ЩИТ!»), `defence_panel`, `defence_panel_bought`,
  `defence_buy_confirm`;
- tank panel: `tank_panel_stealing` (the Sell label);
- re-checks: `trophy_chip` (phones, 3 buttons), `catch_*`.

**World** (the world-FX capture or the scratch mock script of `read_world` §9):

- `steal_hold_follow` (the thief camera: lifted fish, «КРАДУТ!»);
- `steal_hold_thief_hud` / `steal_hold_thief_rule`, `steal_carry_thief_hud` / `steal_carry_thief_rule`
  (the thief's own screen with the HUD on, phone, phone_small, tablet, desktop: rev. 2's top TheftBar
  vs the §6.4 rule mocked — the robbed display's band, printed with `gui_render -v`);
- `steal_hold_spawn` («КРАДУТ!» past the arcade lanterns from the owner's spawn);
- `steal_carry_dog` (the fish over the head, the dog, the red beam);
- `alarm_lamp_court`, `alarm_lamp_far` (dark ↔ hot from the lane, the pitched siren beams);
- `alarm_siren_highlight`;
- `shield_dome_gate` (a shield dome; a join-protected base next to it without one), `shield_dome_spawn`
  (the owner on his spawn pad: faint, not a full-screen layer; the Near band; a bubble from afar);
- `dog_court_rest` (the shown dog at its court spot, seen from the gate, and the kennel), `dog_rest_side`
  (its paws on the paving, «💤»);
- `tank_sign_defences` («🔐1 · 🐕 · 🚨» and «🛡️ 0:42»), `tank_sign_gate` (the row on top, clear of the
  fountain statue from the gate and the spawn);
- `flag_label_neighbour` («🛡️ 0:42» over a blue base's owner sign, on the sky);
- `owner_pier_alert` (the phone fishing camera with «🚨 КРАДУТ!», clear of the fisher and the bobber).

---

## 8. Implementation waves (2 agents at a time, isolated git worktrees)

Rules for every agent (as in Stage 3):

- a Russian header on every new script;
- `stylua`, `tools/analyze.sh`, rebuild (`/opt/tools/l11/lune run tools/build.luau`) — Place1.rbxl
  is generated, never edited by hand;
- the full suite green (`compile_limits` ≥ 24 spare, `place_fresh`);
- commit.

The integrator merges, resolves `Place1.rbxl` by rebuilding, and re-runs the suite.

### Wave 0 — Contract (1 agent, before everything)

- **Config:**
  - `Config/StealConfig.luau`, `Config/DefenceConfig.luau` (new, complete, §2.6);
  - `UIConfig` (Guard, ToastKinds `theft/saved/shield`, the `Theft` block);
  - `MapConfig.PartBudget.RuntimeReserve.Theft = 60` (+ asserts);
  - `DataConfig.Limits.OriginMax = 32`;
  - `TankConfig.Texts.Denied.locked/escrow`.
- **Shared:**
  - `Shared/StealRules.luau`, `Shared/TheftChecks.luau` (complete, pure);
  - `RemoteNames` (4 remotes + the header protocol of §4.10, slot steal attributes incl. `Escrow` and
    `FreshUntil`, the `stolen|<id>` / `void` kinds).
- **Server libs:**
  - `Lib/PlayerData` (§3.1, complete);
  - `Lib/Speed` (with its own expiry), `Lib/Bucket` (with the `Parent` guard), `Lib/CarryGuard`
    (complete, small, pure where possible);
  - `Lib/DogBrain` (pure steps complete, attribute writes stubbed);
  - `Lib/HeldRig` (extracted; FishingService switched to it + `DropHeldFish`; stage2 suites green).
- **Server stubs:**
  - `StealService`, `DefenceService` (headers + API signatures incl. `SetStealProbe`, no behaviour);
  - `DataService.Released` (once per record), `OnClose`, `AmendLeaving` + `FinalTaken` (complete: small,
    contract; A's F8b/F9' tests exercise them);
  - `BaseService:SetHomeGuard` (complete);
  - `Main` ORDER.
- **Client:**
  - stubs `TheftController`, `AlertController`, `DefenceController`, `TheftWorldController` +
    `ClientMain` ORDER;
  - `NotifyController.Reserve(key, px)` (complete); no `Point` (DC-16);
  - `HudController.HomeAlert` (stub); `FishingController.HurryCard()` (a no-op stub: C fills it, D calls
    it).
- **GUI skeleton** (all hidden):
  - `gui/Hud.luau` DefenceButton + ShieldChip;
  - new `gui/Steal.luau` (TheftBar, TheftTitle), `gui/Alert.luau` (TheftAlert with the big-ЩИТ row +
    Compact), `gui/Defence.luau` (DefencePanel + 4 cards on the sheet shell, no pips);
  - `Gui.luau` (calls + the header grid: the 3rd column slot now used, a note for Stage 5).
- **Builder:** `Dog.Pup` sub-model (BaseTemplate) + the `tools/builder/DESIGN.md` names.
- **Sim:** S1–S4b, S6–S8 + README + selftests (S5 is a static test).
- **Preview:** gui_dump stubs + harness helpers; `checks.py` `CONTAINERS` / `SHEETS` + the new sheet.
- **Tests:** `tests/stage4_rules.test.luau` (incl. TheftChecks, CarryGuard and the fairness
  invariants), `tests/stage4_kit.luau` (incl. `Kit.boot` with the Studio knob off and `Kit.drive`),
  `tests/stage4_kit_selftest.test.luau` (the kit against the merged sim) and
  `tests/stage4_data_hooks.test.luau` (W0 review: `Released`, `AmendLeaving` / `FinalTaken` incl. a
  failed final attempt, `OnClose` in both shutdown orders, `SetHomeGuard` with a CFrame).

**Accept:** the suite is green; every name of §6.1 exists in the place; renders show no visible change
except the hidden widgets; `compile_limits` is fine.

### Wave 1 — A: server core ‖ B: world

**A owns:**

- `StealService`, `DefenceService`, `TankService` (§4.5, incl. `SlotChanged`, the slot attributes and the
  unmount cleanup), `DataService` (header lines), `BaseService` (guard use), `Lib/DogBrain` (the
  attribute writes), `Main`;
- the fairness rules (`after`/`rest`, newbie, fresh, weak, tag and fail waits) and the time-bounded maps;
- tests `stage4_theft`, `stage4_data`, `stage4_defence`;
- the updates of `stage3_tank`, `stage3_rules`, `stage1_bases`.

A accepts when:

- §7.2–7.4 pass, `stage4_data` in both `PlayerRemoving` handler orders;
- every F1–F14 row is covered;
- the Stage 1–3 suites are green;
- there are no warnings in normal flows;
- the watcher and the intruder loop stop when idle;
- `_debugSizes` are zero after leave (and after `Advance` with no writes).

**B owns:**

- `TankWorldController`, `TankDisplay` (§5.2, the sign defences line and the pier word of §5.3;
  `hudRects()` also measures `ShieldChip`, `TheftBar` and `TheftAlert`, so world words fade under them),
  `TheftWorldController` (§5.3–5.4: lamp, siren, Highlight, the shield-only dome, the flag label, the
  dog render from its rest pivot, the carried fish), `FisherAnimController` (the carry pose, if the
  budget allows);
- `tests/stage4_world`;
- the world renders of §7.9;
- the `DESIGN.md` runtime contract (the slot steal channel, `StealPhase` last).

B works against the §4.11 attributes, faked in tests. B accepts when:

- §7.5 passes;
- the renders read: the lifted fish, the arc out of the front glass under the ceiling, the lamp and the
  siren, the dome is not a full-screen tint, the dog in the court and its chase, the pier word clear of
  the fisher;
- nothing runs per frame while idle;
- the part budget holds.

### Wave 2 — C: thief UI ‖ D: victim + defence UI

**C owns:**

- `TheftController` (the `MaxActivationDistance` prompt filter, the banner, `NoReply`), `gui/Steal.luau`;
- `FishingController` (inside existing functions only: the hint yield, and `ShieldChip` +
  `TheftBar` / `TheftAlert` added to `statusBoxes()` / `dockBand()` the way `FlagSocket` is; plus the
  body of `HurryCard`, DC-02);
- `FishingFxController` (`boxes("Status")` includes `ShieldChip`; inside the existing function);
- `TankButtonController` (`TankIncoming`, the victim's Berry flash on `Lost`);
- `tests/stage4_hud_thief`;
- the thief scenarios and renders.

C accepts when:

- §7.6 thief passes;
- hold → carry → done/fail reads on all devices;
- prompts stay hidden through server writes (S1/S2);
- `HurryCard` closes a card through its normal path;
- no frame jobs after.

**D owns:**

- `AlertController`, `DefenceController`, `gui/Alert.luau`, `gui/Defence.luau`, `gui/Hud.luau` (the
  button and chip looks);
- `HudController` (`HomeAlert`, Home locked in carry, the intro pop-in order);
- `NotifyController` (the trophy chip on phones), `Controllers/Sheet` (one at a time),
  `TankPanelController` / `TankCards` (the two Sell labels of §6.7), `MoneyController.Spend`;
- `checks.py`;
- `tests/stage4_hud_alert`, `tests/stage4_panel`;
- the updates of `hud_style`, `fishing_ui_style`, `stage3_hud`;
- the victim/defence scenarios and renders.

D accepts when:

- §7.6 alert/panel passes;
- the one-tap shield works during the minigame, in the hold and the carry;
- the ЩИТ button meets its size rule on all 5 screens;
- the plate never intersects `fisherBox` on phones;
- `--all` is clean.

C and D share no file. Both use what Wave 0 fixed: the widget names, `NotifyController.Reserve`,
`FishingController.HurryCard`, the HUD attributes `Stealing`, `AlertPhase` and `TankIncoming`, and
`MoneyController.Celebrate` (Stage 3).

### Wave 3 — E: integration ‖ critics, then a fix round

**E owns:**

- `tests/stage4_e2e*` (incl. the timeline and catch-card cases);
- README: the Stage 4 row ✅, «Как проверить Этап 4» (§10, the carry rule in its first line), the
  defence and fairness numbers in the config list, the Studio knob;
- STYLE.md §3 / §6.5 (the new widgets, the Guard token, the alert layers rule, "the alert outranks the
  catch card");
- `gui_render --all`;
- the perf/budget audit (the part peak, connections, the watcher idle, `Highlight` count, domes on
  phones).

**Critics, 3 lenses:**

1. kid-on-phone UX and fairness (the loop of §1, the renders, the copy, griefing paths, the D21 rules
   in play);
2. data safety and exploits (§3, §4.3–4.10, races, leaks, both handler orders);
3. art (world + GUI renders vs the reference).

Findings → one fix wave (≤ 2 agents, by the ownership above) → the final full suite, `Place1.rbxl`,
the RU notes.

---
## 9. Risks and open questions (each with the default, so nobody blocks)

| # | risk / question | default |
|---|---|---|
| R1 | The user meant "the fish is stolen at the end of the hold" (spec-literal). | Model B (D1). `StealConfig.Carry.Enabled = false` switches to model A; that mode keeps only its server path and one test (DC-19). The README's first line says the rule (DC-22). |
| R2 | Tanks are full after ≈ 1:41, so "steal up, not down" (D4) limits targets. | Intended: thieves aim at better fish, the poor are safe, there is no money dupe. The banner names the reason, and weaker fish show no prompt. |
| R3 | The shield now recalls a fish that is being carried (DC-01); a thief may feel robbed of a run. | Keep: the shield is one per 240 s and visible (the dome), baiting it with a feint is a real tactic, and the thief gets no wait for it. Without it the free defence had a ≈ 2.5 s window and failed a fishing kid. |
| R4 | The lock overlaps the Stage 5 item «Лучший замок». | Stage 4 sells level 1 only (`Lock.SaleMax = 1`, DC-11); levels 2–5 are in config and work at runtime. `SaleMax = 5` sells all five in one line if the user prefers. |
| R5 | Sim fidelity: line of sight, Exclusivity, `InputHoldEnd` on a stock hold, the overlay overwrite, handler orders. | S1–S8 cover what can be emulated (incl. both `PlayerRemoving` orders and a players-first shutdown). The README's Studio checklist (§10) covers the rest. |
| R6 | One fish can be lost (never duplicated): a hard crash inside the thief's key gap (F10), a both-leave race after the victim's final snapshot (F8c, ≈ one request), a lost write reply (F7). | Accepted and documented. P2: a write token in every save closes the F7 case (BE-6). |
| R7 | The logical dog may clip decor on its straight runs (the run to slot 5 grazes the big tank's front-west corner). | One waypoint for a dog in front of the arcades. The pup never collides. Accept the rest. |
| R8 | A teleport-in exploit saves walking time. | Not detected at the start (the server-timed hold, the reach check, and the carry budget on the way out cover the gain). P2: a suspicion counter on MarketService's 1 Hz sample (BE-12). |
| R9 | Griefing by start/cancel spam. | One loud alert per (thief, victim) per 30 s, fail waits 3 / 10 / 30 s (`early` 30 at once), the tag wait 20 s, quiet saves under 1 s, the start bucket, the victim cap. |
| R10 | The DisplayName in the victim's toast. | Shown only to the victim (it is public in the player list anyway); no server broadcast. |
| R11 | Friends or an alt farming protection: without the pair limit, an alt can rob his main twice to give him 10 min of `rest`. | Accept: it creates no money, it costs the main two fish (they go to the alt), and the rest ends the moment the main steals. P2 if seen: no `after`/`rest` for a loot weaker than the victim's weakest active fish. |
| R12 | The 3rd column button lowers the docked catch card's room on phones. | Re-render the `catch_*` scenarios (D); the card floors follow the visible stack automatically (Stage 3 §6.3). |
| R13 | ForceField material looks differ by device and the renderer cannot draw it. | Studio check; the transparency numbers live in config. Only the shield gets a dome now (≤ 2 on phones). |
| R14 | `FisherAnimController` register budget for the carry pose. | P2 if `compile_limits` objects. |
| R15 | A thief on another base's pier (the plot excludes the pier) after the exit. | Fine: the credit is at the victim's plot edge; the fish lands in his own tank wherever he is. |
| R16 | The owner standing in his own court. | Holds within 6 studs of the owner are refused; elsewhere in the court the owner must tag. No "owner at home locks the base" rule (GaG2), so that kids are not pressured to stand guard. |
| R17 | Highlights rendered at once. | ≤ one per active thief (≤ 4 with 8 players); destroyed on end. |
| R18 | Stats `Stolen/Lost` are not shown anywhere in Stage 4. | Saved for Stage 5 (a profile or leaderstat); no UI now. |
| R19 | `VictimMax = 2` may leave thieves idle on a small server. | Default 2 (the critic's simulation); `VictimMax = 3` if playtests show idle thieves. The knob stays in config. |
| R20 | `RichRatio` may leave a veteran with no target on a server of newcomers. | Intended (find a rival your size; newbies can still rob him, and stealing back works once the gap closes). `RichRatio = 0` turns it off. |
| R21 | In Memory mode (a DataStore outage) `SaveCount` stays 0, so every join gets the 5-minute newbie protection. | Acceptable in a degraded mode; `leftAt` still makes a rejoin to the same server quick (20 s). |
| R22 | The Studio knob shortening protections where it should not. | Live servers are never Studio. The sim reports Studio, so the stage 4 kit boots with the knob off and only its own test turns it on. |
| R23 | `ShieldUntil` / `ShieldReadyAt` are public attributes (BE-24). | Keep public (genre-normal; a cheat client gains timing only); no UI shows another player's shield readiness. |

**Questions for the user** (`critique_design.md` §7; each has its default, so nobody blocks):

1. Carry or the literal spec? Default: carry (model B) + the README's one-line rule.
2. Should friends be safe from each other? Default: no (the genre is zero-sum), no knob in Stage 4.
3. The weak-player rule? Default: on, ratio 3.
4. Lock levels in Stage 4? Default: level 1 only (`SaleMax = 5` sells all five).

**P2 (only if a wave has time):**

- the flag `OwnerSign` flashing «🚨 КРАЖА!» on the owner's client;
- `MaxIndicatorDistance` hints on the prompts;
- a «Твои защиты» line on the badge chip tap;
- the carry pose (if R14);
- a red dashed "safe line" decal along the plot edge during the carry (the reference's look);
- the bell swing and the red court lanterns of the siren (DC-17);
- the tank-panel theft overlay: the Berry pill with a timer bar, the «УКРАДЕНА!» stamp, scrolling to the
  card (DC-18);
- the awake dog trotting after a visitor in the plot (DC-05);
- the «🎯 ТВОЯ» get-it-back mark over the display that holds your stolen fish, for 3 min (DC-23);
- the empty tank card remembering «Украдена · {Name}» for 5 min (DC-24);
- the save write token that turns a lost reply into a commit (BE-6);
- the teleport-in suspicion counter (BE-12);
- no after-theft immunity for a loot weaker than the victim's weakest fish (R11);
- the Stage 3 `TankPrompt` hide moved to the `MaxActivationDistance` trick (BE-14).

---

## 10. «Как проверить Этап 4» (outline for the README, Russian)

0. **Главное правило** (первая строка раздела): «Кража = удержать «Украсть» 3 с **и** унести рыбу за
   ограду. Пока рыба на голове у вора, хозяин может нажать ЩИТ или догнать вора».
1. **Server & Clients, 2–3 игрока** (Studio → Test → Clients and Servers). В Studio все защиты (новичка
   5:00, после кражи 1:30, «садок отдыхает» 10 мин) сокращены до 10 секунд —
   `DefenceConfig.Debug.StudioProtect`; поставь `false`, чтобы проверить настоящие времена. Подожди 10
   секунд (фишка «🛡️» справа от плашки базы) и поймай 3+ рыбы вторым игроком. Только что пойманную рыбу
   30 секунд украсть нельзя.
2. **Кража:** первым игроком зайди во двор второго → у витрины с рыбой «E Украсть · Окунь · +$4/с».
   Держи 3 секунды (сверху полоска «КРАДЁШЬ: ОКУНЬ»). Рыба прыгнет на голову → «БЕГИ ЗА ОГРАДУ!» и
   красная дорожка к выходу → выйди за забор → «ДОБЫЧА!», рыба в твоём садке.
3. **Жертва:** у второго игрока сразу плашка «ВОР В САДКЕ!» с большой кнопкой «ЩИТ» и кнопкой «ДОМОЙ»,
   мигает лампа на мачте, у ведра на пирсе «🚨 КРАДУТ!». Если в этот момент открыта карточка улова, она
   сама закроется и плашка появится. После кражи — «Украдено: …» и «Садок отдыхает 1:30».
4. **Прервать кражу:** отпусти кнопку / отойди от витрины / нажми Reset → «СОРВАЛОСЬ!», рыба вернулась.
   Хозяин нажимает «ЩИТ» во время удержания **или пока вор несёт рыбу** → рыба вернулась домой, над
   двором купол. Хозяин нажимает «ДОМОЙ» и подбегает к вору ближе 6 шагов → «Вор пойман — рыба
   спасена!».
5. **Защита:** кнопка «ЗАЩИТА» справа → карточки Щит (бесплатно, 1 мин, перезарядка 3 мин), Собака
   ($6 000), Сигнализация ($2 500), Замок ($1 500). Купи (два нажатия). Собака появится во дворе у
   фонтана и побежит за вором — он станет вдвое медленнее. С сигнализацией хозяин узнаёт о госте заранее
   («Ника у тебя во дворе!»), а вор подсвечен красным. С замком кольцо кнопки «Украсть» 4 с вместо 3
   (сильнее замки — в магазине, Этап 5). Над аквариумом у всех видно «🔐1 · 🐕 · 🚨».
6. **Нечестные ходы не работают:** нельзя красть у себя, у игрока с 1–2 рыбами, под щитом, свежий улов
   (30 с), у намного более слабого игрока, больше 2 рыб у одного игрока за 10 минут, чаще раза в 30 с;
   пойманный хозяином вор 20 с не может красть на этой базе; во время кражи не работает «ДОМОЙ».
7. **Сохранение:** после кражи выйди и зайди снова — рыба у вора, у жертвы её нет, ни у кого нет
   копии. Щит после перезахода всё так же перезаряжается.
8. **Проверить в Studio** (симулятор этого не умеет): кнопка «Украсть» не видна через стену галереи и
   не видна хозяину на своих витринах, на телефоне её можно зажать пальцем, кнопка «ЩИТ» на плашке
   большая, купол щита выглядит как переливающееся поле, а не сплошная заливка.

---

## 11. Решения по критике

Rev. 2 decisions on the two critiques. **Accepted** = applied as proposed; **changed** = applied with a
different number or shape (the why says what); **P2** = accepted, but moved out of the waves;
**rejected** = not applied.

### 11.1 `critique_design.md` (kid fairness and fun, DC-nn)

| item | decision | where / why |
|---|---|---|
| DC-01 the shield also stops a carry | **accepted** | D2, D7, D11, §1.2, §2.4, §4.2, §4.4, §6.2–6.3. The rev. 1 free defence had a ≈ 2.5 s window and failed a kid mid-minigame or on a catch card; hold + carry is 6.2–6.7 s at lock 0. No fail wait for the thief. R3 rewritten. |
| DC-02 the alert outranks the catch card | **accepted** | §6.3: `FishingController.HurryCard()` (one public function, owned by C; D calls it), the normal close path, the slam may finish, the plate after `CounterHold` clears. Tests in C and D, e2e case 8, render `theft_alert_catch`. |
| DC-03 the shield tops up expiring protection | **accepted** | `Shield.StackBelow = 60` (§2.4, §4.10 check 5); the card shows «ВКЛЮЧИТЬ» whenever activation would be accepted. |
| DC-04 big shield button, honest states | **accepted** | §6.3: ЩИТ ≥ 56 px and ≥ 35 % width, Slate «⏳» on cooldown, no buttons while stealing, Compact shows [🏠] when not ready; render `theft_alert_while_stealing`. |
| DC-05 the dog reaches every starting slot during a lock-0 hold | **accepted** | `Dog.Rest = (6, 58)` in the court, the kennel stays at the fence (§2.1); arrival 1.3–2.2 s vs 3.2–4.3 s before; the waypoint now applies only to a dog in front of the arcades. The optional "dog follows a visitor" → **P2**. |
| DC-06 victim cap 2 per 10 min, drop the pair limit | **accepted** | D5, D21, §2.4 (`rest` kind, the loss list keyed by UserId, re-applied on rejoin), §4.3 row 11. One refinement: starting a steal also forgets the victim's loss list, so the map agrees with the protection. Alt farming of `rest` is R11. |
| DC-07 newbie protection on the first session | **accepted** | `JoinProtectFirst = 300`, kind `newbie`, `SaveCount == 0` read at `Loaded` (with BE-25), the `EndingWarn` 15 s toast + bobbing «ЗАЩИТА». Added `leftAt` so Memory mode and same-server rejoins stay quick (R21). |
| DC-08 a fresh catch is not stealable for 30 s | **accepted** | `FreshCatch = 30`, runtime + slot attribute `FreshUntil` (the client needs it to hide the prompt; the critic named no channel), reason `new`. |
| DC-09 no farming much weaker kids | **accepted** | `RichRatio = 3`, `RichMin = 20`, reason `weak`, row 15; the client filter uses the Player `Income` attribute (exists, `EconomyService.luau:208`). R20 covers the empty-server case. |
| DC-10 defending matters; no alert harassment | **accepted, merged with BE-19** | `TagCooldown = 20` on that base, `FailCooldown = { 3, 10, 30 }` in `FailWindow` 60 (per thief, not per pair: simpler and stricter), `early` → 30 at once (from BE-19), `AlertCoalesce = 30` from the last loud alert, `IntruderCoalesce = 45` and none while protected. |
| DC-11 Stage 4 sells lock level 1 only | **accepted** | D8, §2.3, `Lock.SaleMax = 1` replaces `OnSale`, reason `soon`. **Changed:** the card has no pips in Stage 4 (they would advertise an unbuilt Stage 5 item); Stage 5 adds them. |
| DC-12 defences visible to strangers | **accepted, changed** | The sign line «🔐1 · 🐕 · 🚨» is shown to every viewer, the owner too (no owner branch, and it shows off the purchase). Shield readiness is never shown. |
| DC-13 card copy + first-affordable badge | **accepted** | §6.6 effect lines, §6.2 badge once per session. |
| DC-14 copy fixes | **accepted** | No «№», «{Name} у тебя во дворе!», the «Садок отдыхает» loss toast, one tip per loss (§1.2, §6.10). |
| DC-15 the dome for the shield only | **accepted** | `Dome.Kinds = { shield = true }`, `PhoneMax = 2`; the other kinds show on the chip, the tank sign and a client label on the flag's `OwnerSign` (exists in the template; a sibling billboard if it has no room). |
| DC-16 cut `NotifyController.Point` | **accepted** | §6.1, §6.4, Wave 0. The trophy-chip relocation stays. |
| DC-17 trim the alarm FX | **accepted** | The bell swing and the red lanterns → **P2** (§5.3). |
| DC-18 tank-panel overlay → P2 | **accepted** | §6.7 keeps only the Sell labels «КРАДУТ!» / «В ПУТИ…»; `CardTemplate.Steal` is gone from Wave 0. |
| DC-19 `Carry.Enabled = false`: server path + one test | **accepted** | R1, §7.2. |
| DC-20 a Studio knob for the protection timers | **accepted, changed** | `Debug.StudioProtect = 10` (§2.4). It `print`s instead of `warn`ing (the suites assert no warnings), and because RbxSim answers `IsStudio() == true`, `Kit.boot` turns it off for the stage 4 tests. |
| DC-21 tests and renders for the fairness rules | **accepted** | §7.1 invariants, §7.2–7.4 cases, e2e cases 7–8, renders `theft_alert_while_stealing`, `theft_alert_catch`, `shield_chip_rest`, `newbie_protect_ending`. |
| DC-22 README: the carry rule first | **accepted** | §10 step 0 and step 6. |
| DC-23 "get it back" mark | **P2** | A nice steal-back loop, but new client UI with no fairness need; listed in §9 P2. |
| DC-24 the empty tank card remembers | **P2** | Tied to the trimmed tank-panel overlay (DC-18). |
| §7 questions for the user | **accepted** | §9 "Questions for the user", with the critic's defaults. |

### 11.2 `critique_backend.md` (data safety, exploits, testability, BE-nn)

| item | decision | where / why |
|---|---|---|
| BE-1 escrow lost when the victim is already `Leaving` | **accepted** | `DataService:AmendLeaving` + `rec.FinalTaken` (§4.6), F8a/F8b/F8c and F9' (§3.3), tests F8b/F9'. Checked against `saveOnce` (`DataService.luau:470-520`): the flag is set where the release snapshot is taken. |
| BE-2 match by the victim's record; key by the thief's `Player` | **accepted** | §3.2 map and handlers; `Released` once per record (`release` early return); the seq-collision test. |
| BE-3 register the escrow first; apply a precomputed plan | **accepted** | §3.2 step 0 (`Seq = math.huge`), the plan in CHECK, money and signals moved to step 5; the inline-save test. |
| BE-4 idempotent return/void/clear, uid guard, stats | **accepted** | §3.2, §3.4 #6, F14; return/void take the stats back. |
| BE-5 unmount clears the slot steal channel | **accepted** | §4.5 (`showEmpty` clears `StealBy/StealEnd/Escrow/FreshUntil`, then `StealPhase`; `fish.Steal = nil` before `rt.Base = nil`); test in §7.2. |
| BE-6 ambiguous commits | **accepted (1, 2, 4); P2 (3)** | F7 documents the lost-reply loss; "never clear on a timer" in the headers and §3.4 #7; sim S4b. The write token changes every save's format, so it waits (§9 P2). |
| BE-7 Origin length | **accepted** | `DataConfig.Limits.OriginMax = 32` (exists at 24, `DataConfig.luau:61`), a rules case. |
| BE-8 the DefenceService ↔ StealService require cycle | **accepted** | `SetStealProbe` (§4.1), a require-graph test. |
| BE-9 the speed check is too loose | **accepted, changed** | The leaky budget of §4.4 via `Lib/CarryGuard`. **`Teleport` = 24, not 20**: a phone's 1.5 s stall at carry speed is ≈ 20.4 studs in one tick and must not return an honest kid's fish; 24 is still under the 26.4-stud cap, and a 30-stud hop is caught. An invariant pins `16 × 0.85 × 1.5 < Teleport < cap`. |
| BE-10 the credit path leaves the thief slow | **accepted** | All four points: `Speed.ClearAll` as the theft Trove's first cleanup, Speed owns expiry, the dog bites only a live theft's thief, the `Ended` flag and token checks (§4.2, §4.7, §2.1). |
| BE-11 `Slowed` at 10 Hz and mixed clocks | **accepted** | `Slowed` is a boolean written on change; the clock rule in §4.7. |
| BE-12 teleport into the court | **P2** | Logging only; it would couple StealService to MarketService's sampler. R8 keeps "no reject at the start". |
| BE-13 classify the HoldEnded reason | **accepted** | §4.3 timing; the far/died tests now expect `far`/`died`. |
| BE-14 hide prompts with a property the server never writes | **accepted** | `MaxActivationDistance = 0` locally (§5.1, D14); S1 reads both properties; the 20-toggle test. Moving the Stage 3 `TankPrompt` hide too → P2. |
| BE-15 fewer server `Enabled` toggles | **accepted** | `Enabled = mounted and State == "fish"` (§4.3); Begin step 3 and the carry "all 12 disabled" step are gone; the shield cancels holds through `ProtectionChanged`. |
| BE-16 silent drops leave the ring running | **accepted, changed** | `NoReply` = **1.0 s**, not 0.6: phone round trips reach 0.3–0.5 s, and a legit hold must not be ended. Quiet Denied instead of suppression; Denied names the slot. |
| BE-17 a repeated HoldBegan on the held prompt is silent | **accepted** | §4.3 row 2, placed before the bucket so a double tap costs no token. |
| BE-18 freeze `HoldDuration` on the held prompt | **accepted** | §2.3, §4.3, §4.2 End; the test now asserts a credit. |
| BE-19 grief by looping hold and release | **accepted, merged with DC-10** | One escalation table `{ 3, 10, 30 }` instead of `3 × 2^(n−1)` capped at 30 (the same shape, readable in config); `early` → 30 at once; `QuietSavedUnder = 1`. |
| BE-20 bucket hygiene | **accepted** | `Lib/Bucket` guard, `byThief` the same, a test. |
| BE-21 the slot `Escrow` attribute | **accepted** | §3.2, §4.11; it feeds the exact client filter and the «В ПУТИ…» label. |
| BE-22 refresh prompts from `TankService.SlotChanged` | **accepted** | §4.3, §4.5. |
| BE-23 `DogPos` only when it changes | **accepted** | `Dog.MoveEpsilon = 0.25` (§2.1). |
| BE-24 public shield timing | **decided: keep public** | §4.11, R23: genre-normal, a cheat gains only timing; no UI shows another player's readiness (consistent with DC-12). Owner-only delivery would need a reliable initial-state remote for little gain. |
| BE-25 `LastOnline` read too late | **accepted** | `loadInfo` at `DataService.Loaded` (§2.4); it also carries `SaveCount` for DC-07. Checked: committed saves copy both into the live data (`DataService.luau:515-518`). |
| BE-26 prune maps when idle | **accepted** | §3.4 #5, §4.11: on write, on `PlayerRemoving` and inside `_debugSizes()`. |
| BE-27 reset all base-level state on unmount | **accepted** | §4.11 and §2.1 (incl. the pup's template pivot); the A-leaves-B-mounts test. |
| BE-28 split StealService | **accepted** | `Shared/TheftChecks` (shared, so the client filter runs the same rows) and `Lib/CarryGuard`, both written in Wave 0 with their unit tests. |
| BE-29 generalise S3 | **accepted** | S3 is `FirePromptEvent`. |
| BE-30 S8 prompt events through `remoteLatency` | **accepted** | §7.0, e2e case 9. |
| BE-31 S1 reads `MaxActivationDistance` | **accepted** | Folded into S1. |
| BE-32 S7 reverse `PlayerRemoving` order | **accepted** | §7.0; `stage4_data` runs in both orders. |
| BE-33 S6 players-first shutdown | **accepted** | §7.0, F9'. |
| BE-34 S4b `FailKey(…, { after = true })` | **accepted** | §7.0, F7 lost-reply test. |
| BE-35 `Kit.drive` | **accepted** | §7.7 kit; the speed tests. |
| §H the corrected failure table | **accepted** | §3.3 (F8 split into a/b/c, F9', F14; F10 narrowed to the crash case). |
| §I "50 buys → one purchase" fails for Lock | **resolved by DC-11** | Every Stage 4 item is a one-time buy; a `SaleMax`-patched test uses "≤ Burst levels, each paid" (§4.10). No per-item cooldown needed. |
| §I optional: no after-theft immunity for a weak loot | **P2** | R11; only matters for alt farming, which creates no money. |

### 11.3 Wave 0 contract review (W0-nn; applied to this document and the code)

| item | decision | where / why |
|---|---|---|
| W0-01 `HUD.TheftBar.Bar.Fill` missing (the builder had `Bar.Track.Fill`) | **accepted (a)** | `gui/Steal.luau`: `Fill` is the `Track`'s sibling inside `Bar`, drawn over it (ZIndex above; the HUD is `ZIndexBehavior.Sibling`), so the §6.1 path is the built one. `tests/hud_style` pins `Bar.Track` and `Bar.Fill`; STYLE.md §6.5 lists `Bar.{Track, Fill}`. |
| W0-02 `Upgrades.Dog/Alarm` keep numbers, but §3.1 said boolean only | **accepted** | §3.1 and §4.12 now say what the code does (a newer server's number ≥ 0 is kept, B-6). Ownership is one pure predicate, `PlayerData.Owned(v)` = `v == true or (number and v > 0)` (tested in `stage4_rules`); the DefenceService and RemoteNames headers say HasDog / HasAlarm, the attributes and the `owned` check use it and nothing else. |
| W0-03 DogBrain `Pending` conventions not in its header | **accepted (documented)** | The DogBrain header states them: a missing key = untouched, `false` = `SetAttribute(name, nil)` (Reset clears all three), `DogPos` is base-local and is written as `base.Model:GetPivot() * pos` (world, §2.1, §4.11). The writes stay Wave 1 A's (§8). |
| note: `FinalTaken` stays set after a failed final attempt | **accepted** | §4.6 and F8c: a failed release attempt clears it, so a retry writes an amendment made between the attempts (`tests/stage4_data_hooks`). |
| note: `Serialize` does not clamp a negative `ShieldReadyAt` | **rejected** | `Serialize` checks types (finite) for every number and clamps none (Money, LockLevel alike); `Sanitize` clamps on load and DefenceService clamps at load (§3.1). Only DefenceService writes it, always `os.time() + …`. |
| note: `PreviewAdd` and `_debugSizes` miss Steal/Escrow | **Wave 1 A** | `FishRt.Steal` and `FishRt.Escrow` do not exist before `SetSteal` / `StealFish` (§4.5); A adds them to the `Locked` candidate rule and `Escrows` to `_debugSizes`. |

### 11.4 Wave 1 A review (server core; A1-nn data, A2-nn rules) and the implementer's decisions

| item | decision | where / why |
|---|---|---|
| A1-01 a fish returned into a full tank stayed dormant (F8a) | **accepted** | TankService `backToVictim`: no free display → the AddFish full-tank rule (a weaker unlocked fish sold for the victim, the returned one in its display, Event `swap`; otherwise the returned fish itself sold, `Result.LeftSold`); `Returned` names `Result` and `Price`. The leaving victim (F8b, `AmendLeaving` writes only `Tank`) keeps the row dormant with its `Slot` (documented in §3.3). Tests `stage4_data` F8a' / F8b'. |
| A1-02 an amendment refused while the final attempt was in flight was dropped when that attempt failed | **accepted** | `rec.PendingAmends` (§4.6, F8c): applied before the retry of a failed attempt, dropped on committed / quiet / lost / window over. Cannot duplicate (the thief's copy is already stripped). Test `stage4_data` F8c' in both handler orders (FinalTaken forced at the read, as Roblox runs the transform there; RbxSim runs it after the latency). |
| A1-03 the failure table over-promised for failing-store losses | **accepted (documentation)** | §3.3 F7 and F10 and the TankService header item 12: unsaved progress under a failing DataStore, never a duplicate. |
| A1 note: return inserted into the victim before stripping the thief | **accepted** | `returnEscrow` strips first: a throw in between loses one fish instead of leaving two. |
| A1 note: `LeftAt` nonzero for `QuickRejoin` after everyone leaves | **accepted (documentation)** | §3.4 #5 now separates the per-player tables (zero 10 s after) from the time-bounded maps (zero once their windows pass). |
| A2-01 a 2×–2.5× speed hack reached the nearest fence on the full starting budget | **accepted** | `StealConfig.Carry.Speed.Start = 6`: the budget starts small and the stall reserve is earned walking; a 2× hack is returned in ≈ 0.9 s. §4.4 table; `stage4_rules` CarryGuard cases; `stage4_theft` drives 2× / 2.5× from 6 displays to the nearest fence. |
| A2-02 an error after `StealFish` left the theft alive forever | **accepted** | `credit` runs its side effects in `xpcall` and always `finish`es; the watcher's error branch finishes a credited theft; `finish` drops the records before the cleanup. Test `stage4_theft_end`. |
| A2-03 a rejoin dropped `StealCooldownUntil` | **accepted** | StealService writes it again on `TankService.Mounted` while the wait runs (§4.11). The tag wait is per base and has no attribute: after a rejoin the client may show «Украсть» on that one base for ≤ 20 s and the server answers `tagged` (accepted). |
| A2-04 the owner's early tag / shield was sent Quiet | **accepted** | Quiet only for endings the owner did not cause (§1.2, §4.2). Test `stage4_theft_end`. |
| A2-05 a long server tick counted as a teleport | **accepted** | `Teleport + allowed × Rate × max(0, dt − Tick)` (§4.4). Tests in `stage4_rules` and `stage4_theft`. |
| A2 note: an honest phone's late HoldBegan reads as `early` (30 s) | **open (design)** | Not changed: the server cannot tell it from `fireproximityprompt`. Option for the designer: treat `early` as an ordinary fail step. |
| decision: `TankService:Income10(player)` | **added (read API)** | The weak rule and the victim cap read the victim's income without TankService internals. |
| decision: `SlotView.Kg`; `StealService.TheftOn` takes a base or its model | **added** | The steal payloads name the size; DefenceService and tests pass models. |
| decision: extra `_debugSizes` keys (StealService Denied, Dogs, Watcher; DefenceService Alarmed, IntruderLoop; TankService Escrows) | **added** | The leak tests assert each returns to zero. |
| decision: server `Notify` (kind `shield`) «Щит погас» and `Hint.Ended` | **added** | Join / newbie / EndingWarn toasts stay on the client (§2.4). |
| decision: a Triggered with no hold, or too early, logs a rate-limited `print` | **changed** | A laggy honest client can do it; normal flows stay warning-free. |
| decision: DogBrain writes DogState / DogTarget at once on Wake / Return | **changed** | «ГАВ!» in the same frame the hold starts; `Reset` always clears all three. |
| decision: `Carry.Enabled = false` = SetSteal "carry" + StealFish at once | **implementation** | One code path. |
| decision: the alarm's early warning is skipped while a theft is live on that base | **implementation** | The theft alert already says it. |
| decision: the held prompt keeps its HoldDuration until the theft ends | **implementation (BE-18)** | A lock bought mid-hold applies to the next hold. |
| decision: the home guard during the own base's theft faces the base's +Z (`CFrame.lookAt`) | **changed (§4.6)** | Independent of the spawn pad's own rotation; the test asserts +Z. |

### 11.5 Wave 1 B review (B1-nn; world; applied to this document and the code)

| item | decision | where / why |
|---|---|---|
| B1-01 the thief's own follow camera: the robbed display under HUD.Status and the TheftBar | **accepted, changed** | §6.4 rev. 3, §6.9, tools/builder/DESIGN.md (the band). Measured with `TankWorldController.StealRect` (new): the display covers x ≈ 0.36–0.64 W, y ≈ 0.10–0.45 H on all four devices, so the critic's "TheftBar in the badge row (phone y 58–110)" would still cover the lifted fish (phone y ≈ 70–130). Instead: Status hides while `HUD.Stealing` is set (D, HudController) and the TheftBar docks in the bottom band (C), ≥ 16 px from the thumbstick and Jump, under the prompt. Renders `steal_hold_thief_hud` (rev. 2) vs `steal_hold_thief_rule` (the rule, mocked) on phone, phone_small, tablet and desktop. |
| B1-02 the dome as a full-screen layer from the owner's spawn camera | **accepted** | §5.3: `Dome.Near` 16; Inside when the camera or the own HRP is inside, lerped (0.05 steps on the 0.5 s chain) within Near outside the skin. Test: camera outside, character inside → Inside; the band in between. Render `shield_dome_spawn`. |
| B1-03 the siren does not read | **accepted** | §5.3: `Siren.Pitch` 38°, two `Beam`s (`BeamLength` 14, `BeamWidth0/1` 0.6 → 5, `BeamFade` 0.35, LightEmission 1, LightInfluence 0) on a spinner part (1 client part, the `Theft` reserve) spun by the one tween. Render `alarm_lamp_far`. The SpotLight look on court surfaces: Studio. |
| B1-04 the defences row behind the fountain statue | **accepted** | §5.3: the row on top, the sign grows up (`SizeOffset` +k/2/(1+k)). Mirroring the icons on the flag label: not done (the flag label is about protection; the sign row is seen from the gate). Render `tank_sign_gate`. |
| B1-05 low lamp contrast | **accepted** | `World.LampDim` (56, 10, 10) ↔ `LampOn` (255, 112, 84); the lights take `World.LightColor` (red). Test: WCAG ratio ≥ 4. |
| B1-06 lanterns cut the steal words | **accepted** | `AlwaysOnTop` on «КРАДУТ!» and «УКРАДЕНО!» only (MaxDistance 90). Render `steal_hold_spawn`. |
| B1-07 TheftWorldController's words never fade under the HUD | **accepted** | `TankWorldController.TrackWord(gui, cap?, capW?, capH?)`: «ВОР!», the carried plate and «ГАВ!» go through the same rule (`wordRect` now follows `Adornee`, `StudsOffsetWorldSpace`, `StudsOffset` and `SizeOffset`); gone words leave the table. The thief keeps his plate (the §6.4 rule hides Status anyway). |
| B1-08 «ГАВ!» left behind; ranges | **accepted** | Adorned to the pup's Body; `World.WordRange` 120 for «ВОР!», the plate and «ГАВ!» (`Carried.PlateRange` removed). |
| B1-09 the dog does not look asleep and sinks | **accepted, changed** | A still «💤» (`World.Dog.Sleep`, `SleepRange` 60) — **no bob tween**, so an idle base has no per-frame work. The ground: one ray per `DogPos` change (Grounds / Arcades), and the asleep pose raised onto the paving **on the client** (A's DefenceService keeps pivoting at the template height; the client lift is visual only, so no A/W0 number). |
| B1-10 the flag label on the blue cloth | **accepted** | Over the owner sign (`Flag.Raise` 1.02 of its height, the line at the bottom of its box). Render `flag_label_neighbour` (base 2 is blue). |
| nit: `stepDog` looked the thief up every frame | **accepted** | The DogTarget's Player is cached in `watchTarget`. |

### 11.6 Wave 2 (C — the thief's HUD, D — the victim's alert and the defence UI): decisions and deviations

| item | decision | where / why |
|---|---|---|
| D-01 the phone pill's place | **changed** | §6.3 said `FishingLayout.clearOf`; that helper is about words over the panel, so the pill has its own helper `Controllers/AlertLayout` (`compact`): three bands (right of the fisher up to the column, left of him, the toast column), the widest pill that fits anywhere in a band (≥ 16 px + inks from the fisher, the own bobber, the status stack, the column, Jump, the thumbstick, the fishing widgets and the TheftBar), then a tight pass (16 px + the pill's own stroke), then a label-less pill (`COMPACT.Narrow` 132 px: 🚨 + a full-width ЩИТ), last the least-covering spot (the fisher 20× dearer). Re-placed on events only (fishing state, widgets shown / moved — debounced 0.12 s —, the character's tools, the screen), never per frame. |
| D-02 phones always get the pill | **noted** | The toast column (from y ≈ 152 on a phone, §6.9) crosses the fisher's head on every phone, so the full plate is the tablet / desktop layout in practice; the pill sits below the status stack beside the fisher or, when the minigame takes that room, at the top-left under the Roblox buttons. Renders `victim_alert_*` on phone, phone_small, phone_notch. |
| D-03 the pill's label can hide | **added** | Below `COMPACT.LabelMin` (56 px of label room: phone_small in a minigame, phone_notch's inset) «ВОР! ФУГУ» hides and ЩИТ takes the width (≥ 56 px tall, ≥ 35 % — the one tap that matters stays big). The edge pulse, «ДОМОЙ!» and «ЩИТ!» in the column still say what happens. |
| D-04 the pill's 🚨 | **changed** | `IconScale` 0.9 (was 1.1): the emoji's ink stayed outside the 56 px pill and broke the 16 px rule against the minigame and the status stack. |
| D-05 the plate's text is box-driven | **changed** | Title 14..30 px on one line, Sub 12..20 px wrapping (no tiers): on a desktop the chat narrows the toast column to ≈ 392 px and the Title tier broke «ВОР УБЕГАЕТ!» into two lines over the Sub. At run time the text ends 8 px left of the button row (the square ДОМОЙ is sized by height, so on a tall plate the row grows left of its share). |
| D-06 the pop-in shake | **changed** | ≤ 5 px (`UiFx.shake` takes a fraction of the parent: the first cut used 6 = 600 % and threw the pill off screen). |
| D-07 one shield request | **added** | `DefenceController.ActivateShield` answers false while a request waits for `DefenceEvent` (≤ 3 s): the plate, the pill, the column «ЩИТ!» and the card share it — three taps send one `ShieldActivate`. |
| D-08 one sheet at a time | **implemented** | `Controllers/Sheet` closes the other sheet with reason "switch" and hands over the saved `Toasts.ZIndex` and the hidden fishing layer, so closing the second sheet restores both. New hook `contentHeight` (tablet / desktop: the sheet no taller than its cards). |
| D-09 the «ЗАЩИТА» cards on a tablet / desktop | **changed** | One row at `CardAspect` 0.78 left half the sheet empty and the large tablet type overflowed the card (the name over the effect). `DefenceConfig.Panel.CardAspectTall` 0.52: taller cards, the sheet hugs them. Phones unchanged (0.78, the 4th card scrolls on phone_small). |
| D-10 the trophy chip on phones | **changed (NotifyController)** | With three buttons in the column (stage 4) there is no room above it on a phone (HUD < 600 px): the chip stands left of the column at its top, `ColumnGap` (20 px) from the buttons; tablets and desktops keep the stage 3 rule. hud_style asserts both. |
| D-11 the tip after a loss | **noted** | Lost → the big theft toast, «Садок отдыхает …», then the one tip; on a tablet the column holds two, so the tip may wait for the theft toast (≤ 12 s). |
| D-12 `MoneyController.Spend(amount, to)` | **added** | The Wallet counts down (a decrease waits for the sale's count-up like an increase), «−$6 000» floats in Berry and 💵 fly from the Wallet into the bought card. |
| D-13 «КРАДУТ!» on the tank panel | **implemented as §6.7** | A tap sends `TankSell` and the server answers «Её сейчас крадут!» (no client-side refusal: the server decides). «В ПУТИ…» Slate while `Escrow`. |
| D-14 the bobber as a keep-out | **added** | AlertController reads the own bobber through `FishingFxController.GetBobber` (C's file, read only; nil when the API is missing). |
| D-15 new texts / numbers | **added** | `StealConfig.Texts.Alert.HomeAlert` «ДОМОЙ!» (the home button's caption while robbed), `DefenceConfig.Panel.CardAspectTall`; the rest of the pill's layout numbers are in AlertController (`COMPACT`, `GAP`, inks). |
| D-16 render `victim_alert_compact` | **changed** | The own trophy is gone once the card closes (the plate waits for the card, DC-02), so "the pill clear of the trophy" cannot happen; the scenario shows the longest short name «МЕЧ-РЫБА» in a Legendary minigame instead. |
| D-17 tests on four screens | **noted** | `stage4_hud_alert` / `stage4_panel` run phone, phone_small, tablet and desktop (RbxSim has no inset device); phone_notch is covered by the renders (`gui_render.py --all`, 0 findings). |
