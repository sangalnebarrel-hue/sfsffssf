# Stage 3 design — садок, доход, продажа, сохранение (single source of truth, rev. 2)

Designer pass, written on top of the four reports in this folder (`read_fishing.md`, `read_world.md`,
`read_ui_tests.md`, `research.md`) and the code at commit `7324c65`. **Rev. 2** applies the two critiques
in this folder: `critique_design.md` (items **K-1…K-23**) and `critique_backend.md` (items **B-1…B-29**).
§10 «Решения по критике» lists every item and what happened to it. Implementers follow this document;
where it is silent, the reports and STYLE.md (`tools/builder/gui/STYLE.md`) apply. Every number named
here goes into a config ModuleScript (§3.1); nothing below is "magic" in code.

Scope: Stage 3 only. Stage 4 (theft, alarm, dog, lock, shield) and Stage 5 (shop, upgrades) are NOT
built, but every hook they need is named in §4.8.

---

## 0. Decisions at a glance

| # | Question | Decision (short why) |
|---|---|---|
| D1 | Where is the садок? | **One tank, three faces.** (1) The fish **live** in the approved court of the base: `Tank` + the 12 display aquariums `Tank.Slots.Slot_1..12`, one fish per display. It is budgeted (0 free parts per base), its prompts are pinned by tests, and it sits **inside the fence**, where the Stage 4 lock, dog and alarm make sense. (2) **The pier end** shows the intake (spec «садок … на конце пирса», K-1). The existing bucket `Platform.Bucket` stands 5.6 studs from `FishingSpot`, in the fishing camera's frame. It carries the world word «🐠 4/6 · +$42/с», a splash when a fish goes in, and the «+$X» income pops — where the kid actually is. (3) The HUD «САДОК» button opens the tank panel from anywhere. (§9 R1) |
| D2 | Slots | `StartSlots = 6` of 12 (rows 1–3, both arcades, nearest the gate); slots 7–12 are visibly **locked** (Stage 5 sells them, up to `MaxSlots = 12`). |
| D3 | Catch → tank | Server-side and automatic at the winning tap. The fish gets a `Uid` and goes into the lowest free slot **before** `"Caught"` is sent; the payload says what happened. **Casting is denied until the player's data is loaded** («Загружаем твой садок…»), so there is no pending-catch path (B-12). «ЗАБРАТЬ!» stays a close button. |
| D4 | Tank full | **Never blocks fishing, never asks mid-catch.** A new fish that earns more replaces the **lowest-income** fish, which is sold at its current value; otherwise the new fish is sold at once. **"sold" is quiet**: the card stamp «ПРОДАНА», coins into the Wallet, one toast per session. **"replaced" is the moment**: the stamp «ЗАМЕНА!», a toast, and the rate rolls up (K-4). In 1000 runs of 30 min, a Mythic was never auto-replaced or auto-sold. |
| D5 | Income | `FishData.Income` × `IncomeScale` (1), held as **integer tenths** (`Income10`). One fixed-step 1 Hz server loop for all players, with ≤ 3 catch-up ticks; whole coins are credited and the fraction is carried in tenths (B-17, B-19). Income runs only while the owner is loaded, writable (`CanWrite`) and has a base. |
| D6 | Value growth | Linear `×1 → ×3` over **300 s** of tank time (online, with a base), then «МАКС». The age is derived from one server clock (`GrowFrom`) on the server and the client alike (B-18). Income does not grow. |
| D7 | Selling | **One fish at a time** from the tank panel, **anywhere, any time**, at ×1 (spec «в любой момент из садка»). **All five «ПРОДАТЬ РЫБУ» stalls** pay **×1.5**: the hub «РЫБНЫЙ РЫНОК» and the 4 bridge kiosks share one rate (K-17). The server decides from its own 1 Hz position samples (B-22). **There is no «ПРОДАТЬ ВСЁ» in Stage 3** (K-2). |
| D8 | Confirm | **Every** sale takes two taps. The first shows «ТОЧНО?» with a 3 s ring, and the card's rate flashes red «−$4/с». The second tap counts only after a **0.4 s arm delay**, so a double-tap cannot sell (K-3). No favourites in Stage 3. |
| D9 | Offline earnings | **No** (tank lives only while you are online; Stage 4 fairness). `LastOnline` is saved for later. |
| D10 | Money | Integer coins in `[0, MaxMoney = 1e15]`, start $0. Shown «$1 234» (NBSP groups) up to $999 999, then «$1.23M», «$12.3M», «$1.23B», «$1.23T», «$1.23Qa» (B-20). The currency is `$` with the 💵 icon everywhere in the new UI; the catch card copy switches to `$` too. |
| D11 | Persistence | One DataStore key per player, **UpdateAsync only**. The **per-load session lock** lives inside the value, and ownership is strict: a missing lock means "lost" (B-1, B-2). Records are keyed by the `Player` (B-3). There is one write gate, `CanWrite` (B-4). The serializer is a validating whitelist (B-5), and sanitize is rolling-update safe: it never destroys what it does not understand (B-6). Each key has a FIFO with a ≥ 6.05 s gap, stamped when a request finishes (B-9). Autosave every 60 s, a final save on PlayerRemoving, and parallel saves in BindToClose (≤ 25 s). |
| D12 | Load fails | After ~30 s of retries → **kick** with a friendly Russian message (never play on defaults that could be lost or overwrite). Data newer than the server (`V > 1`) → kick «Игра обновилась». The record is `Released` before any kick (B-14). |
| D13 | Studio without access | **Memory mode** only when `RunService:IsStudio()` **and** the boot probe's error says API access is off (B-8). It uses defaults, never writes, prints one Output `warn` with instructions and shows one in-game toast; BindToClose returns at once. A live server never plays on unsaveable defaults. The sim reports Studio, so tests reach memory mode with `SetEnabled(false)`. |
| D14 | HUD | `Status.CatchCounter` is replaced by `Status.Wallet` (💵 «$1 234» + «+$42/с»). A new square `RightButtons.TankButton` (🐠 «САДОК», chip «4/6», onboarding «!») sits above «ДОМОЙ». `HUD.TankPanel` is built on a reusable sheet shell (K-18). The catch card gets a result stamp (K-4). |
| D15 | leaderstats | `IntValue` «Деньги» (first: the list sorts by it) and `IntValue` «Доход/с». |
| D16 | Economy truth | In Stage 3 **holding a fish always beats selling it**. Income is ≈ 98 % of all money, and a fish earns back its maxed price in 30–36 s of its own income. Selling has three uses: making room (automatic), a Stage 4 lever (bank a fish before a thief takes it) and a Stage 5 lever (cash now for an upgrade). The UI copy never advertises selling. Stage 5 knob: `EconomyConfig.SellScalePct` (K-5). |

---

## 1. Player loop after Stage 3

### 1.1 The loop (kid's view)

1. Spawn at the base. The base banner lands in the badge, then **💵 «$0»** pops in under it, then the
   aqua **«САДОК» 🐠 0/6** pops in above «ДОМОЙ», 0.3 s apart (K-10). «ВЗЯТЬ» → walk to the pier.
   Over the bucket beside the fishing spot floats the word «🐠 0/6». (If the data is still loading
   after 3 s, the Wallet shows «$…» on glass, and a cast answers «Загружаем твой садок…».)
2. Cast → bite → minigame → win (unchanged). The pier word hides during the bite and the minigame.
3. **At the winning tap** the server stores the fish in the tank (slot, `Uid`) and sends `"Caught"` with
   the result. The leap, the trophy over the head and the catch card play as today. The card shows
   «цена $45», its float now reads **«+$4/с»** (the fish's income), and a small stamp tells the
   outcome: **«В САДОК!»**.
4. «ЗАБРАТЬ!» / tap / auto-close: the card ghost and the 🐟 fly into the **«САДОК» button**. Its chip
   rolls «2/6 → 3/6», the button bumps with a rarity glow ring, and the **Wallet's «+$/с»** rolls up
   («+$9/с → +$13/с»). At the pier bucket a splash plays and the word bumps to «🐠 3/6». In the court
   the fish appears in its display aquarium.
   First fish ever: the toast «Твоя рыба приносит $ каждую секунду!» and a red «!» on «САДОК» until
   the kid opens the panel (K-8).
5. Money ticks up every second (plain text, calm). Every 5 s a small green «+$13» floats off the
   Wallet, and, while the kid is within 30 studs of the bucket, the same «+$13» rises over the pier word.
6. Every fish's value climbs to ×3 («МАКС»). The panel header shows the tank's total value «💵 $2 783 📈».
7. Tap **«САДОК»** anywhere → the tank panel opens. If the kid taps it while a fish is flying in, the
   panel opens right after the arrival, on the new fish (K-9). It shows one card per slot (a 3D fish,
   «+$4/с», a growth bar, «💵 $45»), empty cards and one locked teaser card. A sale takes two taps:
   «ТОЧНО?», while the rate flashes red «−$4/с». Then the card pops, 💵 fly into the Wallet, and the
   Wallet's rate rolls **down** with a red flash.
8. At any «ПРОДАТЬ РЫБУ» stall (the hub market or a bridge kiosk), hold **E «Продать рыбу»** → the same
   panel opens. Within ≤ 2 s the gold «🏪 РЫНОК +50%» chip pops in and the prices jump ×1.5.
9. Tank full (≈ 1:41):
   - A stronger catch replaces the weakest fish. The stamp reads «ЗАМЕНА!», the toast «Замена!
     «Меч-рыба» вместо «Карасик» +$24», the rate rolls up, and the world fish swaps.
   - A weaker catch is sold on the spot. The stamp reads «ПРОДАНА», a gold «+$15» float rises, and the
     ghost flies as 💵 straight into the Wallet. Only the first time per session a toast says «Садок
     полон — лови рыбу получше!».
10. Leave → everything is saved; rejoin → same money, same fish in the same displays with the same ages.

### 1.2 Decisions with justification

**Selling anywhere from the panel (×1).** The spec says «продать рыбу в любой момент из садка или в
магазине на хабе». A kid spends ~90 % of the time on the pier, 131–185 studs from the displays. Making
them walk to sell adds friction and no fun. The server checks ownership, the fish `Uid`, rate limits and
(Stage 4) "this fish is being stolen". Distance matters only for the **stall rate** (D7).

**The economy truth (D16, K-5).** Numbers from `critique_design.md` §1 (1000 runs, the real configs):

- At 10:00, selling the whole tank at a stall leaves the kid with **29 % less money** by 15:00 ($53K
  vs $74K), and $/s drops from 145 to 59.
- Selling a Mythic at the market as soon as it reaches МАКС costs **−$109K** by 30:00.

Therefore:

- There is no sell-all button.
- Every sale is confirmed and shows the income lost.
- The copy never says "sell for profit".
- The stall rate stays: it is the spec's «магазин на хабе», and the price on the button is the
  information.
- Stage 5 decides whether cashing out ever pays (`SellScalePct`, `Growth.Cap`, §9 R9).

**Market prompts open the panel (not an instant sale).** A hold-E «sell everything» at a stall is
exactly how a kid loses a Mythic by accident. The prompt says «Продать рыбу»; the panel lets them pick.

**Full tank = automatic, kid-safe rule.** No modal appears while the trophy is overhead, and the cast is
never blocked:

```
on AddFish(new):
  if a free unlocked slot exists → put it into the LOWEST free SlotIndex                    → "stored"
  else weakest = the ACTIVE fish (not Locked, not Dormant) with the lowest Income10
                 (ties: lowest current value, then oldest)
       if new.Income10 > weakest.Income10 → sell weakest at SellPrice(…, HomeRatePct), new takes its slot → "replaced"
       else → sell new at SellPrice(new.Value, 0, HomeRatePct)                              → "sold"
```

The tank therefore auto-upgrades itself by income, the number kids watch. Past ≈ 4 minutes most catches
are weaker than the whole tank: sold on the spot in 52 % of catches at minute 4 and 82 % at minute 10.
No Common can get in after ≈ 3.9 min, and no Rare after ≈ 11 min. So "sold" must be quiet, and the rarer
"replaced" (about one a minute in minutes 3–10) is the loud moment (K-4).

**Default slots 6.** 6 fish fill rows 1–3 on both arcades (slots 1..6 alternate west/east, nearest the
gate; `stage1_bases` already pins 1..3 as the nearest). The tank fills at ≈ 1.7 min, the first
decision point. Slots 7–12 show a dim light bar and «🔒 Закрыто», Stage 5's first goal.

---

## 2. Data model and persistence

### 2.1 PlayerData schema v1 (`src/ServerScriptService/Lib/PlayerData.luau`)

Stored at DataStore `PlayerData` (Studio: `PlayerData_Studio`), key `Player_<UserId>`:

```lua
{
  V = 1,                      -- schema version (integer)
  Money = 0,                  -- whole coins, 0..MaxMoney
  RodId = "RodBamboo",        -- «уровень удочки» (RodConfig Tier = level); Stage 5 adds OwnedRods
  TankSlots = 6,              -- unlocked slots, ≥ TankConfig.StartSlots (runtime mounts min(TankSlots, MaxSlots))
  LockLevel = 0,              -- «уровень замка» (Stage 4); 0 = none
  Upgrades = {},              -- Stage 4/5 dictionary (Dog, Alarm, Shield, …); string keys only
  Tank = {                    -- DENSE array (never sparse), order irrelevant
    { Uid = "f7", Id = "Perch", Kg = 1.23, Mutation = "Gold", Age = 212.4, Slot = 2, CaughtAt = 1700000123 },
    -- Stage 4 adds the optional Origin = "<victimUserId>:<uid>" (≤ 24 chars) on stolen fish
  },
  NextUid = 8,                -- per-player counter → Uids "f1", "f2", … (never reused)
  Stats = {
    Caught = 0,               -- fish caught ever
    Sold = 0,                 -- fish sold ever (incl. auto-sold)
    Earned = 0,               -- coins earned ever (income + sales)
    Spent = 0,                -- coins spent ever (Stage 5 SpendMoney); ledger: Money == Start + Earned − Spent
    Species = {},             -- { [FishId] = count } → «НОВИНКА!» is "first ever", a future «Индекс»
  },
  Created = 0,                -- os.time() of the first load
  LastOnline = 0,             -- os.time() at the last save (reserved: offline earnings later)
  SaveCount = 0,
  Session = { Id = "<GUID per load>", Server = "<GUID per boot>", Job = "<JobId>", T = 0 },  -- the lock; nil once released
}
```

**Per fish, stored:** `Uid` (`^f%d+$`, ≤ 12 chars), `Id` (FishConfig Id), `Mutation` (absent = none),
`Kg`, `Age` (seconds of tank time, 1 decimal, ≤ `Growth.Time`), `Slot` (1..TankSlots, unique among active
fish), `CaughtAt` (os.time, informational), `Origin` (Stage 4, optional).

**Derived, never stored:** `Rarity`, `Value` and `Income10`, all from `FishingRules.Price(Id, Kg, Mutation)`
on load. This way balance changes apply to saved fish, and a bad save cannot inject income. `Price` is
called only for known Ids, because it asserts on unknown ones. It already clamps the size factor, so `Kg`
needs only a finiteness check (`FishingRules.luau:258`), and it already treats an unknown mutation as ×1.
Also derived: the current value (from the age), `GrowFrom`, `Locked` (Stage 4), `Dormant`.

**Not saved:** the session catch count `FishCaught`, the income carry, rate-limit buckets, the fishing
session / trophy / card, `SellRatePct`, the market dwell, the base index (bases are per session), anything
in the client. **Runtime state never lives in the data table.** TankService keeps `GrowFrom`, `Locked`,
`Dormant` and `Income10` in its own runtime records, and keys starting with `_` are never serialized.

`PlayerData` (pure module, unit-tested) exports:

- `Template()`.
- `Reconcile(data)`: deep-fills missing fields in **dictionaries only**. An array field such as `Tank` is
  copied only when it is missing, never merged element by element (B-29).
- `Migrate(data)`: chains `MIGRATIONS[v](data)` while `V < Version`. Empty in v1; a missing `V` is
  treated as 1.
- `Sanitize(data) -> (data, issues)`.
- `Serialize(data, opts) -> (out, issues)`.
- `NewUid(data)`.
- `StoreNameFor(isStudio) -> string`.
- `Ledger(data) -> (ok, expected)`.

**Sanitize — repair only what is provably invalid; never destroy what this server does not understand**
(B-6, B-7). Roblox keeps old servers running after a publish. Stage 4/5 add fish, rods and slots without
bumping `V`, and an old server that loads such data must not drop it, reset it or sell it and then write
that back.

- **Numbers.** One helper, `num(x, default, min?, max?)`: the value must be a number, not NaN and not
  ±inf, then it is clamped. Every numeric field goes through it, because in Luau `math.clamp(NaN, a, b)`
  is NaN.
- **Top-level fields.**
  - `Money`: `floor(num(Money, 0, 0, MaxMoney))`.
  - `TankSlots`: an integer; only the **lower** bound `StartSlots` is clamped.
  - `LockLevel`: an integer ≥ 0.
  - `Upgrades`: a dictionary with string keys, else `{}`.
  - `RodId`: a string. An unknown `RodId` is **kept verbatim**; the runtime rod is `StartRod`, and the
    saved `RodId` changes only through `FishingService:SetRod`.
- **`Tank`.**
  - A dictionary or sparse table is re-packed densely with `pairs`.
  - An entry must be a table with a string `Id` and a finite `Kg > 0`, else it is dropped (issue).
  - An unknown `Id` is **kept verbatim** and is **dormant** at runtime. An unknown `Mutation` string is
    kept; at runtime it counts as none.
  - `Age`: `num(Age, 0, 0, Growth.Time)`.
  - An invalid or duplicate `Uid` gets `NewUid(data)`; `NextUid` ≥ 1 + the highest Uid number.
- **Slots.**
  - A known fish keeps an integer slot in `1..min(TankSlots, MaxSlots)` if no other fish has it.
  - Duplicate or out-of-range known fish are re-packed into the lowest free slots. When none is free,
    they stay **dormant** (kept in `Tank`, `Slot` unchanged). **Sanitize never sells anything.**
  - A dormant fish earns nothing, is not shown, cannot be sold and is never auto-replaced. It is saved
    verbatim and re-checked on every load: a dormant known fish takes a free slot.
- **`Stats`.** Numbers go through `num(…, 0, 0)` and are floored. `Species` keys must be strings, with
  integer values ≥ 0.
- **Ledger** (B-25): if `Money ≠ StartMoney + Stats.Earned − Stats.Spent`, one `warn` with both numbers.
  It is never auto-corrected, because it is a dupe or bug detector.

**Serialize(data, opts) — a validating whitelist** (B-5):

- Known schema fields are copied field by field with type checks: finite numbers, strings ≤ 64 chars, a
  dense `Tank` rebuilt with `table.insert`. An invalid value is replaced by the template default and
  reported, with one `warn` per field path per session.
- Unknown fields (from a newer server) pass through only when JSON-safe: strings, booleans, finite
  numbers, dense arrays or string-key dictionaries, depth ≤ 4. Anything else is dropped and reported.
- Keys starting with `_` are never written.
- `opts.skipUid(uid) -> boolean` leaves fish out (Stage 4 escrow).
- `opts.strict = true` drops every unknown field (the 103/104/105 fallback, §2.2).

Size: 12 fish ≈ 1.5 KB of JSON (limit 4 MB).

### 2.2 DataService (`src/ServerScriptService/Services/DataService.luau`)

**States and the write gate** (B-4). Put this table in the DataService header:

| state | loads | saves | `CanWrite` | income tick | notes |
|---|---|---|---|---|---|
| Loading | in flight; retrying stops once the player has left | — | no | no | cast denied "loading" |
| Ready | — | autosave, SaveSoon | **yes** | yes | |
| Memory | — | never | **yes** | yes | Studio only (§D13); "Broken" behaves the same |
| Leaving | — | one final release save | no | no | set synchronously in PlayerRemoving **and** BindToClose |
| Released | — | never | no | no | set **before** any `Kick`; the record is then dropped |

**Mutator rules.**

- Every mutator in every service checks `DataService:CanWrite(player)` **first**: `AddFish`, `RemoveFish`,
  sell, `AddMoney`, `SpendMoney`, `SetSlots`, `SetRod` and the fishing stats. When it is false, the
  mutator returns `nil`/`false` with no side effects.
- Inside a mutator, compute and validate everything first: the slot, the Uid, the price, `isFinite`.
- Then commit in a fixed order, with nothing that can error between the steps: remove → credit → stats →
  attributes (fish fields → `State` → `Event`) → signals and remotes.
- Listeners of `MoneyChanged`, `FishAdded` and `FishRemoved` must not call mutators synchronously
  (`Signal:Fire` uses `task.spawn`, so they run inside the commit); use `task.defer`.

**Records** (B-3). `records[player]` is keyed by the **Player instance**: a rejoin is a new Player. Every
completion callback runs `if records[player] == rec then records[player] = nil end`. Otherwise an old final
save could delete the new session's record on a same-server fast rejoin. EconomyService, TankService and
MarketService follow the same rule.

**Identity** (B-2):

- `TOKEN = HttpService:GenerateGUID(false)` is generated once per boot, never from `JobId` (`""` in
  Studio, constant in the sim).
- `rec.LoadId = HttpService:GenerateGUID(false)` is generated once per load operation and reused across
  that load's retries.
- The lock is `Session = { Id = rec.LoadId, Server = TOKEN, Job = game.JobId, T = os.time() }`.
- A leaked save of the *previous* session on the same server shares `TOKEN`, but its `LoadId` differs, so
  it cannot cost data.

**Store choice and probe** (B-8):

- `name = PlayerData.StoreNameFor(RunService:IsStudio())`: `"PlayerData"` or `"PlayerData_Studio"`.
- At Start, one probe: `pcall(function() store = DataStoreService:GetDataStore(name); store:GetAsync("__probe") end)`.
  - It has a `ProbeTimeout` of 5 s; with no answer the server continues in normal mode.
  - `probed = true` is set on every path, including an unexpected Lua error, so loads never wait forever.
- **Memory mode** only if `RunService:IsStudio()` and the error text contains `403`, `publish` or
  `not allowed`. On a live server a probe error is only logged; per-player loads retry and kick as
  designed. Loads wait for the probe.

**Load** (per player, through the per-key queue). `UpdateAsync(key, transform)`; the transform is pure,
never yields and never kicks:

```
transform(old):
  lockedByOther, tooNew, corrupt = false, false, false     -- reset every call (UpdateAsync may re-run it)
  if old ~= nil and type(old) ~= "table" then corrupt = true; return nil end
  data = old or PlayerData.Template()
  s = data.Session
  if type(s) == "table" and s.Id ~= rec.LoadId then
    mine  = s.Server == TOKEN and not liveRecordFor(userId, rec)    -- this server, its old record is gone
    stale = os.time() - num(s.T, 0) >= LockStale
    if not (mine or stale or steal) then lockedByOther = true; return nil end
  end
  if num(data.V, 1) > Version then tooNew = true; return nil end
  data = Sanitize(Migrate(Reconcile(data)))       -- issues are logged after UpdateAsync returns
  data.Session = { Id = rec.LoadId, Server = TOKEN, Job = game.JobId, T = os.time() }
  if data.Created == 0 then data.Created = os.time() end
  return data, userIds                            -- userIds = { UserId } only when UserId > 0 (B-23)
```

- **The live table is UpdateAsync's return value**, the committed and decoded value, not the closure's
  `data`, because the transform may have run more than once (B-15).
- `lockedByOther` → wait `LockWait.Every` (6 s, the write gap) and try again. After `LockWait.Tries` (4,
  ≈ 24 s), set `steal = true` and log one `warn("[DataService] сессия игрока <id> занята другим сервером — забираю")`.
  Lock waits are not failed attempts.
- `tooNew` → `Released`, then `player:Kick(DataConfig.Texts.TooNew)`; nothing is written.
- `corrupt` (a non-table value) → `Released`, `warn`, `Kick(LoadFailed)`. Never overwrite what we do not
  understand.
- A `pcall` error → retry with backoff `min(Retry.Max, Retry.Base · 2^(n−1)) × (1 + 0.5·random)` (1, 2,
  4, 8 s plus jitter), up to `Retry.Load` = 5 tries. Codes 101–107 (our bug) and 403 are not retried. Out
  of tries → `Released`, `Kick(LoadFailed)`; nothing is written.
- The player left during the load → stop retrying and wait only for the attempt in flight. If that attempt
  took the lock, run a **release-only** save (same data, `Session = nil`), then drop the record.
- Success → `Ready`, Player attribute `DataMode = "Ready"`, fire `DataService.Loaded(player, data)`.

**Save transform** (`Ready`/`Leaving`):

```
transform(old):
  if type(old) ~= "table" or type(old.Session) ~= "table" or old.Session.Id ~= rec.LoadId then
    lost = true; return nil                       -- a missing lock or a deleted key is "lost", never "fine" (B-1)
  end
  skip = serializeHook and serializeHook(player, rec.Data)   -- TankService: refresh ages; Stage 4: escrowed uids
  out = PlayerData.Serialize(rec.Data, { skipUid = skip, strict = rec.Strict })
  out.Session = if release then nil else { Id = rec.LoadId, Server = TOKEN, Job = game.JobId, T = os.time() }
  out.LastOnline = os.time(); out.SaveCount = num(old.SaveCount, 0) + 1
  rec.SnapshotSeq = rec.Dirty
  return out, userIds
```

- `lost` on a normal save → `Released`, `warn`, and `player:Kick(DataConfig.Texts.Stolen)` if the player
  is still here.
- On a **release retry**, `old.Session == nil` has two causes: our own earlier attempt landed (the result
  was unknown), or another server released after us. Both mean "stop, write nothing": `Released`, no
  warn, no kick.
- Errors 103/104/105 (bad value) → one `warn` with the field paths from Serialize's issues, then **one**
  retry with `rec.Strict = true`. The same failing value is never sent again.

**Per-key queue and write gap** (B-9, B-27):

- One FIFO per UserId, at module level, survives the player record. A request starts only after the
  previous one for that key has finished, retries included.
- Before every `UpdateAsync` attempt (a load, a cancelled one, a failed one), wait until
  `lastRequest[userId] + MinWriteGap + GapEpsilon` (6 + 0.05 s).
- `lastRequest` is stamped **when the pcall returns**: success, failure or cancel. The sim stamps after its
  latency wait (`datastore.luau:_request`), and its clock is a sum of 1/60 steps.
- This keeps the sim's "added to queue" warning away (tests end with
  `AssertNoErrors({ warnings = true })`). It also fixes the same-server fast rejoin: the new load runs
  after the final save released the lock.
- A queue entry and its `lastRequest` are **pruned** once the queue is empty and the gap has passed.

**Autosave** (B-27, B-29):

- **One 1 Hz DataService scheduler loop**; no per-player threads or `task.delay` chains. `Ready` records
  with `now ≥ rec.NextSave` get a save.
- The first `NextSave` = load + gap + `random()·(AutoSave − gap)`; after that, `+ AutoSave` (60 s).
- The autosave also refreshes `Session.T`.
- If `GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < BudgetMin` (5), postpone by
  `BudgetDelay` (10 s), at most `LockStale / 3` in total per cycle, so a live lock never looks stale. The
  sim returns 100.
- A failed autosave is retried once after the gap; after that, the next cadence takes over.
- **Boot asserts:**
  - `AutoSave < LockStale`, with `LockStale = 150 = 2.5 × AutoSave`.
  - `LeaveSaveWindow + MinWriteGap < LockWait.Tries × LockWait.Every` (15 + 6 < 24).

**Coalescing and the commit sequence** (B-11, B-24):

- `rec.Dirty` is a sequence number that `SaveSoon` increments and returns. `rec.SnapshotSeq` is captured
  inside the save transform.
- After a successful commit, `rec.Committed = rec.SnapshotSeq` and `DataService.Committed(player, seq)`
  fires. This includes the final release save.
- A request that arrives while a save for that key is **queued** (its transform has not run yet) is
  dropped: that save will serialize the newest state anyway.
- A `SaveSoon` that arrives while a save is **in flight** (the snapshot is taken), so that
  `Dirty > SnapshotSeq`, schedules exactly **one** follow-up save after the commit.

**PlayerRemoving.** Synchronously set the state to `Leaving` (`CanWrite` is now false). Then the final save
with `release = true`, **retried until it succeeds or `LeaveSaveWindow` (15 s since PlayerRemoving) has
passed**; no new attempt starts after the window (B-10). Then `Released`, and the record is dropped
(identity-checked). The order versus the other services does not matter: the profile in memory is the
truth, and TankService's serialize hook refreshes the ages inside the transform (§4.3).

**BindToClose** (B-13):

1. **Synchronously, before any yield:** `closing = true`, and every `Ready` record → `Leaving`. When the sim
   fires PlayerRemoving after the callbacks have started, those handlers see `Leaving` and write nothing
   again → exactly one final write per key.
2. Memory / Broken → return at once.
3. `pending` is the **set of in-flight operations**, not a count of records:
   - every `Leaving` record's final save, whether this callback or PlayerRemoving started it;
   - every `Loading` record. When its attempt returns with the lock taken while `closing`, it runs the
     release-only save at once.
4. `PlayerAdded` while `closing` → no load, no lock.
5. `while next(pending) and os.clock() − t0 < CloseBudget (25) do task.wait() end`. Close saves use
   `Retry.Close` = 2 tries with a short backoff. A normal save in flight that becomes the final (release)
   save — on leave or at close — starts its own count: its failed normal tries do not use up the
   `Retry.Close` tries, and its first release try always runs (fix BE-01).

**Kicks** (B-14):

- Transforms only set flags; `Kick` runs after `UpdateAsync` returns.
- The record goes `Released` **before** `Kick`. The sim's `Kick` fires PlayerRemoving and flushes it
  synchronously (`players.luau:248`: kick → remove → flush).
- No code after a `Kick` assumes the record still exists.

**Memory and Broken modes** (B-29):

- **Memory.** Every player gets `Template()`, `DataMode = "Memory"`, and no DataStore call happens after
  the probe. One Output warn at boot:
  `[DataService] DataStore недоступен — прогресс НЕ сохраняется. Studio: опубликуй место (File → Publish to
  Roblox) и включи Game Settings → Security → Enable Studio Access to API Services.`
  The client shows one toast (§6.6).
- **Broken.** DataService guards its own `Start`. An internal error sets mode `"Broken"`, logs a loud
  `warn`, and the server behaves exactly like Memory: it plays, never writes, and the client sees
  `DataMode = "Memory"`. Dependants therefore never wait forever for `Loaded`.

**No per-player RBXScriptConnections in DataService** (B-27). `stage2_fishing`'s leak test expects
`CountConnections("server")` back within 0.5 s of `RemovePlayer`, while a final save may wait 6 s behind the
gap. Pending work is a record or a thread, never a connection. `WaitLoaded` waiters are resumed with `nil`
on leave and on timeout; they never block on `Loaded:Wait()`.

**API** (Stage 4/5 use these; nothing else touches the DataStore):

| function | what |
|---|---|
| `DataService.Loaded` | Signal `(player, data)` — once, when `Ready` or `Memory` |
| `DataService:Get(player) -> PlayerData?` | the live table (nil until loaded / after release) |
| `DataService:IsLoaded(player) -> boolean` | |
| `DataService:CanWrite(player) -> boolean` | `Ready` or `Memory` (the write gate) |
| `DataService:WaitLoaded(player, timeout?) -> PlayerData?` | nil on leave / timeout |
| `DataService:Mode() -> "DataStore" \| "Memory" \| "Broken"` | |
| `DataService:SaveSoon(player) -> seq` | coalesced save respecting the gap (rare catches, Stage 4 theft both sides, Stage 5 purchases) |
| `DataService:CommittedSeq(player) -> seq` / `DataService.Committed` | Signal `(player, seq)` after a commit whose snapshot included every `SaveSoon` up to `seq` (incl. the release save) |
| `DataService:OnSerialize(fn: (player, data) -> skipUid?)` | one hook (TankService registers it); runs inside the save transform, must not yield |
| `DataService.Token`, `DataService.StoreName` | read-only, for tests |
| `DataService._debugSizes()`, `_recordFor(player)`, `_saveRecordForTest(rec)` | test hooks (sizes of records / queues / lastRequest; drive an old record's save) |

**Field ownership.** Gameplay services own their own fields of the live table:

- EconomyService: `Money`, `Stats.Earned`, `Stats.Spent`.
- TankService: `Tank`, `TankSlots`, `NextUid`, `Stats.Sold`.
- FishingService: `RodId`, `Stats.Caught`, `Stats.Species`.

They mutate it synchronously behind `CanWrite`; DataService serializes whatever is there.

**SaveSoon on rare moments** (B-29): a Legendary or Mythic catch, Stage 4 theft (both sides), Stage 5
purchases. With coalescing and the gap, that is ≤ 10 writes/min/player, against a server budget of
60 + 40 × players.

### 2.3 Keys, names, versions

`DataConfig`: `StoreName = "PlayerData"`, `StudioSuffix = "_Studio"`, `KeyPrefix = "Player_"`,
`Version = 1`. The version lives inside the value, so migrations never need a new store.

**Rule for the first real migration (v2), written into the DataService header:** when `Migrate` changes
`V`, write the raw pre-migration value once with `SetAsync` to `PlayerData_Backup / Player_<id>_v<old>`
(B-29). There is nothing to migrate in v1.

**README note:** when bumping `Version`, publish with "Migrate to latest update". Otherwise a player kicked
by an old server can be matched into another old server.

---

## 3. Economy

### 3.1 Config modules (all balance numbers live here)

Every timing knob stays on **its own line**, so the tests' source-patch helper (`boot(t, patches)`,
`stage2_fishing.test.luau:61`) can shrink it per test (B-28).

`src/ReplicatedStorage/Shared/Config/EconomyConfig.luau` (pure):

```lua
StartMoney = 0,
MaxMoney = 1e15,           -- exact-integer range; AddMoney clamps (+ one warn)
IncomeTick = 1,            -- s between server credits
MaxCatchUp = 3,            -- at most this many ticks credited per wake (a hitch never becomes a lump sum)
IncomeScale = 1,           -- × FishConfig/FishData Income (Stage 5 tuning knob)
SellScalePct = 100,        -- × the sale value only (Stage 5 knob; FishConfig Value stays what the card shows)
HomeRatePct = 100,         -- selling from the panel anywhere
MarketRatePct = 150,       -- every «ПРОДАТЬ РЫБУ» stall (hub market + 4 bridge kiosks)
MarketDwell = 2,           -- consecutive 1 Hz server samples in range before the stall rate applies (or a held stall prompt)
MarketJump = { SpeedFactor = 2, Slack = 8, Penalty = 5 }, -- a jump (> WalkSpeed·dt·2 + 8) or a new character: 5 more samples
SellPoints = {             -- the server picks a point within Range of its sampled HumanoidRootPart position
  { Id = "Market", Path = "Map.Hub.FishMarket.Scales.SellPromptAttachment", Name = "Рыбный рынок", Range = 12, Word = true },
  { Id = "Kiosk1", Path = "Map.Bridges.Bridge_1.Lookout.SellKiosk.Scales.SellPromptAttachment", Name = "Ларёк", Range = 12 },
  -- Kiosk2..Kiosk4: Bridge_2..Bridge_4, the same
},
Prompt = { Action = "Продать рыбу", HoldDuration = 0.25, MaxDistance = 10, Slack = 4 },
Format = { ShortFrom = 1e6 },  -- below: «$12 345»; from 1e6: «$1.23M», «$12.3M», «$123M», B, T, Qa
Leaderstats = { Money = "Деньги", Income = "Доход/с" },
Milestones = { 1000, 10000, 100000, 1000000 },   -- (P2) one toast each, ever
```

`src/ReplicatedStorage/Shared/Config/TankConfig.luau` (pure):

```lua
StartSlots = 6, MaxSlots = 12,
Growth = { Cap = 3, Time = 300 },          -- ×1 → ×3 linear over 300 s of tank time
ConfirmTime = 3,                           -- two-tap window, s (every sale)
ConfirmArm = 0.4,                          -- a second tap earlier than this is ignored (double-tap guard)
Requests = { Burst = 6, Rate = 3 },        -- token bucket per player: TankSell, prompts, Denied replies
Display = {                                 -- client visuals (§5)
  Fit = 5.2, MaxScale = 1.6, Yaw = 18,     -- longest side in a 6.2 display; scale cap; turn to the aisle, deg
  Range = 180, DropRange = 210,            -- build within 180 studs, tear down beyond 210 (hysteresis)
  BuildPerCheck = 3,                       -- at most 3 fish models built per check
  LifeRange = 70, TagRange = 45, SignRange = 160, EventRange = 120,
  CheckEvery = 0.5, GlassOccupied = 0.8,
},
Pier = { Range = 40, PopRange = 30, PopEvery = 5 },   -- the bucket word (MaxDistance), income pops near the bucket
Panel = { RowsTall = 2, TallFrom = 600, Tick = 1, WideCard = 150 },  -- 2 rows when HUD ≥ 600 px; «ПРОДАТЬ» on cards ≥ 150 px
Texts = { … all Russian strings of §6.9 … },
```

`src/ReplicatedStorage/Shared/Config/DataConfig.luau` (pure):

```lua
StoreName = "PlayerData", StudioSuffix = "_Studio", KeyPrefix = "Player_", Version = 1,
AutoSave = 60,
MinWriteGap = 6,
GapEpsilon = 0.05,               -- s added to the gap (the sim's clock is a sum of 1/60 steps)
LockStale = 150,                 -- 2.5 × AutoSave; boot assert AutoSave < LockStale
LockWait = { Tries = 4, Every = 6 },
LeaveSaveWindow = 15,            -- s; boot assert LeaveSaveWindow + MinWriteGap < Tries × Every (21 < 24)
Retry = { Load = 5, Save = 2, Close = 2, Base = 1, Max = 8 },
CloseBudget = 25,
ProbeTimeout = 5,
BudgetMin = 5, BudgetDelay = 10,
Texts = {
  LoadFailed = "Не получилось загрузить твой прогресс — серверы Roblox заняты. Зайди ещё раз через минуту!",
  TooNew = "Игра обновилась — перезайди, чтобы продолжить.",
  Stolen = "Ты зашёл в игру на другом сервере — здесь эта игра закрыта.",
  MemoryWarn = "<the Output warn of §2.2>",
  MemoryToast = "💾 Studio: прогресс не сохраняется",
},
```

`FishConfig` gains `ShortName` per fish (K-6), in sentence case; cards upper-case it with `TextUtil.upper`:

| fish | `ShortName` |
|---|---|
| Карасик | «Карасик» |
| Окунь-полосатик | «Окунь» |
| Фугу-пуфик | «Фугу» |
| Меч-рыба | «Меч-рыба» |
| Акулёнок | «Акулёнок» |
| Рыба-дракон | «Дракон» |

`FishingConfig.Texts.Denied` gains `loading = "Загружаем твой садок…"`.

### 3.2 Pure rules (`src/ReplicatedStorage/Shared/TankRules.luau`, shared by server and client)

```
Growth(age)                       = 1 + (Cap − 1) · clamp(age / Time, 0, 1)
CurrentValue(value, age)          = floor(value · Growth(age) · SellScalePct / 100)
SellPrice(value, age, ratePct)    = max(1, CurrentValue(value, age) · ratePct // 100)      -- integer percents (B-19)
IsMaxed(age)                      = age ≥ Time
Income10(income)                  = round(income · IncomeScale · 10)                         -- integer tenths
ChooseReplacement(list, newIncome10) -> uid?   -- §1.2 rule (skips Locked and Dormant)
FormatMoney(n)                    → "$0", "$1 234", "$999 999", "$1.23M", "$12.3M", "$123M", "$1.23B", … "Qa"
                                    (NaN/inf → "$0": FormatCoins' string.format("%d") errors on them, B-20)
FormatRate(income10)              → "+$0.8/с", "+$4/с", "+$42/с", "+$1 234/с", "+$1.2M/с"  (1 decimal below 10)
AttrTime(t)                       = if t % 1 == 0 then t + 1/1024 else t                    -- (B-16, see §4.6)
```

`FormatMoney` reuses `FishingRules.FormatCoins` for the grouped part. All money is integer; only the
rate has a decimal (a dot, like «M»). The client and the server run the same code on the same inputs, so
the panel's price and the server's price agree to the coin, apart from network latency on the age.

### 3.3 Income, growth, rounding (server)

**The tick loop** (B-17, B-19):

- One `task.spawn` loop in TankService runs `dt = task.wait(IncomeTick)`, then a **fixed-step
  accumulator**: `acc += dt; n = floor(acc / IncomeTick); acc −= n · IncomeTick; n = min(n, MaxCatchUp)`.
- It iterates **TankService's runtime records**, not `Players:GetPlayers()`, and takes only those that are
  mounted (have a base) and pass `CanWrite`. That way nothing is credited after the final-save snapshot.
  For each:
  - `carry10 += n · rec.Income10Sum`; `whole = carry10 // 10`; `carry10 −= whole · 10`.
  - `EconomyService:AddMoney(player, whole, "income")` when `whole > 0`.
  - `MarketService:Sample(player)` (§4.4); the `SellRatePct` / `SellPlace` attributes are written on
    change only.
- Each player's step runs in `xpcall`, with a rate-limited `warn`. The loop itself sits outside every
  pcall, so one bad record never ends it for everyone.
- Nothing in the tick yields: no `WaitForChild`; the HRP is read with `FindFirstChild`.

**Ages** (B-18):

- Per mounted fish, `ageNow = min(Time, workspace:GetServerTimeNow() − GrowFrom)`, the same formula and
  clock as the client.
- The tick refreshes `rec.Age` for saving, and the serialize hook refreshes it again inside the transform.
- A sale uses `ageNow` at the sale moment.
- Unmount freezes `rec.Age`; mount sets `GrowFrom = now − rec.Age`.
- No base (queue) → no income, no growth.

**Income per player** (`Income10Sum`) is recomputed only when the tank changes. The attributes `Income`
(Player and Tank model) and the leaderstats «Доход/с» (rounded) are written on change, not per tick.

**Sale:** `price = TankRules.SellPrice(f.Value, ageNow, MarketService:RatePct(player))`, server-side only.

**Cost** (B-21): 8 players × 12 fish is ≈ 20–50 µs of Luau and ≈ 16 small replicated changes per second
server-wide. Do not optimize. Keep `MoneyChanged` handlers trivial, so Stage 5 badges do no work per tick.

### 3.4 Per-species numbers (base rod; size factor 0.8–1.5; × mutation 2 / 3 / 5)

| Fish | Rarity | sale value (×1) | income $/s | maxed ×3 | earns its value in | earns its maxed value in |
|---|---|---|---|---|---|---|
| Карасик | Common | 8–15 | 0.8–1.5 | 24–45 | ≈ 10 s | ≈ 30 s |
| Окунь-полосатик | Common | 12–23 | 1.2–2.3 | 36–69 | ≈ 10 s | ≈ 30 s |
| Фугу-пуфик | Rare | 36–68 | 3.2–6 | 108–204 | ≈ 11 s | ≈ 34 s |
| Меч-рыба | Epic | 112–210 | 9.6–18 | 336–630 | ≈ 12 s | ≈ 35 s |
| Акулёнок | Legendary | 360–675 | 32–60 | 1 080–2 025 | ≈ 11 s | ≈ 34 s |
| Рыба-дракон | Mythic | 1 440–2 700 | 120–225 | 4 320–8 100 | ≈ 12 s | ≈ 36 s |

Income is the engine. Selling means "make room" (automatic), a Stage 4 bank, or Stage 5 cash (D16). A
maxed Mythic at a stall ≈ $12K is also the Stage 4 theft prize.

### 3.5 First 30 minutes, simulated with the real numbers

**The model.** Monte-Carlo, 1000 runs:

- the real FishConfig weights, sizes and mutations, and the FishingConfig timings;
- the kid's hit chances, 92 % → 72 %, and the card times;
- 75 % of the time spent fishing;
- 6 slots, growth ×3 over 300 s, the full-tank rule, whole-coin crediting.

The scripts are `scratchpad/stage3/design_sim/econ_design.py` and `scratchpad/stage3/critique_sim/outcomes.py`.

| min | money p10 / **median** / p90 | **$/s** (median) | tank | caught | tank value now: home ×1 / stall ×1.5 |
|---|---|---|---|---|---|
| 1 | 94 / **235** / 880 | **9** | 3/6 | 3 | 116 / 174 |
| 2 | 614 / **1 220** / 4 258 | **22** | 6/6 | 7 | 326 / 489 |
| 3 | 1 630 / **3 032** / 8 820 | **33** | 6/6 | 10 | 574 / 861 |
| 4 | 3 022 / **5 594** / 15 197 | **44** | 6/6 | 14 | 864 / 1 296 |
| 5 | 4 808 / **8 787** / 22 556 | **54** | 6/6 | 17 | 1 202 / 1 803 |
| 6 | 6 899 / **12 883** / 31 831 | **66** | 6/6 | 21 | 1 577 / 2 365 |
| 7 | 9 294 / **17 366** / 43 172 | **74** | 6/6 | 24 | 1 892 / 2 838 |
| 8 | 12 062 / **22 483** / 53 899 | **84** | 6/6 | 28 | 2 215 / 3 322 |
| 9 | 15 164 / **28 186** / 66 413 | **90** | 6/6 | 31 | 2 490 / 3 735 |
| 10 | 18 522 / **34 329** / 79 541 | **99** | 6/6 | 35 | 2 783 / 4 174 |
| 15 | 39 462 / **72 161** / 155 427 | **140** | 6/6 | 52 | 4 301 / 6 451 |
| 20 | 68 399 / **123 324** / 253 032 | **173** | 6/6 | 70 | 5 373 / 8 059 |
| 30 | 149 159 / **251 341** / 474 589 | **248** | 6/6 | 105 | 7 791 / 11 686 |

What each catch does (median):

| minute | 2 | 3 | 4 | 5 | 6 | 10 | 15 | 20 | 30 |
|---|---|---|---|---|---|---|---|---|---|
| sold on the spot | 4 % | 33 % | 52 % | — | 69 % | 82 % | 88 % | — | 93 % |
| replaces a fish | — | 63 % | — | 37 % | — | 18 % | — | 9 % | — |

Beats (median):

- the first catch at **0:15** (money starts ticking);
- the tank is full at **1:41**;
- the first Epic+ at **1:55**;
- the first fish at «МАКС» at **5:38**;
- the first Legendary+ at **6:26**;
- a Mythic by 15 min in 38 % of runs.

Replacements run about one a minute in minutes 3–10 and one every ≈ 2.5 min in minutes 10–20.

**Stage 5 note** (R9):

- The median player has $34K at 10 min and $250K at 30 min, so Stage 5 prices (slots, rods ×2–3 of
  RodConfig today, the lock) must be set against this table, or `IncomeScale` lowered.
- With Value ≈ 10–12 × Income, selling one maxed fish buys about 5 s of a 6-fish tank's income.
- `SellScalePct` and `Growth.Cap` decide whether selling ever helps.

---

## 4. Server: modules, remotes, attributes

### 4.1 Services and boot order

`Main.server.luau` `ORDER = { "MapService", "BaseService", "DataService", "EconomyService",
"MarketService", "FishingService", "TankService" }`.

| module | owns | requires |
|---|---|---|
| `Lib/PlayerData` (new, pure) | schema v1, template, reconcile, migrate, sanitize, serialize, ledger | configs, FishingRules |
| `DataService` (new) | the DataStore, lock, queue, autosave scheduler, close, memory/broken mode, commit seq | PlayerData, DataConfig |
| `EconomyService` (new) | **the only writer of Money**; leaderstats; attributes `Money`, `Income`; the ledger | DataService |
| `MarketService` (new) | sell-point prompts, the 1 Hz position samples (dwell), `RatePct(player)` | EconomyConfig |
| `FishingService` (changed) | catch sink, cast denied while loading, rod from data, fishing stats | BaseService, DataService |
| `TankService` (new) | fish in tanks, slots, dormancy, the full-tank rule, selling, the income tick, slot/tank attributes, labels and light bars, the tank prompt, the tank remotes, the serialize hook | BaseService, DataService, EconomyService, FishingService, MarketService, TankRules |

Every new script starts with a Russian header: what it does, its API, attributes and remotes, like the
existing services. Every per-player thing lives in a Trove cleaned on leave, and per-player maps are keyed
by `Player` with an identity check (B-3). No unbounded lists. DataService, TankService, EconomyService and
MarketService each expose `_debugSizes()` (B-27).

**Stub tolerance.** Client tests and the preview stub sim replace services with `return {}`.

- TankService calls `FishingService.SetCatchSink` only `if type(FishingService.SetCatchSink) == "function"`.
- FishingService uses DataService only through `DataService.Loaded`, `Get` and `CanWrite`, each behind a
  `type(...) == "function"` check.
- Main already skips missing `Init`/`Start`.

### 4.2 FishingService changes (small, `src/ServerScriptService/Services/FishingService.luau`)

1. `FishingService.SetCatchSink(fn: (player, fish) -> TankResult?)`, stored in a local.
2. `castProblem` (:597), after the `nobase` check:
   `if type(DataService.CanWrite) == "function" and not DataService:CanWrite(player) then return "loading" end`
   (B-12). The text comes from `FishingConfig.Texts.Denied.loading`.
3. `catch()` (:483): after `state.Caught += 1` and the attribute, before `broadcastFx`/`endSession`:
   - `local sent = table.clone(fish)`;
   - if `CanWrite`: `Stats.Caught += 1`; `prev = Stats.Species[fish.Id]`;
     `Stats.Species[fish.Id] = (prev or 0) + 1`; `sent.New = prev == nil`;
   - `local tank = sink and sink(player, fish)` (synchronous, never yields; `nil` when the sink refuses);
     `sent.Uid = tank and tank.Uid`;
   - `endSession(player, state, "Caught", { Fish = sent, Total = state.Caught, Tank = tank })`;
   - a Legendary or Mythic → `DataService:SaveSoon(player)`.
4. Rod: on `DataService.Loaded(player, data)`, the runtime rod is `data.RodId` if RodConfig knows it, else
   `StartRod`; the saved `RodId` is never rewritten here. `SetRod` writes `data.RodId` (behind `CanWrite`);
   Stage 5 calls only `SetRod`.
5. `state.Catch` keeps at most the last 50 fish (`GetCatch` stays for Stage 2 tests; no unbounded list).
6. A full tank never blocks fishing; "loading" is the only new denial reason.

### 4.3 TankService (`src/ServerScriptService/Services/TankService.luau`)

Runtime per player (keyed by `Player`):
`{ Player, Data, Fish = { [uid] = { Rec = <the Tank entry>, Value, Income10, Rarity, GrowFrom, Locked, Dormant } },
Base?, Mounted, Income10Sum, Carry10, Bucket }`.

- **Init.**
  - For every base, resolve the `Tank.Slots.Slot_1..12` refs: `Pedestal`, `Display`,
    `Display.FishPoint`, `Pedestal.LabelGui.Label`, and `LightBar` with its SurfaceLight. Missing refs
    are loud errors.
  - Create `ProximityPrompt "TankPrompt"` under `Tank.Glass.PromptAttachment`: ActionText «Открыть»,
    ObjectText «Садок», HoldDuration 0, MaxActivationDistance 10, RequiresLineOfSight false, Enabled false.
  - Register `DataService:OnSerialize`. It refreshes the mounted ages and returns the Stage 4
    escrow-skip function (none in Stage 3).
- **Build the runtime** on `DataService.Loaded`. Each fish gets `Rarity`, `Value` and `Income10` from
  `FishingRules.Price`. A fish is **Dormant** when its Id is unknown or it has no valid unique slot ≤
  `min(TankSlots, MaxSlots)` (§2.1).
- **Mount**, when the player is loaded AND has a base, whichever comes second (also `BaseAssigned`):
  - write the slot attributes, labels and light bars for slots 1..12 (§5.2) with `Event = "<n>|mount|"`;
  - set `GrowFrom = serverNow − Age` per active fish;
  - write the Tank model attributes and the Player attributes, and enable the prompt.
- **Unmount** (`BaseReleased`, PlayerRemoving):
  - freeze every `rec.Age`;
  - set every slot back to `empty` / «Пусто» / the default look, with all fish attributes `nil`;
  - clear the Tank attributes and disable the prompt.
- **Catch sink** `(player, fish) -> TankResult?` → `nil` unless `CanWrite` and mounted (casting is denied
  before the load, so this is only a shutdown or leave race); else `AddFish(player, fish, "catch")`.
- **`AddFish(player, fish, reason)`**, synchronous, behind `CanWrite`:
  1. Compute first: `Uid = PlayerData.NewUid(data)`, the §1.2 decision, the prices.
  2. Commit: `data.Tank` → runtime → `EconomyService:AddMoney(…, "autosell")` for "replaced"/"sold" →
     `Stats.Sold += 1` → slot attributes (with `Event`) → income → attributes → `FishAdded`/`FishRemoved`.
  3. Return `{ Result, Slot?, Uid?, Count, Slots, Replaced? = { Uid, Id, Rarity, Mutation?, Price }, Price?, First? }`.
     `First = true` when `Stats.Caught == 1`: the client's one-time toast and the onboarding «!».
  - A fish added outside a catch (Stage 4 steal) also sends `TankEvent("Stored", result + { Fish })`.
- **Sell** (`TankSell(uid)`): see §4.5. Check, then mutate with no yield: find the fish, compute `ageNow`
  and the price, remove it from `data.Tank` (dense) and the runtime, `AddMoney`, stats, the slot
  (`State = "empty"`, fish fields nil, `Event "sold"`), income, `TankEvent("Sold", …)`, `FishRemoved`.
- **Prompt** `Triggered(player)` goes through the same token bucket (B-23). Only the owner of this base,
  after a server distance re-check ≤ MaxActivationDistance + 4, gets
  `TankEvent("Open", { Place = "Tank", RatePct = SellRatePct attr, Name = "Садок" })`.

### 4.4 EconomyService and MarketService

EconomyService: on PlayerAdded create `leaderstats` (`IntValue` «Деньги», `IntValue` «Доход/с»); on
`DataService.Loaded` publish `Money` and check the ledger. API:

| function | what |
|---|---|
| `GetMoney(player) -> number` | |
| `AddMoney(player, amount, reason) -> boolean` | integer, finite, > 0, and `CanWrite`, else `false` + `warn` (callers already checked, so `false` is a bug); clamps at `MaxMoney` (excess → one warn); updates data, `Stats.Earned`, attribute `Money`, leaderstats; fires `MoneyChanged` |
| `SpendMoney(player, amount, reason) -> boolean` | Stage 5 (implemented + tested now); writes `Stats.Spent` |
| `CanAfford(player, amount) -> boolean` | |
| `SetIncome(player, income10)` | called by TankService; attribute `Income` (`income10 / 10`), leaderstats rounded |
| `MoneyChanged` | Signal `(player, money, delta, reason)` — handlers stay trivial |
| `SetMoneyForTest(player, n)` | test hook; moves `Earned`/`Spent` too, so the ledger holds |

MarketService:

- **Start.** For each `EconomyConfig.SellPoints` entry found by its path (a missing one → one warn, then
  skip), create `ProximityPrompt "SellPrompt"`: ActionText «Продать рыбу», ObjectText «Рыбный рынок ·
  +50%» / «Ларёк · +50%», HoldDuration 0.25, MaxActivationDistance 10, RequiresLineOfSight false.
- **`Sample(player)`**, called from TankService's 1 Hz tick (B-22):
  - Read the HRP position with `FindFirstChild`.
  - Horizontal displacement `> WalkSpeed × dt × 2 + 8` studs since the last sample (a teleport; a jump
    or a fall from a roof does not count), or a new character (no last sample) → `hold =
    MarketJump.Penalty` (5): the stall rate waits that many more clean samples, each one `hold −= 1`
    (fix BE-02: resetting the dwell alone cost a teleport nothing, since a jump into a stall's Range
    always changes the point too). A legitimate teleport (join, Home, respawn) puts the
    player at their base, more than 5 s of walking from any stall, so no exemptions are needed.
  - In `Range` of a point → `dwell += 1`, else `dwell = 0`.
  - `SellRatePct = (dwell ≥ MarketDwell and hold = 0 and still in range) and MarketRatePct or HomeRatePct`; write
    `SellRatePct` / `SellPlace` on change.
- **`RatePct(player) -> ratePct, pointId?`** returns the sampled state plus a live in-range check of the
  same point. It never yields.
- **`Triggered(player)`** runs through the token bucket, then a distance re-check. The hold of the prompt
  counts as the dwell (fix UX-05): in the point's `Range`, `hold = 0` and no jump since the last sample (the
  same measure; the trigger moves neither the sample position nor the hold, so prompt spam cannot soften
  either) → `SellRatePct = MarketRatePct` is written **before** the answer, so the panel opens with the
  market prices instead of ×1 for the first second (a jump → `hold = Penalty`, ×1). Then
  `TankEvent("Open", { Place = point.Id, RatePct = current, Name })`. This only opens the UI; the rate at
  the sale moment is decided by `RatePct`.

### 4.5 Remotes (add to `RemoteNames.Events` + the header protocol)

| name | dir | payload | validation / limits (in this order) |
|---|---|---|---|
| `TankSell` | C→S | `(uid: string)` | 1) `typeof == "string"`, matches `^f%d+$`, `#uid ≤ 12` (else silent drop); 2) the token bucket per player, `Burst 6 / Rate 3/s`. Every reply, `Denied` included, comes out of the same bucket (B-23); an empty bucket → silent drop. 3) `CanWrite` (else `Denied loading`). 4) A mounted base (else `Denied nobase`). 5) The fish is active in **this player's** tank (else `Denied missing`; this also covers the double-tap and race cases). 6) Not `Locked` (Stage 4, `Denied locked`). 7) Price and rate are computed server-side; a non-finite price → `warn`, no mutation. |
| `TankEvent` | S→C | `(kind: string, data: table)` | — |
| `FishingState "Caught"` (existing) | S→C | `{ Fish: FishData + Uid? + New?, Total, Tank: TankResult? }` | — |

`TankEvent` kinds:

| kind | data |
|---|---|
| `"Open"` | `{ Place: "Tank" \| "Market" \| "Kiosk1".."Kiosk4", RatePct: number, Name: string }`: a prompt opened the panel |
| `"Sold"` | `{ Items = { { Uid, Id, Rarity, Mutation?, Price } }, Amount, RatePct, Place: string? }`: one item in Stage 3; a list, so a later sell-all needs no new kind |
| `"Stored"` | `TankResult + { Fish }`: a fish added outside the Caught payload (Stage 4 steal) |
| `"Denied"` | `{ Reason: "loading" \| "nobase" \| "missing" \| "locked", Text }` |

`TankResult = { Result: "stored" | "replaced" | "sold", Slot?, Uid?, Count, Slots,
Replaced? = { Uid, Id, Rarity, Mutation?, Price }, Price?, First? }`. A missing `Tank` in "Caught" means
the sink refused: the client plays the card and flies home without a chip change.

Never `InvokeClient`; no RemoteFunctions. Clients never send amounts, prices, slots or fish data.
**No yields between the check and the mutation in any handler**: no `WaitForChild`, and no `RateAt` that
waits for a character.

### 4.6 Replicated state (what clients read)

**Player attributes:**

- `Money` (int) and `Income` ($/s, 1 decimal).
- `TankCount` (active fish) and `TankSlots` (mounted: `min(TankSlots, MaxSlots)`).
- `SellRatePct` (100 / 150) and `SellPlace` ("" / "Market" / "Kiosk1".."Kiosk4").
- `DataMode`: "Loading" / "Ready" / "Memory"; Broken shows as "Memory".
- The existing `FishCaught`, `RodId`, … are unchanged.

**leaderstats:** «Деньги», «Доход/с» (IntValue).

**Tank model** (`Base_N.Tank`): `Count`, `Slots`, `Income`, written on change. They are public, so Stage 4
thieves see a rich tank.

**Slot model** (`Base_N.Tank.Slots.Slot_K`), written only on change (B-26):

- **`State`**: "empty" | "fish" | "locked"; an unowned base is all "empty".
- **Fish fields**, with `State = "fish"`:
  - `FishUid`, `FishId`, `Rarity`, `Mutation` (absent = none or unknown), `Kg`;
  - `Value` (base, ×1) and `Income` (`Income10 / 10`);
  - `GrowFrom` = `AttrTime(workspace:GetServerTimeNow() − Age)`. The client value is
    `TankRules.CurrentValue(Value, GetServerTimeNow() − GrowFrom)`.
- **`Event`**: `"<n>|in|<FishId>"`, `"<n>|mount|"` (a mount: no splash, no toast), `"<n>|sold|<price>"`,
  `"<n>|swap|<price>"` (replaced), and Stage 4's `"<n>|stolen|"`.

**Write order and refresh contract** (B-26):

- The server writes the fish fields first, then `State`, then **`Event` last**.
- An `empty` or `locked` slot gets every fish attribute set to `nil`, so no stale `FishId`/`Value` can be
  read.
- `n` is **monotonic per base for the server's lifetime**, never reset on unmount. Otherwise a new owner's
  first event could repeat the old string and `AttributeChanged` would not fire.
- Only one `Event` per slot per frame reaches clients (replication sends the last value). That is why
  combined kinds like `swap` exist, and why Stage 4 adds `stolen` as **one** event, not `sold` + `in`.
- Clients refresh a slot **only** on `Event`, with one coalesced `task.defer` per slot that re-reads every
  field, plus one initial read when they build a base. A swap keeps `State = "fish"` while `FishUid`
  changes, so a client keyed on `State` would miss it.
- These attributes require `StreamingEnabled = false`, which is pinned in `tools/build.luau:82`. Note it in
  the TankPanelController and TankWorldController headers.

**Time attributes and the float32 sim trap** (B-16, verified by the critic in `critique_probe/attr.luau`).
Lune stores **whole-number** attribute values as float32: `1700000123` reads back as `1700000128`, while
`1700000123.5` is exact. A mount on a whole-second sim frame would therefore get a `GrowFrom` off by up to
±64 s. So every time-valued attribute is written through `TankRules.AttrTime` (+1/1024 s on whole
numbers; dyadic, exact in a double). The header says this is a Lune artefact; in production the added
error is < 1 ms. Money stays < 2^24 in tests, or the tests read the leaderstats IntValue (exact).
Production attributes are doubles.

### 4.7 Security summary (for the reviewer)

- **Money.** A single money writer (`AddMoney`/`SpendMoney`: integer, finite, > 0, clamped, behind
  `CanWrite`) and a ledger check on load.
- **Prices.** Recomputed server-side from FishConfig, with integer percents.
- **Fish.** A `Uid` per fish with a strict pattern, so double sells are no-ops.
- **Mutations.** Check-then-mutate without yields, compute-before-commit and a fixed commit order.
- **Rate limits.** A token bucket on every tank remote, every prompt and every `Denied` reply.
- **Ownership.** The tank prompt answers only its owner.
- **Stall rate.** From the server's own position samples: a dwell (2 samples, or a held stall prompt) and a
  displacement check (a teleport or a new character holds the stall rate for 5 more samples, the prompt
  included); Stage 4
  cannot "sell to dodge" (`Locked`).
- **Saves.** Sanitized, rolling-update-safe loads and a validating serializer. A per-load session lock
  with strict ownership guards against dupes and stale overwrites.
- **Time.** No client-trusted time.

### 4.8 Hooks for Stage 4 and Stage 5

| stage | needs | Stage 3 provides |
|---|---|---|
| 4 theft | take a fish by uid, give it to the thief | `TankService:RemoveFish(owner, uid, reason) -> fishRecord?` and `TankService:AddFish(thief, fish, "stolen")` (the same full-tank rule; a non-catch keeps `fish.Origin`, a string ≤ `Limits.OriginMax`, fix BE-03), both `nil` unless `CanWrite` of that player; signals `FishAdded`/`FishRemoved (player, fish, reason)`; slot `Event "stolen"` (one event) |
| 4 theft | no "sell to dodge" during a steal hold | `TankService:SetLocked(owner, uid, bool)`: sells answer `Denied locked`, and the fish is never auto-replaced |
| 4 theft | per-slot steal prompts | `Pedestal.PromptAttachment` (unused by Stage 3); slot attributes already public |
| 4 dupes | never duplicate a fish across two keys | `SaveSoon -> seq`, `CommittedSeq`, `Committed`, `OnSerialize` skip-uid, per-load lock, `Origin` field (B-24) |
| 4 lock/shield | level saved | `LockLevel`, `Upgrades` in schema v1 |
| 4 shield UI | a timer spot that does not reshuffle the HUD | a glass chip at the right end of `Status.BaseBadge` (§6.7) |
| 5 shop | spend | `EconomyService:SpendMoney`, `CanAfford`, `Stats.Spent` |
| 5 slots | raise slots | `TankService:SetSlots(player, n)` (unlocks the next displays, attributes and labels; restores dormant known fish into the new slots) |
| 5 rods | change rod | `FishingService:SetRod` (writes `RodId`) |
| 5 cash-out | make selling matter | `SellScalePct`, `Growth.Cap`; `TankEvent "Sold"` already carries `Items` (a sell-all can come back at the market) |
| 5 UI | sheet + teaser | `gui/Sheet.luau` + client `Sheet` helper (the shop reuses them), the locked card in the panel, the free 3rd slot in the right column |

**Stage 4 theft protocol** (B-24), written here so nobody improvises it:

1. `RemoveFish(victim, uid)` → `seqV = DataService:SaveSoon(victim)`.
2. `AddFish(thief, fish, "stolen")`: a new Uid from the thief's counter, `Origin = "<victimUserId>:<uid>"`,
   and a runtime `Escrow = { victim, seqV }`. While escrowed, the fish cannot be sold and the
   `OnSerialize` hook skips it.
3. When `Committed(victim) ≥ seqV`, clear the escrow and call `SaveSoon(thief)`.
4. If the victim's save never commits (a lost lock), the escrowed fish is dropped when the thief leaves.

The worst case is one lost fish, never a duplicate. Two fish with the same `Origin` in one tank → keep one.

---

## 5. World

### 5.1 Placement (court + pier bucket — D1)

**The court.** Fish live in the display aquariums `Tank.Slots.Slot_1..12`: base-local x ±33.5,
z 60.5…115.5, filled in `SlotIndex` order. The big show tank stays decorative and carries the tank-wide
prompt and sign.

**The pier intake.** `Platform.Bucket` (`BaseTemplate.luau:2670`, a wooden bucket with a fish tail
5.6 studs beside `FishingSpot`) carries the client-side «садок» word (§5.3).

**No new parts in the template** (4 spare per base): everything is attributes, property changes, GUI and
client clones.

### 5.2 Server look per slot (TankService, written on change)

| State | Pedestal label | LightBar | Display |
|---|---|---|---|
| empty (or unowned base) | «Пусто» (as today; stage1 test) | template look (`AquaGlow` Neon, light on) | template (T 0.66) |
| fish | fish name «Окунь-полосатик», `TextColor3` = rarity flat colour (FishConfig) | `Color` = rarity colour (`UIConfig.Rarity[r].Bottom`; Mythic: `UIConfig.Rainbow[6]`), light on | `Transparency = Display.GlassOccupied` 0.8 (mutation colours read through the glass) |
| locked | «🔒 Закрыто» | `Material = SmoothPlastic`, `Color = Slate.Bottom`, SurfaceLight off | template |

### 5.3 Client: `TankWorldController` (+ helper module `TankDisplay`)

- **Range, with hysteresis and a build cap** (K-15). A 0.5 s `task.delay` chain (no connection) measures
  from the camera.
  - Bases whose `Tank.Glass` is within `Display.Range` (180) get their display fish built, at most
    `BuildPerCheck` (3) models per check.
  - Bases farther than `DropRange` (210) are torn down (one Trove per base).
  - Building a base reads every slot once; after that, slots refresh only on `Event` (§4.6).
- **Fish model.**
  - Clone `ReplicatedStorage.Assets.Fish[FishId][Mutation or "Normal"]`; an unknown mutation uses
    "Normal". Scale by `min(MaxScale 1.6, Fit 5.2 / longest side)`.
  - **Centre the bounding box** on `Display.FishPoint` (the Body is up to 0.88 off-centre).
  - Head along the slot's local ±X (alternate by `SlotIndex % 4 < 2`), yawed 18° toward the aisle.
  - CanCollide, CanQuery, CanTouch and CastShadow are all false.
  - Keep the attributes `FishId, Rarity, Mutation, Kg, Value`; the rainbow animator works for free via the
    tag `RainbowFish`.
  - Weld all parts to the anchored `Body` (one assembly).
- **Calm life on looped tweens only (no per-frame Lua).** Within `LifeRange` 70 studs, one root CFrame
  tween: bob ±0.12 stud and yaw ±6°, Sine InOut, 2.4–3.2 s, `Reverses`, `RepeatCount −1`, random phase.
  Beyond 70 studs the tweens are cancelled (static fish). The fish never flops. *(P2: a tail wag on the
  tail weld's `C0`, K-16.)*
- **Slot tag** `FxTankTag`:
  - A BillboardGui on an Attachment at `FishPoint + (0, Tag.Lift 3.3, −Tag.Forward 3.6)` in the display's
    axes: in FRONT of the glass at the height of its LightBar (from the aisle the view never goes through
    the glass, which hides billboards behind it; the bar runs between the two lines like a rule), under
    the arcade ceiling at 13.15.
  - 5.6 × 1.9 studs + 44 × 16 px, `MaxDistance` `TagShow` 28 (further the aisle's tags blur into mush),
    LightInfluence 0, AlwaysOnTop false.
  - **Letters capped in pixels** (ART-02): up close the tag grows with the world but its letters do not
    (`UITextSizeConstraint`): line 1 is at most `Tag.TextShare` 0.056 of the screen height, clamped to
    `TextMin..TextMax` 16..30 px (never louder than the Wallet's number), line 2 `ValueShare` 0.88 of it;
    both lines hug the middle (the light bar), so a near tag no longer runs into the next one down the
    aisle.
  - Line 1 «+$4/с» in `BillboardGreen`; line 2 «$45» / «$135 МАКС» in `BillboardYellow` (no «▲»: in
    italic Montserrat it fell back to an upright stray glyph; «МАКС» already says the price stopped).
  - STYLE §3 "words in the world": Montserrat Heavy, white → colour Fill, thin dark outline, no plate.
  - Values refresh on one 1 s timer, only for tags within `TagRange` 45 (fresh by the time they show).
- **Locked word** `FxTankLock` (ART-03): a dim Slate «🔒 Закрыто» on the empty glass, lower than the
  aisle tags (`Tag.LockShare`, `LockLift`), `MaxDistance` `LockRange` 80 (seen from the court gate). It
  is shown **once per arcade side**, over the first locked display next to the open rows, and follows
  them when `TankSlots` grows; the other locked displays keep only their pedestal «🔒 Закрыто» and the
  dim Slate LightBar (three identical words in perspective piled into «За🔒рыто»).
- **Tank sign** `FxTankSign`: a BillboardGui over the front edge of `Tank.Glass` (`Sign.Inset` 4 studs in,
  `Sign.Lift` 3 studs above the glass top: just over the frame and lanterns, above the «АКВАРИУМ»
  plaque; from the gate at eye height it sits mid-frame, not in the Wallet's band), MaxDistance 160. It
  shows «+$42/с» big green and «🐠 4/6» small white, from the Tank model attributes, and is hidden on
  unowned bases. Its letters are capped like the tags': «+$42/с» ≤ `Sign.TextShare` 0.08 of the screen
  height (22..44 px), «🐠 4/6» `CountShare` 0.6 of it. (The court income pops are dropped: nobody sees
  them while fishing, K-1/K-16.)
- **Pier word** `FxPierTank` (K-1), **own base only**:
  - A BillboardGui on a client Attachment just over `Platform.Bucket`: studs-sized ≈ 4 × 1.4,
    `MaxDistance` `Pier.Range` 40, LightInfluence 0, AlwaysOnTop false.
  - Line 1 «🐠 4/6» white, line 2 «+$42/с» `BillboardGreen`, from the Player attributes.
  - **Hidden** while `FishingState` is Bite or Reeling, while the HUD has `CounterHold`, and while the own
    character holds `HeldFish` (the toasts' busy flags) — and `Pier.TrophyGap` 0.3 s longer: the
    trophy's nameplate «Карасик 💵 $12» fades out right where the word stands (UX-03).
  - On a stored or replaced arrival (when `CounterHold` clears): one splash `Emit` at the bucket rim
    (within the two-emitter budget) and a punch of the word.
  - **Income pops:** while the own character is within `Pier.PopRange` 30 studs of the bucket, income is
    > 0 and the word is visible, every `PopEvery` 5 s a «+$13» rises 2.5 studs over the word and fades
    (1.2 s tween).
  - No ProximityPrompt at the bucket: a tap target 5 studs from the spot would land on the fishing screen.
- **Slot events** (`Event` attribute, bases within `EventRange` 120):
  - `in`: a splash/sparkle burst (`ParticleEmitter:Emit` on a temporary attachment at the display TOP,
    never inside the glass), a LightBar flash, and the tag pops in.
  - `sold` / `swap`: the fish shrinks to 0 in 0.25 s, gold sparkles, and «+$45» rises.
  - `mount`: a quiet build, with no FX.
  - ≤ 2 emitters alive per player.
- **Clear of the HUD** (ART-01, UX-02): the Wallet uses the same green italic, so a world «+$959/с»
  drawn behind «💵 $0 +$959/с» read as one block. On the same `CheckEvery` chain (and at once when a
  word shows up or a toast arrives, `Clear.ToastWait` 0.2 s later) every visible word — the tags, the
  lock words, the tank sign, the pier word, the market word — is projected (`Camera:WorldToScreenPoint`
  against the HUD's `AbsolutePosition`) and its text rect compared with the plates of `HUD.Status` (the
  base badge; the Wallet by the extent of its row's content) and the toasts in `HUD.Toasts`: closer than
  `Clear.Margin` 12 px → the word fades out in `Fade` 0.15 s; it comes back in `Show` 0.25 s only once it
  is `Back` 18 px away (no flicker at the edge). The pier word under a catch toast fades the same way.
- **Prompts:** hide `TankPrompt` on bases not owned by the local player (client-local `Enabled = false`);
  the server checks ownership anyway.
- **Sell points:** one client BillboardGui word over the hub market, «РЫНОК +50%!» (BillboardYellow),
  MaxDistance 200. The bridge kiosks get only their prompts; their words are P2 (K-16). A `"Sold"` at a
  stall plays a coin burst at its scales.
- **Budget:** fish parts count against `MapConfig.PartBudget.RuntimeReserve.TankFish` 1 920
  (12 × 8 × ≤ 20; in practice only the bases within 180–210 studs exist). No new server parts. The comment
  in MapConfig becomes "client-side display fish within Display.Range".

### 5.4 Engine caveats (verify in renders/Studio)

- Glass with transparency hides particles and billboards behind it, so FX and tags stay above or outside
  the glass.
- The hanging lanterns (z 66/88/110) can occlude displays from court-side cameras (accepted).
- Occupied displays use T 0.8.
- The pier word must not cover the fisher or the bobber in the phone fishing camera; check it in the
  `pier_tank_word` render.

---

## 6. UI («Симулятор», mobile-first)

### 6.1 Widgets and owners (contract names — tests and controllers find them by name)

| widget | built by | driven by |
|---|---|---|
| `HUD.Status.Wallet` (Frame, LayoutOrder 30, replaces `CatchCounter`) → `Money` (`Theme.stat` 💵, `Label` «$0» in `MoneyText`) + `Rate` (italic label «+$42/с», MoneyText); a glass «$…» look while loading | `tools/builder/gui/Hud.luau` | `MoneyController` |
| `HUD.RightButtons.TankButton` (`Theme.simButton` "square", token **`Water`**, Icon 🐠, Caption «САДОК», Tier Small, Size (1, 0.3), LayoutOrder 90, `SimOpts.stroke 5`) → `Count` (Cream chip plate, `Label` «0/6», italic dark text, top-left shoulder), `Badge` (`Theme.badge` «!», hidden; onboarding, K-8) | `Hud.luau` | `TankButtonController` |
| `HUD.TankPanel` (Frame, ZIndex 30, hidden), on the sheet shell → `Panel` → `Header.{Icon, Title, Count, Rate, Total, Market}`, `Close`, `Cards` (ScrollingFrame + UIGridLayout) → `CardTemplate`, `EmptyTemplate`, `LockedTemplate` | `tools/builder/gui/Sheet.luau` (new, shell) + `tools/builder/gui/Tank.luau` (new, content) | `TankPanelController` + client helper `Controllers/Sheet.luau` |
| `HUD.Fishing.CatchCard.TankStamp` (small tilted stamp, hidden) | `tools/builder/gui/Fishing.luau` | `FishingController` via `CatchFx.tankStamp` |
| fish display, tags, sign, pier word, pops, slot FX | runtime | `TankWorldController` |

`ClientMain` ORDER gains `"MoneyController", "TankButtonController", "TankPanelController",
"TankWorldController"` (after `HudController`, before `FishingController`).

**The sheet shell** (K-18). `gui/Sheet.luau` builds the plate, the header row, the ✕ and the scrolling
card grid. The client helper `Controllers/Sheet.luau` owns open/close (`snapIn`/`popOut`), the placement
(§6.4), the recompute on `ViewportSize` changes and the auto-close-on-fishing rule. The Stage 5 shop
reuses both.

### 6.2 Wallet (money + rate)

- **Where.** The status stack's second row, exactly where `CatchCounter` was:
  - phone 844×390 ≈ 287..557 × 99..131;
  - tablet ≈ 296..752 × 142..221;
  - desktop ≈ 424..880 × 139..215.

  Width 0.94 of Status; `Money` takes 0.64 of it and `Rate` 0.34, in a horizontal UIListLayout, centred.
  The stack does **not** grow: phones have no room below (reader §0.1).
- **Look.** The reference's «$0»: an outlined 💵 at −8° and a big italic `MoneyText` green number with the
  Ink display outline. The rate is a smaller italic green (Button tier, ≥ 14 px on `phone_small`), hidden
  while income is 0. «$999 999» must stay ≥ 22 px tall on `phone_small`.
- **Load states** (K-10):
  - The Wallet shows once `DataMode ≠ "Loading"`. A base is **not** required: a queued player owns money
    too.
  - If loading lasts > 3 s (a lock wait can take ≈ 24 s), the Wallet appears on glass with «$…» and no
    rate, so the money never looks gone.
  - Pop-ins are ordered after the base banner lands: badge → Wallet → САДОК, 0.3 s apart (`popIn` from
    0.3, the 💵 spinning in). In a queue, the Wallet pops in when the data loads.
- **The income tick.** **Plain text** each second: no `countUp`, no bump (STYLE idle budget, hud_style
  "idle HUD"). Every 5 s, with income > 0, a small «+$13» `floatText` (timer-based) rises to the right of
  the number.
- **One owner of the label** (K-11). MoneyController keeps `shown` (= `Money − held`). While a `countUp`
  runs, the 1 Hz tick does not write the label; it adds its delta to the count-up's target. The tick
  resumes when the count-up ends. The number never jumps back and forth.
- **`MoneyController.Celebrate(amount, from: GuiObject?, opts)`:**
  - `flyTo(hud, from, Money.Icon, { text = "💵", count = 3..8 by amount })`; with `from = nil`, there is
    no flight;
  - on the first arrival `countUp(label, shown, shown + amount, 0.6–1.0, TankRules.FormatMoney, { bump = true })`
    and `flashText(label, Gold.Top)`;
  - a Button-tier gold «+$1 234» float and the sound "ping";
  - a frame job only while it runs.
- **Rate feedback.** After a **manual sale** the rate label rolls **down** (`countUp`, 0.5 s) with a short
  Berry `flashText`, so "sold" links to "less income" (K-3). After a **replacement** it rolls up with a
  gold flash.
- **Catch hold.** While the HUD has `CounterHold`, a sale that came with the catch (`Tank.Result`
  "replaced" / "sold": `Price`) is held back (`shown = Money − held`). When `CounterHold` clears:
  - "replaced" → `Celebrate(price, TankButton)`: coins fly from «САДОК» to the Wallet.
  - "sold" → the card ghost has just landed on `Wallet.Money` as 💵 (§6.5), so `Celebrate(price, nil)`
    only counts up.

### 6.3 TankButton

- **Where.** Right column slot 2, above «ДОМОЙ»:
  - phone 776,141 60×60; notch 734,136 56×56; small 603,137 57×57;
  - tablet 910,285 104×104; desktop 1163,467 104×104.

  The column, the card docking, the «СМОТАТЬ» narrowing and the trophy chip already follow the visible
  stack (reader §1.2); re-check with renders.
- **Visibility.** Shown when a base is assigned and the data is loaded (`popIn` on its spot; never animate
  the column's Position). Press: `UiFx.press` once at Start → `TankPanelController.Toggle()`.
- **Chip.** «4/6» comes from the Player attributes `TankCount`/`TankSlots`, the only source; the Caught
  payload's `Tank` decides only which arrival plays. The chip is Cream, and **Gold** when the tank is full.
- **Catch arrival** (the old counter contract, re-pointed). FishingController sets `CounterHold` on
  "Caught" and `CounterIncoming = rarity` at card close. TankButtonController treats `CounterHold` as
  "freeze the chip at the count before this catch". On release it plays:
  - "stored" → an odometer roll on the chip, a bump of 1.3 (1.45 in rarity colours), a glow ring in the
    rarity colour, a 🐠 squash and wiggle, and a tick;
  - "replaced" → the chip stays, the 🐠 wiggles, a ring plays, then `MoneyController.Celebrate(price, TankButton)`;
  - "sold" → no arrival on this button (the ghost flew to the Wallet), but while the sold card is on
    screen the Gold «6/6» chip **pulses** (`UIConfig.TankButton.SoldPulse` 1.22 every `SoldPeriod`
    0.7 s): the sale is tied to the full tank (UX-01).

  Without `CounterHold` (a Stage 4 `"Stored"`), the same arrival plays one frame after `TankCount`
  changes.
- **Onboarding «!»** (K-8):
  - After the arrival of the first fish ever (`Tank.First`), `UiFx.badgeBob(TankButton.Badge)` runs.
    STYLE §6.6: "A new notification on a button: `Theme.badge` + `UiFx.badgeBob`".
  - The first open of the panel calls `UiFx.badgeHide`.
  - It is session-local, so it needs no new remote; `First` fires once ever anyway.
- **Tap during the flight** (K-9). A tap while `CounterHold` is set is remembered (no refusal wiggle). The
  panel opens right after the arrival, scrolled so the new fish's card is in view, with a rarity
  `glowRing` on it. A tap during a bite, the minigame or while the card is still open is refused with a
  `wiggle`.
- **Colour check** (K-23). `Water` (#6FF2FF → #13B8D6) is close to `Sky` (the «ЗАБРОСИТЬ» colour just
  below on phones). If the `tank_button` phone render reads as "the same blue button", deepen the Water
  fill for this button, or keep it and enlarge the 🐠 so it reads by its icon.
- **Micro-life:** HudController's rotation swaps the 🐟 counter flip for the 🐠 wiggle on this button.
  *(P2, K-20: a short gold `shine` glint when a tank fish reaches МАКС, and «МАКС!» floating off the
  pier word; never a toast.)*

### 6.4 Tank panel

- **Placement**, computed in px at open, then **written as `UDim2.fromScale(x / W, y / H)` of the HUD**
  and recomputed on a `ViewportSize` change (K-13, spec «UDim2 через scale»):
  - left = 16 px (+ safe inset); right = min(RightButtons.left, Jump.left) − 16;
  - top = Status bottom + 16; bottom = HUD bottom − 16.
  - Phone 844×390 ≈ 16..733 × 153..374 → 717 × 221. Tablet and desktop are capped at 900 × 560 and
    centred in that box.

  The panel **never covers the Wallet or the TankButton** (coins fly there; the button toggles), and there
  is no dim. It may cover the idle ActionArea and the thumbstick zone (a modal sheet).
- **Back** (K-12):
  - On phones, a **glass** back (one quad; STYLE: "secondary info goes on glass") with a thin Night
    header strip.
  - On tablet and desktop, a Night sim plate.
  - Cards keep `Theme.sim` with `shine = false`, no gloss, no shadow.
  - `TankPanel` is added to `tools/preview/gui/checks.py` `CONTAINERS` (`{"HUD": {"Fishing", "TankPanel"}}`),
    so its cards, header and ✕ are checked as widgets even though the sheet covers ≥ 45 % of the screen.
- **Header row** (≈ 44 px on phones):
  - 🐠 «САДОК» (Title tier) · chip «4/6» · «+$42/с» (green italic);
  - **«💵 $2 783 📈»**: the tank's total current value at the current rate, ticking on the 1 s chain (K-2;
    it makes «дорожает, чем дольше лежит» visible);
  - the market chip «🏪 РЫНОК +50%» (Gold, only while `SellRatePct > 100`);
  - `Close`, a round Berry «✕» (≥ 44 px) overhanging the top-right corner.

  There is **no «ПРОДАТЬ ВСЁ»** (K-2).
- **Cards.** Phones get one horizontal row (ScrollingFrame, explicit `CanvasSize`); a HUD ≥ 600 px tall
  gets 2 rows. Card size is a scale of the ScrollingFrame, with `UIAspectRatioConstraint` and
  `UISizeConstraint` (phone ≈ 112 × 160 px; buttons ≥ 44 px). Order: slots 1..TankSlots, then ONE locked
  teaser card.
  - **Fish card**: a rarity sim plate (rarity gradient; the Mythic rainbow outline only while open):
    - `Name`: `TextUtil.upper(ShortName)` at the Small tier («ОКУНЬ», ≤ 76 px at 14 px). Cards ≥
      `Panel.WideCard` 150 px wide show the full name (K-6).
    - `Viewport`: the real fish, a ViewportFrame with a clone, its camera framed once, created on open and
      destroyed on close.
    - `Mutation`: a chip overhanging the top-left («✨ ×2» etc.), hidden if none.
    - `Rate` «+$4/с» (Body, MoneyText).
    - `Growth`: a thin bar (Track/Fill) with «×1.4», or a gold «МАКС» stamp.
    - `Sell`: on phones **«💵 $45»** («💵 $60 750», the longest case, is 63 px at 14 px), on cards ≥ 150 px
      «ПРОДАТЬ $45». Leaf at home, Gold in market mode, Berry «ТОЧНО?» with a 3 s `ringTimer` in the
      confirm state. On a Legendary card (a yellow → orange plate: the Gold button's own colours) the
      market button is Sun with a solid white rim instead, so the most valuable fish keeps a strong call
      to action (ART-07, `TankCards.lookToken`).
  - **Empty card**: a glass plate with a faint 🎣, «ПУСТО», «Поймай рыбу!».
  - **Locked card**: Slate, with 🔒, «ЕЩЁ МЕСТО», «Скоро в магазине».
- **Live values:** one 1 s `task.delay` chain while open (prices, bars, the header total). The values come
  from the own base's slot attributes plus `SellRatePct`. Never a frame job while idle-open.
- **Market mode:** whenever `SellRatePct > 100`, the server-sampled attribute and the only source. The
  Market chip pops in, prices use the stall rate, and the sell buttons turn Gold. `TankEvent "Open"` from a
  stall only opens the panel; the server writes `SellRatePct` before it (the prompt hold counts as the
  dwell), so a stall's panel opens in market mode. Opened by «САДОК» on the way, the chip may pop in up to
  ≈ 2 s after arrival (the dwell); that reads as a "prices jump up" moment.
- **Sell one** (every fish, K-3):
  1. The first tap → confirm state: Berry «ТОЧНО?» + `ringTimer` 3 s, and the card's `Rate` label flashes
     red «−$4/с».
  2. A second tap earlier than `ConfirmArm` 0.4 s is ignored. A second tap within 0.4–3 s → `TankSell(uid)`,
     and the button shows ⏳ until the answer. After 3 s it reverts.
  3. On `"Sold"`: the card squashes, the viewport pops out, and the card turns into an empty card
     (`popIn`); then `MoneyController.Celebrate(Amount, card)` and the rate rolls down (§6.2). The world
     fish pops on its own via the slot event.
  4. `"Denied"` → the card wiggles, and a hint toast shows `Text`.
- **Open / close:** `snapIn` + `staggerPop` of the cards / `popOut`.
  - Open while `CounterHold` → deferred (§6.3).
  - Open during a bite, the minigame or an open catch card → refused (the button wiggles).
  - The panel **closes itself** when `FishingState` becomes "Bite" or "Reeling", when `CounterHold`
    appears, or when `BiteAlert`/`Minigame`/`CatchCard` become visible. The fisher is never covered while
    fishing.
  - It also closes via ✕ or the TankButton.
  - **The open sheet covers the fishing layer** (UX-04): while it is open, `HUD.Fishing` is hidden when
    its ActionArea lies under the sheet or the screen is short (`Sheet` fit not tall) — «ВЗЯТЬ», its red
    «!» and the hint never show through the glass as part of an empty card; it is back on close (the
    panel is refused during a bite, the minigame or an open card anyway, so nothing is interrupted).
- **Budgets:**
  - phone fill ≤ 2.5× with the panel open, measured by `gui_render.py`; if it still fails, phones swap
    the viewports for rarity emoji 🐟 🐠 🐡 🦈 🐉;
  - ≤ 60 temp GUI objects;
  - `activeJobs() == 0` after every juice;
  - the connection count back to baseline after close.

### 6.5 Catch card changes (FishingController — copy and target only)

1. `collectUi`: `ui.counter = child(child(hud, "RightButtons"), "TankButton")`;
   `ui.wallet = Status.Wallet.Money`.
2. `ghostCard` / `flyHome`: one `if` on `fish.Tank and fish.Tank.Result == "sold"` → the target is
   `ui.wallet` and the ghost's emoji is 💵. Otherwise the target is the TankButton. Drop the hidden-counter
   Status-list fallback; when no base exists, target the RightButtons frame centre.
3. `fillCard`: `InfoLabel` «{kg} · цена $45» (`TankRules.FormatMoney`). **One money notation**
   (UX-06, ART-05): the price chip (icon 💵) counts up «$0 → $58» and the own trophy's nameplate reads
   «💵 $518» — `CatchFx.money` = `TankRules.FormatMoney`, the Wallet's «$».
4. `floatPrice`: «+$4/с» (`TankRules.FormatRate(Income10)`, MoneyText), or a gold «+$15» when the result is
   "sold" (K-4).
5. **`TankStamp`**: `CatchFx.tankStamp(result) -> (text, token, sub)` (new and pure; K-4). It returns
   «В САДОК!» (Water), «ЗАМЕНА!» (Leaf) or, for a fish sold on the spot, «ПРОДАНА» under «САДОК ПОЛОН»
   (`sub`, Sun: the cause is named on the card, UX-01), and `nil` without `Tank` (hidden). It is a
   sticker like «НОВИНКА!» (ART-04): tilted −8°, overhanging the card's bottom-right corner
   (`CatchFx.tankRow`; the close hint keeps its row, left of it), its plate ≥ 26 px tall on the
   smallest phone card with a ≥ 16 px line (the sold one ≥ 18 px), and it never covers the price chip.
   A sold card closes itself no sooner than `CatchFx.SOLD_HOLD` 1.8 s after its stamp lands
   (`CatchFx.cardTime`), so «САДОК ПОЛОН / ПРОДАНА» can be read. The
   existing `CatchFx.stampText` is the mutation-stamp fitter and keeps its contract.
6. `parseFish`/`onCaught`: read the optional `Fish.Uid`, `Fish.New` and `data.Tank` (the result is kept
   on the fish record). `openCard`: `isNew = if fish.New ~= nil then fish.New else not seenSpecies[fish.Id]`.
7. `CLIMAX.ListLeft` / `ListBottom` are re-estimated for the wider desktop player list with two leaderstats
   columns (default estimate: the list ≈ W−308..W−8 × 4..74; `ListLeft ≈ 330`), together with
   `tools/preview/gui/backdrop.chrome_shapes` PlayerList.

No new top-level locals beyond one `TankRules` require (34 spare registers; floor 24); the stamp logic
lives in CatchFx.

**HudController:**

- delete the CatchCounter code (refs, render, roll, arrival, listeners);
- micro-life uses the TankButton 🐠;
- the header and the «магазин (этап 3)» label are fixed to «этап 5».

NotifyController is unchanged: the `CounterHold` busy semantics survive, because FishingController still
sets it.

### 6.6 Toasts (client-side, `NotifyController.Show` with `look` overrides — no new kinds)

| when | text (TankConfig.Texts / DataConfig.Texts) | width at 12 px | look |
|---|---|---|---|
| first fish ever (`Tank.First`), after the arrival | «Твоя рыба приносит $ каждую секунду!» | 231 | Water 🐠 |
| replaced | «Замена! «{new short}» вместо «{old short}» +$24» | ≤ 260 | Leaf 💵 |
| sold on the spot — **first time per session only** | «Садок полон — лови рыбу получше!» | 206 | Sun 💵 |
| sold on the spot, a **notable** fish (a new species, a mutation, or Epic+ — `SoldExplain`) — **every time** | «Садок полон: «{short}» слабее всех, +$58» | ≤ 300 | Sun 💵 |
| denied | `Text` from the server | — | warning |
| memory mode (once, after the base banner) | «💾 Studio: прогресс не сохраняется» | 212 | warning |
| (P2) milestone | «Уже $10 000! 🎉» | — | Gold 💵 |

The toasts follow the existing rules: none while the catch is on screen, queued, one at a time on phones.
Names in quotes avoid Russian gender agreement. Later on-the-spot sales of ordinary fish get no toast:
just the «САДОК ПОЛОН / ПРОДАНА» stamp, the pulsing «6/6» and the coins (K-4); a good fish never leaves
silently (UX-01). The catch toasts wait for the own trophy to leave and then `UIConfig.Wallet.AfterTrophy`
0.9 s more, so the pier word's «🐠 1/6» punch is seen before a toast lands on it (UX-03). A `stage3_rules` case checks every toast with the longest names and prices
filled in: ≤ 300 px at 12 px (the `phone_small` column is 374 px, icon included) (K-7).

### 6.7 What moves on screen

- `CatchCounter` disappears; its row becomes the Wallet.
- `TankButton` takes the free column slot above «ДОМОЙ». The column grows upwards, and the trophy chip
  moves up to HUD y ≈ 32 on phones.
- The pier word appears in the world beside the fisher (hidden while fishing is busy).
- Nothing else moves.
- The 3rd column slot stays free for Stage 5; then the trophy chip needs a new place (reader §1.2, R14).
- **Reserved for the Stage 4 shield timer** (K-19): a glass chip «🛡 4:59» docked at the right end of
  `Status.BaseBadge`. The shield protects the base, the status stack cannot grow on phones, and the
  Wallet's rate stays visible. Stage 4 checks its width on `phone_small`.

### 6.8 Save indicator

None (kids don't need it). Only the memory-mode toast and the kick messages of §3.1.

### 6.9 Text inventory (all in config)

- **Panel:** «САДОК», «ПРОДАТЬ», «ТОЧНО?», «МАКС», «ПУСТО», «Поймай рыбу!», «ЕЩЁ МЕСТО»,
  «Скоро в магазине», «РЫНОК +50%».
- **Card stamps:** «В САДОК!», «ЗАМЕНА!», «ПРОДАНА» under «САДОК ПОЛОН».
- **Toasts:** §6.6.
- **World:**
  - «Пусто», «🔒 Закрыто»;
  - prompts «Открыть / Садок», «Продать рыбу / Рыбный рынок · +50%», «Продать рыбу / Ларёк · +50%»;
  - the word «РЫНОК +50%!» (hub only).
- **Denied:** loading «Загружаем твой садок…» (also `FishingConfig.Texts.Denied.loading`), nobase
  «Сначала дождись своей базы», missing «Этой рыбы уже нет», locked «Эту рыбу сейчас не продать».
- **Kicks:** §3.1 `DataConfig.Texts`.

---

## 7. Tests (RbxSim) and renders

Runner: `/opt/tools/l11/lune run tools/run_tests.luau [filter]`. Every file runs < 600 s, and nearly every
test ends with `AssertNoErrors({ warnings = true })`. Keep test money < 2^24 (float32 attributes) or read
the leaderstats.

### 7.0 Test infrastructure (B-28)

- **Headless server tests.** `sim:AddPlayer({ …, clientDelay = 1e9 })` never starts the client
  (`players.luau:155`). Long virtual waits such as `Advance(300)` for growth or `Advance(130)` for two
  autosaves cost a fraction of a client run.
- **Patchable knobs.** Use `boot(t, patches)` (`stage2_fishing.test.luau:61`) to shrink `AutoSave`,
  `Growth.Time` and `LockWait.Every` per test. Keep one test at the real numbers.
- **Restart helper.** `restart(old, gap)` = `t.sim({ place, dataStore = old.DataStore:Snapshot(),
  epoch = 1700000000 + math.floor(old:Time()) + gap, seed = old.seed + 1 })`. Use it everywhere, so no
  test forgets the seed (a different seed → a different server token, R10).
- **Gap assertion from the log.** Group `sim.DataStore.Calls` by key (writes = `UpdateAsync`, including
  failed and cancelled ones) and assert that consecutive `time`s differ by ≥ 6. This is in addition to
  `AssertNoErrors({ warnings = true })`.
- **The ledger.** Every server test asserts `PlayerData.Ledger` on the `Peek`ed value after `Shutdown`.
- **Leaks.** `_debugSizes()` of the four services is all zeros 10 s after the last player leaves.
- **Store name.** Read it via `DataService.StoreName` (the sim reports Studio → `PlayerData_Studio`).
  `PlayerData.StoreNameFor(false) == "PlayerData"` is unit-tested.

### 7.1 `tests/stage3_rules.test.luau` (pure; Wave 0)

- **TankRules:**
  - the growth curve and cap;
  - `CurrentValue`/`SellPrice` with integer percents (45 at 150 % → 67; 54 at 150 % → 81, exact,
    with no 0.999… floors);
  - `Income10`;
  - `ChooseReplacement` (ties, Locked and Dormant skipped, never a higher-income fish);
  - `FormatMoney` (0, 999 999, 1e6, 12 345 678, 1.5e9, 1e15, NaN, inf);
  - `FormatRate` (8, 40, 420, 12 340 tenths);
  - `AttrTime`.
- **PlayerData:**
  - the template shape;
  - `Reconcile` deep-fills dictionaries only and keeps unknown fields;
  - `Sanitize`: every rule of §2.1 (negative/NaN money, NaN `Kg`/`Age`, duplicate/invalid Uids, a
    dictionary `Tank`, duplicate/out-of-range slots → re-pack or dormant, `NextUid`);
  - **future content kept verbatim** (`Id = "FutureFish"`, `RodId = "RodFuture"`, `TankSlots = 16`,
    14 fish → nothing dropped, nothing sold);
  - the ledger.
- **Serialize:**
  - JSON-safe output (dense arrays, no NaN);
  - `_` keys dropped;
  - runtime junk dropped with an issue (`Tank[1].Junk = <Instance>`, `Money = 0/0`);
  - unknown JSON-safe fields kept, and dropped under `strict`;
  - `skipUid`;
  - 12 fish < 4 KB.
- **Config invariants:** `AutoSave < LockStale`; `LeaveSaveWindow + MinWriteGap < LockWait.Tries × Every`.
- **Text widths** (K-6, K-7):
  - every toast with the longest names and prices ≤ 300 px at 12 px;
  - every card string at its tier fits its box by `UiFx.textWidth` (the longest ShortName, «💵 $60 750»,
    «ТОЧНО?», «−$1 125/с»);
  - `CatchFx.tankStamp` texts.

### 7.2 `tests/stage3_data.test.luau` (server, real place, headless; Wave 1 A)

- **Load:**
  - a new player → the template, and the lock written with `LoadId` and `Server`;
  - load retries (`FailNext(2, …, {"UpdateAsync"})`);
  - the load fails 5× → kicked (≈ 30 s), nothing written, the record `Released` before the kick;
  - `Poke` V = 99 → kicked TooNew, untouched;
  - a non-table value → kicked, untouched.
- **Locks:**
  - a fresh foreign lock → waits ≈ 24 s, steals, one warn;
  - a stale lock (T − 200) → taken at once;
  - the lock lost mid-session (`Poke` a foreign Session) → the next save is cancelled + kicked.
- **The holes the backend critic found:**
  - **B-1:** another server released the key (`Poke` `Session = nil`) → our save is cancelled, newer
    data untouched; a deleted key → our save is cancelled, the key is not recreated.
  - **B-2:** same-server rejoin, then the old record's save via `_saveRecordForTest` → cancelled, the
    new session's money untouched.
  - **B-3:** same-server fast rejoin while the old final save retries (`FailNext(2, nil, {"UpdateAsync"})`)
    → the new session still saves.
  - **B-5:** runtime junk in the live table → the next save still commits a valid value, one warn; a
    forced 104 → one strict retry.
  - **B-6:** future content survives load → play → leave (`Peek`).
- **Cadence:**
  - autosave cadence: no two writes to a key < 6 s (from the log), no "added to queue" warning, a
    single scheduler (no per-player connections);
  - coalescing: a `SaveSoon` while queued is dropped; a `SaveSoon` while in flight → exactly one follow-up;
    `Committed` seq order.
- **Leave:**
  - leave → final save, `Session == nil`;
  - leave during load (`SetLatency(3)` then 0.05) → a release-only save, no gap warning;
  - the leave save fails twice → succeeds within `LeaveSaveWindow`;
  - a release retry that finds `Session == nil` → stops quietly.
- **Shutdown:**
  - `Shutdown()` with 3 players → `completed`, one final write each (`CountCalls`), all locks released,
    < 25 s;
  - **B-13:** a player mid-load at shutdown → the lock is released.
- **Modes:**
  - memory mode (`SetEnabled(false)` before boot) → one warn, `DataMode = "Memory"`, zero writes, an
    instant `Shutdown`;
  - Broken (a patched Start error) → plays, never writes.
- **Hygiene:**
  - a garbage `Poke` → sanitized, the ledger warn expected;
  - no leaked connections after leave; `_debugSizes` zeros.

### 7.2b `tests/stage3_data_chaos.test.luau` (headless; Wave 1 A)

1. `SetFailRate(0.3)`, 3 players, 10 virtual minutes of forced catches and sells, two leaves and rejoins,
   then `Shutdown()`.
2. Restart with `SetFailRate(0)` and rejoin all players.
3. Assert:
   - no duplicate Uids;
   - the ledger holds;
   - every lock is released or stale;
   - money is ≥ the last value seen at a confirmed `Committed` and ≤ the in-memory value at leave.

This is the one test that exercises the retry, coalescing and queue logic together.

### 7.3 `tests/stage3_tank.test.luau` (server; Wave 1 A)

- **Catching:**
  - a catch (a forced fish via `RollFishForTest`) → the lowest free slot, a `Uid`, the payload's `Tank`
    stored; slot/Tank/Player attributes, label, light bar;
  - `Event` written last, fish fields nil on empty;
  - `New` true, then false (and persisted).
- **Full tank:** 6 → full; the replaced (higher income) and sold (lower) paths with money and the toast
  data.
- **Casting before load:** a cast before the load finishes (`SetLatency(2)`) → `Denied loading`.
- **Income and growth:**
  - **income exact**: after N ticks, money = floor(N · Σ Income10 / 10);
  - a hitch (`Advance` 10 s in one step) → ≤ 3 ticks credited;
  - no base (queue) → no income or growth; once assigned → mount (`Event mount`, no `in`);
  - growth → ×3 at 300 s (patched to 30), the price at the sale moment;
  - a mount on a whole-second frame → `GrowFrom` exact (`AttrTime`).
- **Selling:**
  - `TankSell` → money += price, slot empty, `Event sold`, `TankEvent Sold`, stats, the ledger;
  - the Legendary/Mythic catch → `SaveSoon`.
- **Stall rate:**
  - the HRP at the market → `SellRatePct` 150 after 2 samples, the price ×1.5; a kiosk 150; away 100;
  - teleporting in and selling at once → ×1, and still ×1 after the dwell: a jump holds the rate for
    `MarketJump.Penalty` samples, the stall prompt included (BE-02);
  - walking in and holding the stall prompt at once → `SellRatePct` 150 before `Open` (UX-05).
- **Prompts:** a market hold → `Open`; the own tank prompt → `Open`; another player's tank prompt →
  nothing; a prompt spam → bounded by the bucket.
- **Exploits:**
  - junk args (nil, number, table, NaN, a 200-char string, `"f1x"`);
  - another player's uid;
  - a double sell (money once, `Denied missing`);
  - 100 sells in one frame (≤ burst, `Denied` replies bounded);
  - a sell without a base → `Denied nobase`.
- **Other:**
  - a dormant fish (unknown Id `Poke`d) is never shown, sold or replaced, and is saved back;
  - two players are independent;
  - the rod from data (`Poke RodId = "RodSea"`; `"RodFuture"` → runtime StartRod, saved unchanged);
  - leave → slots «Пусто», attributes cleared, the prompt disabled.

### 7.4 `tests/stage3_world.test.luau` (client with faked slot attributes; Wave 1 B)

- **Display fish:**
  - a fish model built on the right display (bbox centred within 0.1 of FishPoint, fits the 6.2 cube,
    the correct species/mutation), removed on `empty`;
  - a swap via `Event` with `State` unchanged → the model changes;
  - nothing built beyond `Display.Range`; torn down only beyond `DropRange`;
  - ≤ 3 builds per check;
  - tweens only within `LifeRange`, cancelled beyond.
- **Words:**
  - tags show «+$4/с», the value ticking, «МАКС»; the tank sign;
  - **the pier word** on the own base only: hidden on Bite/Reeling/`CounterHold`/`HeldFish` (and
    `TrophyGap` after it); a splash on arrival; income pops only within 30 studs of the bucket, every 5 s;
  - the tags' and the sign's letters stay within their px caps up close (ART-02); one «🔒 Закрыто» per
    arcade side, following the open rows (ART-03);
  - **clear of the HUD** (ART-01, UX-02): a word projected onto the Wallet row or a toast fades, and comes
    back once it is clear again.
- **Slot events:** `in`, `sold`, `swap` create and clean their FX; `mount` creates none.
- **Other:**
  - other players' tank prompts are hidden locally;
  - no RenderStepped/Heartbeat connections are added;
  - the part count of display fish is ≤ 20 each;
  - everything is gone after the base is released (no leaks).

### 7.5 `tests/stage3_hud.test.luau` (Wave 2 C) and `tests/stage3_panel.test.luau` (Wave 2 D)

Client tests stub `FishingService`, `DataService`, `EconomyService`, `TankService` and `MarketService`
with `return {}`, and fake the contract:

- the Player attributes, incl. `DataMode`, `Money`, `Income`, `TankCount`, `TankSlots`, `SellRatePct`;
- the slot/Tank attributes;
- `TankEvent`;
- `FishingState "Caught"` with `Tank`.

They read the client's requests with `sim:ServerEventsFor(p, "TankSell")`. Stage 1/2 client tests that stub
only `FishingService` keep the real Stage 3 services (they load from the sim DataStore in ≈ 0.1 s).

**HUD (`stage3_hud`):**

- names; the sim look (`checkSim`);
- layout on phone / phone_notch / phone_small / tablet / desktop: no overlaps, TankButton ≥ 44 px and
  ≥ 16 px from Jump, the trophy chip clear of the taller column;
- Wallet formatting incl. «$1.23M»;
- the Wallet shown with no base; «$…» after 3 s of Loading; the pop-in order;
- idle with income flowing → `activeJobs() == 0`, stable connections, the 5 s float only;
- the tick never fights a count-up (K-11);
- the catch flight → the chip frozen under `CounterHold`, the arrival on release in rarity colours;
- the stamps «В САДОК!» / «ЗАМЕНА!» / «САДОК ПОЛОН · ПРОДАНА» (a corner sticker, ≥ 16 / 18 px);
- **sold** → the ghost to `Wallet.Money`, the «6/6» chip pulses while the card is up, no toast after the
  first per session for an ordinary fish; a notable one (new, mutated, Epic+) gets «Садок полон: …» every
  time;
- the catch toasts wait for the trophy to leave plus `Wallet.AfterTrophy`;
- **replaced** → coins from the TankButton + the toast after the hold;
- the onboarding «!» after `First`, gone on the first open;
- a tap during the flight → the panel opens after the arrival, on the new card;
- the first-fish toast once; the memory toast once.

**Panel (`stage3_panel`):**

- open/close by the button and by `TankEvent Open`;
- cards for fish/empty/locked;
- phone labels (ShortName, «💵 $45») vs wide labels;
- values tick (1 s chain, no frame job); the header total;
- market mode on `SellRatePct` only (on a Legendary card the market button is Sun with a white rim);
- **confirm on every sale**: the first tap fires nothing; a second tap at +0.15 s fires nothing; at +0.5 s
  it fires `TankSell(uid)`; a 3 s timeout reverts; the red «−$X/с» flash;
- after `Sold`, the Wallet rate rolls down;
- juice ends (`activeJobs() == 0`);
- closes on Bite / `CounterHold` / CatchCard; refuses to open during a bite;
- while open it hides the fishing layer under it («ВЗЯТЬ» and its «!»), back on close (UX-04);
- the layout is scale-based (`Size.X.Offset == 0` on the panel and cards) and survives a `ViewportSize`
  change;
- phone fill ≤ 2.5×.

### 7.6 `tests/stage3_e2e.test.luau` (real server + clients; Wave 3 E; split in two files if > 600 s)

1. A forced catch → the card stamp «В САДОК!» → the flight → the chip «1/6» → the pier word «🐠 1/6» → the
   client has a fish model on `Slot_1.Display`.
2. Advance 30 s → Wallet ≈ income × 30.
3. Open the panel → sell (two taps) → money += price.
4. Walk to the market, `HoldPrompt` at once → the panel opens in market mode → **sell 2 fish one by one
   at ×1.5**.
5. 6+1 forced catches → replace / auto-sell (stamps, one toast).
6. Leave → `Peek` → `restart` (+1 h) → rejoin → the same money, fish, slots and ages (no offline growth),
   and the HUD shows them.
7. The same flow with `remoteLatency 0.15`, and with `FailNext` on the first load and the leave save.

### 7.7 Existing tests to update

- `hud_style`: the names, the layout, the 3 catch-counter tests → the TankButton chip, idle, micro-life.
- `fishing_ui_style`: «closing … flies into the counter» → the TankButton (the Wallet for "sold");
  «+N 💰» → «+$X/с»; the card dock vs the taller column; the TankStamp.
- `stage2_e2e` `checkCatch`: the counter assertions → the chip.
- `stage2_client`: the counter.
- `stage2_fishing`: the `Caught` payload has `Tank`; the `GetCatch` cap; **casts right after join must
  wait for `DataMode ~= "Loading"`** (cast denied "loading", ≈ 0.1 s in the sim).
- `stage1_bases`: the owned base slot labels.
- `tools/preview/gui_dump.luau`:
  - `DEFAULT_BEATS` "+1" → `HUD.RightButtons.TankButton.Count.Label`;
  - the stub list +4 services;
  - harness helpers `h:money(n, income10)`, `h:tank(list)`, `h:tankEvent(kind, data)`,
    `h:caught(fish, total, tank)`.
- `gui_scenarios`: `catch_close`, `trophy_chip`.

**No RbxSim changes are required**: prompts, DataStore, BindToClose, leaderstats, GUIDs, time,
`clientDelay` and the budget API are all there.

### 7.8 Renders (5 devices; `gui_render.py --all` must stay clean: layout, ≥ 12 px text, phone fill ≤ 2.5×)

**GUI:**

- `wallet_idle`, `wallet_loading`;
- `tank_button` (+ `trophy_chip` re-check, the Water vs Sky check), `tank_button_badge`;
- `catch_to_tank` (the card with «В САДОК!» + the flight), `catch_replaced` (stamp + toast), `catch_sold`
  (stamp, the 💵 ghost into the Wallet);
- `tank_panel_home` (3/6 with a Gold mutant and a maxed fish), `tank_panel_full` (6/6 with a Mythic),
  `tank_panel_market`;
- `tank_sell_confirm` (Berry «ТОЧНО?», the red «−$X/с»), `tank_sell` (burst, the rate rolling down);
- `panel_bite_yield`;
- `first_fish_toast`, `data_memory_toast`.

**World** (the world-FX capture, or the mock script in `scratchpad/stage3/mock/`):

- **`pier_tank_word`** (the phone fishing camera: the word readable, clear of the fisher and the bobber);
- the base 1 court iso with 6 fish + locked slots;
- the follow camera in the west aisle (tags readable, lanterns);
- a Rainbow DragonFish close-up;
- the big tank sign;
- the hub market word and prompt, and a bridge kiosk prompt.

---

## 8. Implementation waves (2 agents at a time, isolated git worktrees)

Rules for every agent:

- a Russian header on every new script;
- `stylua`, `tools/analyze.sh`, a rebuild (`lune run tools/build.luau`);
- the full suite green (`compile_limits` ≥ 24 spare registers, `place_fresh`);
- commit.

The integrator merges, resolves `Place1.rbxl` by rebuilding, and re-runs the suite.

### Wave 0 — Contract (1 agent, short, before everything)

Files:

- **Configs:** `Config/TankConfig`, `Config/EconomyConfig`, `Config/DataConfig`; `FishConfig.ShortName`
  ×6; `FishingConfig.Texts.Denied.loading`.
- **Shared code:** `Shared/TankRules`; `ServerScriptService/Lib/PlayerData` (complete, pure);
  `RemoteNames` (`TankSell`, `TankEvent` + the header protocol of §4.5); `FishingRules` (`FishData` gets
  the optional `Uid`, `New`); `CatchFx.tankStamp` (pure).
- **Server stubs:** `DataService`, `EconomyService`, `MarketService`, `TankService` (headers + API
  signatures, no behaviour); `Main` ORDER.
- **Client stubs:** `MoneyController` (`Celebrate` no-op), `TankButtonController`, `TankPanelController`
  (`Toggle`, `IsOpen` no-ops), `TankWorldController`, the client `Sheet` helper; `ClientMain` ORDER.
- **GUI skeleton** (all hidden):
  - `gui/Hud.luau`: Wallet + TankButton with `Badge`; `CatchCounter` kept for now;
  - the new `gui/Sheet.luau` + `gui/Tank.luau`: the panel tree with all the contract names;
  - `gui/Fishing.luau`: `CatchCard.TankStamp`;
  - `Gui.luau`: the build call + the header grid.
- **Preview and tests:** `tools/preview/gui_dump.luau` stub list + harness helpers;
  `tests/stage3_rules.test.luau`.

The stub-sim harness joins every scenario player with the Stage 3 defaults (`DataMode "Ready"`,
`Money 0`, `Income 0`, `TankSlots 6`, `TankCount 0`, `SellRatePct 100`), so every existing scenario shows
the new chrome once Wave 2 lands.

Accept: the suite is green; no visible change in renders; every name in §6.1 exists in the place.

### Wave 1 — A: server core ‖ B: world visuals

- **A owns:**
  - `DataService`, `EconomyService`, `TankService`, `MarketService`, `FishingService`, `Main`;
  - `tests/stage3_data`, `tests/stage3_data_chaos`, `tests/stage3_tank`;
  - the server-side updates of `stage2_fishing` / `stage1_bases`.

  Accept: §7.2, §7.2b and §7.3 pass. The Stage 1/2 suites are green with real persistence running. No
  warnings in normal flows. `Shutdown` saves once per key. Memory and Broken modes are clean.
  `_debugSizes` reads zero after leave.
- **B owns:**
  - `TankWorldController`, `TankDisplay` (the pier word included);
  - `tests/stage3_world`;
  - the `MapConfig` comment and the `tools/builder/DESIGN.md` slot runtime contract (§4.6 write order);
  - the world renders.

  B works against the §4.6 attributes, faked in tests. Accept: §7.4 passes, and the world renders of §7.8
  look right (fish centred, readable tags, dim locked slots, the pier word clear of the fisher). No
  per-frame connection while idle; within budgets.

### Wave 2 — C: HUD + catch→tank ‖ D: tank panel + selling

- **C owns:**
  - `gui/Hud.luau`, `gui/Fishing.luau` (TankStamp);
  - `MoneyController`, `TankButtonController`, `HudController`, `FishingController` (§6.5 only);
  - the `UIConfig` additions and the `tools/preview/gui/backdrop.py` player list;
  - `tests/stage3_hud`;
  - the updates of `hud_style` / `fishing_ui_style` / `stage2_client` / `stage2_e2e` `checkCatch`;
  - the HUD scenarios of §7.8.

  Accept: catch → card stamp → flight into «САДОК» (or the Wallet for "sold") on all devices. The Wallet
  ticks calmly; the onboarding badge and the deferred open work; `--all` checks are clean; all the
  updated tests are green.
- **D owns:**
  - `gui/Sheet.luau`, `gui/Tank.luau`, the client `Sheet` helper, `TankPanelController`;
  - the `TankConfig.Panel/Texts` additions;
  - the `tools/preview/gui/checks.py` `CONTAINERS` entry;
  - `tests/stage3_panel`;
  - the panel scenarios of §7.8.

  D uses `MoneyController.Celebrate` (C) and the TankButton press (C calls `Toggle`). Accept: the §7.5
  panel cases pass. Phone fill ≤ 2.5× with 6 cards + the teaser on the glass back. The layout is
  scale-based. Nothing is left running after close.

### Wave 3 — E: integration ‖ critics, then a fix round

- **E owns:**
  - `tests/stage3_e2e*`;
  - README: the Stage 3 row ✅, «Как проверить Этап 3», how to enable saving in Studio, the "Migrate to
    latest update" note;
  - STYLE.md (§3/§6.5 for the Wallet, the TankButton, the sheet, the panel, the world tags and the pier
    word);
  - `gui_render --all`, the perf/budget audit.
- **Critics (3 lenses):**
  - kid-on-phone UX (the renders of §7.8 + the loop of §1.1);
  - data safety and code (§2, §4.7, races, leaks);
  - art (the world + GUI renders vs the reference).

  Findings → one fix wave (≤ 2 agents, by the file ownership above) → the final full suite,
  `Place1.rbxl`, the RU notes.

**«Как проверить Этап 3» (outline for README, Russian):**

1. Play → поймай рыбу → на карточке «В САДОК!», рыба прилетает в кнопку «САДОК», у ведра на пирсе всплеск
   и «🐠 1/6». Деньги 💵 растут каждую секунду. Во дворе базы рыба плавает в витрине (садок — ведро у места
   рыбалки: рыба сразу попадает туда, а живёт в 12 аквариумах-витринах во дворе базы).
2. Открой «САДОК» → цены растут до ×3 «МАКС» (5 минут). Продажа: «💵 $45» → «ТОЧНО?» → ещё раз (доход «+$/с»
   уменьшится — держать рыбу выгоднее, чем продавать).
3. Любой ларёк «ПРОДАТЬ РЫБУ» на мостах или «Рыбный рынок» на острове: E «Продать рыбу» → через секунду
   цены +50 %.
4. Поймай 7+ рыб — садок полон: рыба сильнее заменяет самую слабую («ЗАМЕНА!»), слабее — сразу продаётся
   («ПРОДАНА»).
5. Сохранение: в Studio без публикации — уведомление «прогресс не сохраняется» (так и должно быть). Чтобы
   проверить, опубликуй место, включи доступ к API, Play → Stop → Play: деньги и рыба на месте.
6. Server & Clients на 2 игрока — у каждого свой садок, деньги в списке игроков.

---

## 9. Risks and open questions (with the default answer, so nobody blocks)

| # | Risk / question | Default |
|---|---|---|
| R1 | The spec says «садок на конце пирса». | D1: the pier bucket is the intake (word, splash, pops); the fish live in the court. RU notes: «садок — ведро у места рыбалки: рыба сразу попадает туда, а живёт в 12 аквариумах-витринах во дворе базы». If the user wants a physical keep-net at the pier end, a later pass can trade big-tank decor parts (≈ 30 parts per base). |
| R2 | Selling anywhere lets an owner sell a fish a thief is stealing (Stage 4). | Stage 4 sets `Locked` during the steal hold (`Denied locked`). |
| R3 | Auto-replace could surprise a kid attached to a weak pretty fish (a first Rainbow Crucian is auto-sold by the first Puffer). | Accept; the toast names both fish. If playtests show upset kids: protect Rainbow (×5) fish in `ChooseReplacement` (one line, K-22), before favourites ⭐ (an optional `Fav` field). |
| R4 | Kick on a failed load is harsh. | Only after ~30 s of retries on a real outage; the message promises nothing it cannot keep. Never play on unsaveable defaults. |
| R5 | Desktop player list width with 2 leaderstats columns is unknown here. | Estimate (W−308..W−8) for `CLIMAX.ListLeft` and the preview chrome; verify in a real client later. |
| R6 | Sim attributes are float32 for whole numbers. | `AttrTime` for times; tests keep money < 2^24 or read leaderstats. No sim change. |
| R7 | Panel fill / ViewportFrame cost on phones. | Decided: a glass back on phones (K-12); measure; if it still fails, rarity emoji instead of viewports. |
| R8 | The client's price vs the server's. | Same formula, same clock, integer percents (B-18/19): the difference is network latency only; `"Sold"` carries the real amount and the count-up uses it. |
| R9 | Economy is generous; selling never pays in Stage 3. | Fine for Stage 3 (D16). Stage 5 sets prices against §3.5 or lowers `IncomeScale`; `SellScalePct`/`Growth.Cap` decide whether cashing out ever helps. |
| R10 | Same sim seed on restart → same server token. | The `restart` helper bumps the seed (§7.0). |
| R11 | Glass hides FX; lanterns occlude displays. | FX/tags above the glass; accept lantern occlusion. |
| R12 | Copy change on the approved catch card («цена $45», «+$4/с», the result stamp). | Do it (consistency, the float becomes true, the outcome is readable on the card). |
| R13 | DataStore request budgets are not emulated in the sim (it returns 100). | The budget check stays; one write/min/player is far under the limits. |
| R14 | A third right-column button (Stage 5) breaks the trophy chip on phones. | Out of Stage 3; noted for Stage 5. |
| R15 | The user tests in Studio on an unpublished file → memory mode. | Expected; the README explains publishing + API access; the Output warn says the same. |
| R16 | Milestone toasts / a persistent «Индекс». | Index data (`Stats.Species`) ships now; milestone toasts are P2. |
| R17 | Dormant fish (rolling updates) can reappear on a later load. | Accept: rare, and better than losing them. |
| R18 | Stage 1/2 tests that cast right after join now meet `Denied loading`. | They wait for `DataMode` (≈ 0.1 s in the sim); Wave 1 A updates them. |
| R19 | The stall chip pops in up to ≈ 2 s after arrival (dwell). | Accept; it reads as "prices jump up". The server pays what `"Sold"` says. A stall's prompt opens the panel at the stall rate at once (UX-05). |
| R20 | `Water` vs `Sky` on phones (K-23). | Check in the `tank_button` render; deepen the fill or enlarge the icon. |

**P2 (only if a wave has time):** the tail wag, the kiosk words, milestone toasts, the МАКС glint (K-20), and
the court hint (K-21). The court hint is «Твои рыбы — в аквариумах во дворе!» with the existing guide beam to
`Tank.Glass` for 6 s, shown once ever when the tank first fills (server flag `Stats.Filled`, result
`FirstFull = true`), only while Idle.

---

## 10. Решения по критике

Legend: **accepted** = applied as proposed; **changed** = applied in a different form (why given);
**rejected** = not applied (why given).

### critique_design.md (K)

| # | item | decision | why / where |
|---|---|---|---|
| K-1 | Садок presence at the pier end (bucket word, splash, pops moved there, fisher safety, no prompt, RU wording) | accepted | D1, §1.1, §5.3 pier word, §7.4, render `pier_tank_word`, R1, README. Verified: `Platform.Bucket` exists at `BaseTemplate.luau:2670`, 5.6 studs from the spot. |
| K-2 | Remove «ПРОДАТЬ ВСЁ»; header shows the tank's total value | accepted | Not in the spec; it is the −30 % button. The `TankSellAll` remote, its cooldown, confirm, toast, render and e2e step are cut (§4.5, §6.4, §7). `"Sold"` keeps an `Items` list for a Stage 5 return. |
| K-3 | Every sale two taps, 0.4 s arm, red «−$/с», rate rolls down after the sale | accepted | D8, §6.2, §6.4; `ConfirmRarities`/`NeedsConfirm` removed, `ConfirmArm = 0.4` added. |
| K-4 | Quiet "sold", loud "replaced", result stamp on the card | changed | Applied in full, but the stamp text comes from a new pure `CatchFx.tankStamp`. `CatchFx.stampText` is the mutation-stamp fitter, and reusing it would bend its contract. Logic stays out of FishingController (§6.5). |
| K-5 | Tell the economy truth; add a sale-only knob; Stage 5 constraint | changed | D16, §1.2, §3.4, §3.5, R9. The knob is `SellScalePct = 100`, an integer percent, to match B-19. |
| K-6 | `ShortName`; «💵 $45» on phone cards; width tests | changed | `ShortName` is stored in sentence case («Окунь», «Дракон»): toasts need it, and cards upper-case it with `TextUtil.upper`. Otherwise as proposed (§3.1, §6.4, §7.1). |
| K-7 | Shorter toast copy, ≤ 300 px test; fix `LoadFailed` | changed | The toasts are accepted as written (§6.6). `LoadFailed` now promises nothing («…Зайди ещё раз через минуту!»): with B-12 nothing can be caught during a failed load, and the critic's «прогресс до этого захода сохранён» is not guaranteed either (a previous final save may have failed). |
| K-8 | Onboarding «!» on «САДОК» until the first open | changed | Shown after the first fish ever (`Tank.First`) and hidden on the first open, but **session-local**, not saved in `Stats.TankOpened`. Persisting it needs a client→server remote just for a hint; `First` already fires once ever (§6.3). |
| K-9 | A tap during the flight opens after the arrival, on the new card | accepted | §6.3, §6.4, §7.5. |
| K-10 | Wallet without a base; «$…» after 3 s of loading; ordered pop-ins | accepted | §1.1, §6.2. |
| K-11 | Tick vs count-up ownership of the label | accepted | §6.2. |
| K-12 | Glass panel back on phones; `TankPanel` in `checks.CONTAINERS` | accepted | §6.4, Wave 2 D; R7 updated. |
| K-13 | Scale-based sizes (spec) | accepted | §6.4 (`fromScale`, recompute on `ViewportSize`, constraints), §7.5 test. |
| K-14 | Never drop a pending catch (`PendingMax` 50, overflow sold) | rejected | Superseded by B-12: casting is denied until the data is loaded, so there are no pending catches. |
| K-15 | Hysteresis 180/210 and ≤ 3 builds per check | accepted | §3.1 `Display`, §5.3, §7.4. |
| K-16 | Cuts: tail wag, court pops, kiosk words, milestones → P2 | accepted | §5.3, §9 P2 list. The court pops are removed (replaced by the pier pops). |
| K-17 | One stall rate | accepted | `MarketRatePct = 150` for all 5 stalls (D7, §3.1). Selling never pays in Stage 3, so two rates would be two prompts, words and tests for no decision. |
| K-18 | Reusable sheet shell | accepted | `gui/Sheet.luau` + the client `Sheet` helper (§6.1, Wave 0/2 D, §4.8). |
| K-19 | Reserve the Stage 4 shield-timer spot | accepted | A chip at the right end of `Status.BaseBadge`, the critic's option b (§6.7, §4.8). The shield protects the base, and the Wallet's rate stays visible. |
| K-20 | МАКС glint + «МАКС!» off the pier word | accepted (P2) | §6.3 note, §9 P2. |
| K-21 | Hint to find the court | accepted (P2) | §9 P2, with a saved once-ever trigger (`Stats.Filled` → `FirstFull`). |
| K-22 | Treasure protection later | accepted (later) | R3: a one-line rule in `ChooseReplacement`, if playtests ask. |
| K-23 | Water vs Sky colour check | accepted | §6.3, R20, render `tank_button`. |

### critique_backend.md (B)

| # | item | decision | why / where |
|---|---|---|---|
| B-1 | Strict save ownership: a missing lock or a nil value = lost | accepted | §2.2 save transform; the release-retry special case (our own unknown-result write) stops quietly instead of kicking. |
| B-2 | Per-load lock id; same-server instant takeover | accepted | §2.1 `Session`, §2.2 identity + load transform, §7.2 test. |
| B-3 | Records keyed by `Player` + identity check, in all services | accepted | §2.2, §4.1. |
| B-4 | One write gate `CanWrite`; compute before commit; fixed commit order | accepted | §2.2 state table + mutator rules, §4.3–4.5; `AddMoney` returns `false`. |
| B-5 | Whitelist serializer + 103/104/105 fallback | changed | Instead of a `__unknown` stash, `Serialize` validates known fields and passes unknown fields through only when JSON-safe (they came from a decoded save). Runtime junk is dropped by the validator, `_` keys are never written, and `strict` is the one-retry fallback. Same guarantees, one rule at every depth (§2.1). |
| B-6 | Sanitize never destroys unknown data (rolling updates) | changed | Applied, but dormancy is a **runtime flag** and the fish stays in `Tank` (no separate `Dormant` array), so an old and a new server never shuffle fish between arrays. `Kg` is not clamped: `FishingRules.Price` already clamps the size factor (`:258`). Sanitize never sells (§2.1). |
| B-7 | `num()` helper, unique Uids, non-array `Tank`, `Species` keys | accepted | §2.1. |
| B-8 | Memory mode only when `IsStudio()`; probe timeout; `probed` on every path | accepted | D13, §2.2, `ProbeTimeout = 5`. |
| B-9 | Stamp the gap when the request finishes, + epsilon | accepted | §2.2, `GapEpsilon = 0.05`. Verified: the sim stamps `lastWrite` after its latency wait (`datastore.luau:214–249`). |
| B-10 | Time-bounded leave save, shorter than the steal window | changed | `LeaveSaveWindow = 15`, not 18: the critic's own assert `18 + 6 < 4 × 6` is false (24 < 24). With 15: 21 < 24 (§2.2, §3.1). The autosave postponement cap is accepted. |
| B-11 | Queued vs in-flight coalescing (`Dirty`/`SnapshotSeq`) | accepted | §2.2. |
| B-12 | Deny casting while loading; delete `Pending` | accepted | D3, §4.2, §4.3; `PendingMax`, `Result = "pending"` and the pending `"Stored"` are removed (`"Stored"` stays for Stage 4). |
| B-13 | BindToClose accounting (sync Leaving, pending set, Loading counted, no load while closing) | accepted | §2.2, §7.2. |
| B-14 | Never Kick inside a transform; `Released` before every Kick | accepted | §2.2. Verified: `players.luau:248` kick → remove → synchronous flush. |
| B-15 | The live table = UpdateAsync's return value | accepted | §2.2 (the sim returns the decoded JSON). |
| B-16 | float32 trap → `AttrTime` | accepted | §3.2, §4.6, §7.3. |
| B-17 | The income loop never dies; runtime records only; dt cap; no yields | changed | Applied with a **fixed-step accumulator** (`MaxCatchUp = 3`) instead of crediting the measured `dt` directly. This keeps B-19's exact integer tenths and still never drifts (§3.3). |
| B-18 | Age derived from `GrowFrom`; price at the sale moment | accepted | D6, §3.3. |
| B-19 | Integer tenths for income, integer percents for rates | accepted | §3.1, §3.2 (`HomeRatePct`, `MarketRatePct`, `SellScalePct`). |
| B-20 | `MaxMoney = 1e15`; NaN guard in `FormatMoney`; formats past T | accepted | D10, §3.1, §3.2, §4.4. |
| B-21 | Loop cost: no concern; keep `MoneyChanged` trivial | accepted | §3.3. |
| B-22 | Stall rate from server samples (dwell + displacement) | changed | P2 → in Stage 3, simplified. No teleport exemptions: a displacement (or a new character) holds the stall rate for `MarketJump.Penalty` = 5 samples (BE-02), and legitimate teleports only move players away from stalls. The panel's market mode reads the sampled `SellRatePct` only (§4.4, R19). |
| B-23 | Remote/prompt checklist (Uid pattern, Denied from the bucket, `nobase`, prompts bucketed, no yields, `userIds > 0`) | accepted | §4.5, §4.3, §4.4, §2.2. |
| B-24 | Commit seq + escrow-ready serializer + the Stage 4 protocol + `Origin` | accepted | §2.2 API (`SaveSoon -> seq`, `CommittedSeq`, `Committed`, `OnSerialize`), §2.1 `Origin`, §4.8 protocol. |
| B-25 | `Stats.Spent` + the ledger invariant (warn, test oracle) | accepted | §2.1, §4.4, §7.0. `SetMoneyForTest` keeps the ledger. |
| B-26 | Slot write order, `Event` last, refresh only on `Event`, nil fields, monotonic `n`, `mount` kind, one event per frame | accepted | §4.6, §5.3, §7.3–7.4. |
| B-27 | Leak-proofing (prune the queue, one scheduler, `WaitLoaded` nil, no per-player connections, `_debugSizes`) | accepted | §2.2, §4.1, §7.0. |
| B-28 | Testability (headless `clientDelay`, patchable knobs, gap from the log, `StoreNameFor`, `restart`, chaos test, explicit hole tests) | accepted | §3.1 note, §7.0, §7.2, §7.2b. Verified: `clientDelay` (`players.luau:155`) and `boot(t, patches)` (`stage2_fishing.test.luau:61`) exist. |
| B-29 | Small things | mixed | **Migration backup:** changed, deferred to the first real migration (v2) as a rule in §2.3, because v1 has no migration to back up. **SaveSoon on Legendary/Mythic:** accepted (§4.2); the sell-all trigger is gone with K-2. **`LockStale = 150` + assert:** accepted. **"Broken" mode:** accepted (§2.2). **TooNew README note:** accepted (§2.3, Wave 3 E). **Reconcile dictionaries only:** accepted (§2.1). |
