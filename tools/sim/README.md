# RbxSim — headless Roblox runtime emulator for Lune

RbxSim runs the game's real server `Script`s, `LocalScript`s and `ModuleScript`s from
`Place1.rbxl` (or a DataModel built in code) without Roblox Studio: virtual time,
any number of fake players, remote events, DataStores, GUIs, prompts and tools. It
has no physics and no rendering; it aims for faithful *game-logic* behaviour.

```
Lune 0.11.0 is required:  /opt/tools/l11/lune
```

## Quick start

```luau
-- tests/fishing.test.luau
return {
	["player gets a base"] = function(t)
		local sim = t.sim({ place = t.place })      -- t.place = <repo>/Place1.rbxl
		sim:StartServer()
		local p = sim:AddPlayer({ Name = "Alice", device = "phone" })
		sim:Advance(1)                               -- 1 virtual second (60 frames)
		t.ok(p:GetAttribute("BaseIndex"), "base assigned")
		sim:FireServer(p, "Cast", 0.5)               -- as if Alice's client fired it
		sim:Click(p, sim:Gui(p, "HUD.ShopButton"))   -- tap a GuiButton in her PlayerGui
		sim:AssertNoErrors()
	end,
}
```

Run tests (from any directory):

```
/opt/tools/l11/lune run tools/run_tests.luau                 # everything
/opt/tools/l11/lune run tools/run_tests.luau sim_selftest    # filter by file / test substring
/opt/tools/l11/lune run tools/run_tests.luau "stage1::two players"
/opt/tools/l11/lune run tools/run_tests.luau --inproc -v     # same process, show output
SIM_VERBOSE=1 /opt/tools/l11/lune run tools/run_tests.luau x # echo script print/warn/errors
```

The runner discovers `tests/*.test.luau` and `tests/sim_selftest*.luau`, runs each
file in its own Lune process, prints `PASS`/`FAIL`/`SKIP` per test (failures include
the assertion location and every script error captured by the test's sims) and exits
non-zero on any failure, crash, timeout (`SIM_TEST_TIMEOUT`, default 600 s per file)
or when filters match nothing.

A test file returns `{ [name] = function(t) end }` or a list of `{ name, fn }`.
`t` provides `t.eq(a, b, msg)` (deep), `t.neq`, `t.ok(v, msg)`,
`t.near(a, b, eps, msg)` (numbers, Vector2/3, CFrame), `t.match(s, pattern)`,
`t.throws(fn, pattern) -> message`, `t.fail`, `t.skip(reason)`, `t.log`,
`t.sim(opts)` (creates a tracked sim), `t.place`, `t.basePlace`, `t.root`.

## How it works

| File | Role |
|---|---|
| `init.luau` | `Sim` class: construction, frame loop, all test helpers |
| `scheduler.luau` | virtual clock, timers heap, deferred queue, context/script tagging of threads, error capture |
| `signal.luau` | RBXScriptSignal / RBXScriptConnection (userdata facades) |
| `proxy.luau` | script-facing instance proxies, property writes + change events, hierarchy events, Destroy, WaitForChild, client-local overlays |
| `members.luau`, `members/*.luau` | emulated class members resolved along the reflection class hierarchy |
| `runtime.luau` | which scripts run where (Roblox rules), compile/run, instance `require` with per-context cache and cycle detection |
| `env.luau` | per-context globals (task, wait, os, typeof, Random, TweenInfo, RaycastParams, DateTime, Enum, ...) |
| `players.luau` | join/leave, characters, StarterGui/StarterPack/StarterCharacterScripts, health/death/respawn, walking, tools |
| `remotes.luau`, `serialize.luau` | remote/bindable delivery between contexts, argument copying rules, DataStore value rules |
| `datastore.luau` | in-memory DataStore backend (`sim.DataStore`) |
| `world.luau` | CFrame moves, pivots, bounding boxes, raycasts, overlap queries |
| `rigs.luau` | optional R15/R6 rigs: Animator stand-in, forward kinematics per client view, RightGrip |
| `tween.luau`, `input.luau`, `collection.luau`, `misc.luau`, `random.luau`, `util.luau` | TweenService, input/CAS/prompts, CollectionService, sounds/animations, deterministic Random, helpers |

**Contexts.** One DataModel is shared by the server and all clients (replication is
instant). Every execution context (`"server"`, `"client:<Name>"`) has its own
`require` cache, `_G`, `shared` and globals. Each thread is tagged with its context
and owning script; spawned threads, coroutines and event handlers inherit the context
in which they were created/connected. `RunService:IsServer()/IsClient()` and
`Players.LocalPlayer` answer for the running context. Harness code (the test itself)
counts as the server.

**Why proxies instead of `implementProperty`.** In Lune 0.11.0
`roblox.implementMethod/implementProperty` are ignored for members that exist in the
reflection database (verified for `SetAttribute`, `Parent`, `Name`, `Position`), so
built-in mutations cannot be hooked, and derived properties (`Position`,
`Orientation`, `AbsoluteSize`, `Humanoid.Health`, ...) error with "missing default
value". Polling would also leave `Position` stale. Scripts and tests therefore get
`newproxy` userdata proxies (one per instance, stable identity, `typeof` →
`"Instance"`): property writes go through the sim, so `Changed`,
`GetPropertyChangedSignal`, `AttributeChanged`, `ChildAdded`, `DescendantAdded`,
`AncestryChanged`, `Destroying` … fire at write time (no polling, no latency) and
derived properties are computed. Lune's own `Destroy` makes instances unreadable, so
Destroy is emulated (fire `Destroying`, detach, lock `Parent`, disconnect, recurse) and
destroyed instances stay readable like in Roblox.

**Time.** Nothing sleeps. `sim:Step(dt)` runs one frame:
`RenderStepped`/`PreRender` + `BindToRenderStep` (clients) → `PreAnimation` → the emulated
Animator of rigged characters → `Stepped`/`PreSimulation` → humanoid walking, joints of rigged
characters (forward kinematics), tweens, prompt holds → `Heartbeat` → due timers (`task.wait/delay`, legacy
`wait`). Deferred work (event handlers, `task.defer`) is flushed after every phase,
mirroring `SignalBehavior = Deferred`. A timer never fires in the frame it was created
(`task.wait()` = one frame). `sim:Advance(seconds, step?)` repeats `Step`.

## Sim API

### Construction / lifecycle

`Sim.new(opts)`:

| option | meaning |
|---|---|
| `place` | path to `.rbxl`/`.rbxlx` (loaded with `roblox.deserializePlace`) |
| `game` | an existing Lune `DataModel` (default: a new empty one) |
| `seed` | RNG seed (default 1): `math.random`, `Random.new()` without seed, spawn choice, GUIDs, DataStore fail rate |
| `frameTime` | default frame length (1/60) |
| `epoch` | unix time at t=0 for `os.time`, `tick`, `DateTime`, `GetServerTimeNow` (default 1700000000) |
| `dataStore` | `sim.DataStore:Snapshot()` of a previous sim (simulate a server restart) |
| `remoteLatency` | one-way latency in seconds for remotes and for the server side of ProximityPrompt events (default 0) |
| `strictReplication` | client writes to server-owned instances raise an error |
| `destroyPlayerOnLeave` | `Destroy()` the Player on leave (default false: parented to nil, like legacy Roblox, so leaks stay visible) |
| `instantMoveTo` | `Humanoid:MoveTo` teleports (default: walks at `WalkSpeed`, 8 s timeout) |
| `removingOrder` | `"fifo"` (default: `Players.PlayerRemoving` handlers run in connection order) or `"reverse"` (last connected first). Roblox guarantees no order, so run order-sensitive leave code both ways |
| `verbose` | echo logs (also `SIM_VERBOSE=1`) |
| `placeId`, `gameId`, `gamePasses` | values for `game.PlaceId`, `game.GameId`, `UserOwnsGamePassAsync` (`{[userId] = {[passId] = true}}`) |

- `sim:StartServer()` — runs enabled server scripts (Legacy in `ServerScriptService`/`Workspace`, `RunContext.Server` anywhere but ServerStorage/Starter*), then starts clients of players added earlier.
- `sim:Step(dt?)`, `sim:Advance(seconds, step?)`, `sim:Flush()` (run queued handlers without advancing time), `sim:Time()`.
- `sim:WaitFor(predicate, timeout?, step?)` → steps until `predicate()` is truthy; returns its value.
- `sim:Run(fn, who?, timeout?)` → runs `fn` in a sim thread of a context (`nil`/`"server"` or a Player) and advances time until it returns; re-raises its error. Inside, Lune globals still apply — use `sim:Env(who).task.wait(...)` etc.
- `sim:Require(moduleScript, who?)`, `sim:Globals(who?)` (`_G` of a context), `sim:Env(who?)` (its globals), `sim:ContextName(who?)`, `sim:Typeof(v)`.
- `sim:Shutdown({ timeout = 30, kickPlayers = true, order = "closeFirst" })` → runs all `game:BindToClose` callbacks concurrently, removes players, advances until they finish → `{ completed, elapsed, pending }`. `order = "closeFirst"` (default) starts the callbacks first and then removes the players; `order = "playersFirst"` removes every player (firing `PlayerRemoving`, handlers run to their first yield) before the callbacks start, so they find `Players:GetPlayers()` empty. Roblox guarantees neither order.

### Instances

`sim.game`, `sim.workspace` are proxies; everything reached from them is a proxy and
behaves like in scripts (`part.Position = v`, `p:GetAttribute(...)`, `x:Destroy()`).
Proxy property writes from the harness queue events; call `sim:Flush()`/`Step` to run handlers.

- `sim:Find("ReplicatedStorage.Remotes.Cast", root?)`, `sim:Gui(player, "HUD.Money")`.
- `sim:Create(className, props?, parent?)` (raw construction, then parented with events).
- `sim:AddScript(parent, className, name, source, props?)` — add Script/LocalScript/ModuleScript; runs automatically if its location is runnable and the server has started.
- `sim:Wrap(raw)`, `sim:Unwrap(proxy)`.

### Players

- `sim:AddPlayer({ UserId, Name, DisplayName, device = "desktop"|"phone"|"tablet"|"console", viewport, clientDelay, characterDelay, AccountAge, MembershipType, rig = "R15"|"R6", joints = "Motor6D"|"AnimationConstraint" })` → Player. Fires `PlayerAdded`, then starts the client (ReplicatedFirst LocalScripts, StarterPlayerScripts → PlayerScripts, client RunContext scripts); with `CharacterAutoLoads` the character spawns on the next frame.
- `sim:RemovePlayer(p)` — `PlayerRemoving` (player still parented while handlers start), `CharacterRemoving`, character destroyed, client threads/connections killed, player parented to nil. `player:Kick(msg)` does the same and records `sim.Kicks`.
- `sim:LoadCharacter(p)`, `sim:KillCharacter(p)` (Health = 0 → `Died`, auto-respawn after `Players.RespawnTime`), `sim:GetCharacter/GetHumanoid/GetRoot(p)`, `sim:Teleport(p, cframeOrVector3)`, `sim:WalkTo(p, pos, timeout?)` → reached.
- `sim:SetDevice(p, name)`, `sim:SetViewport(p, Vector2)`, `sim:GetPlayers()`.

Characters: Model named after the player with `Humanoid` (Health/MaxHealth 100, WalkSpeed 16, JumpPower 50, JumpHeight 7.2, HipHeight 2, `Animator`), `HumanoidRootPart` (2×2×1, PrimaryPart) and `Head`, placed on `Player.RespawnLocation`, else a random enabled `SpawnLocation`, else (0, 10, 0). Each spawn re-clones `ResetOnSpawn` GUIs (others are cloned once), copies StarterPack into the Backpack and StarterCharacterScripts into the character. As in Roblox, StarterPlayerScripts/StarterGui/character contents are copied completely before their scripts start, so scripts may index siblings without `WaitForChild`.

Rigged characters (`tools/sim/rigs.luau`, opt-in per player: `rig = "R15"` or `"R6"`, R15 also
with `joints = "AnimationConstraint"` — the "Avatar Joint Upgrade" rig whose joint frames live in
`Attachment0/1` named `<Joint>RigAttachment`): body parts and joints with the standard names (R6
C0/C1 exact, R15 a block approximation: 15 parts, Root/Waist/Neck/Shoulders/Elbows/Wrists/Hips/
Knees/Ankles), `RightGripAttachment`, `Humanoid.RigType`. Every frame after `PreAnimation` an
Animator stand-in writes each joint's `Transform` (identity = idle, or the pose from
`sim:SetAnimatorPose(p, { [jointName] = CFrame })`, joint space) on the server and drops every
client-local `Transform`; `sim:ThrottleAnimator(p, n)` skips every n-th frame (then
`Animator.EvaluationThrottled` is true and `Transform` keeps the last write). After
`PreSimulation` forward kinematics places every part connected to the HumanoidRootPart through
Motor6D / AnimationConstraint / Weld (`Part1 = Part0 * C0 * Transform * C1:Inverse()`), once with
the replicated values and once per client that holds client-local joint values (its `Transform`,
`C0`, `C1` or attachment writes): that client sees its own pose, the server and everyone else the
replicated one (part CFrames written without events). Equipping a Tool on a rigged character adds
the `RightGrip` Weld (hand grip attachment → `Tool.Grip`), unequipping removes it. Minimal
characters are unaffected and cost nothing.

### Remotes and logs

- `sim:FireServer(p, remoteOrName, ...)`, `sim:InvokeServer(p, remoteOrName, ...)` → results (as that client).
- `sim.ClientEvents` / `sim.ServerEvents`: `{ time, player, remote, name, args (packed, .n), invoke? }` for every FireClient/FireAllClients/InvokeClient and FireServer/InvokeServer.
- `sim:LastClientEvent(p, name?)` → `args, entry`; `sim:ClientEventsFor(p?, name?)`, `sim:ServerEventsFor(p?, name?)`.

### Input, GUI, prompts, tools

- `sim:Click(p, button, { force })` — fires `MouseButton1Down/Up/Click` and `Activated(inputObject, 1)` in that player's client only. Without `force` it errors unless the button is in the player's PlayerGui, every ancestor GuiObject is `Visible`/`Interactable`, the ScreenGui is `Enabled`, and the button has non-zero size on screen. `sim:CanClick(p, button)` → `ok, reason`.
- `sim:TypeText(p, textBox, text, enterPressed?)`, `sim:PressKey(p, keyCode, { hold })`, `sim:ReleaseKey`, `sim:Tap(p, pos?)`, `sim:MouseClick(p)`, `sim:FireInput(p, "InputBegan", { KeyCode, UserInputType, UserInputState, Position }, gameProcessed?)`, `sim:TriggerAction(p, actionName, state?, inputObject?)`.
  Key/tap/click input is offered to ContextActionService bindings first (priority, most recent first; sunk input reaches UIS with `gameProcessedEvent = true`).
- `sim:HoldPrompt(p, prompt, seconds?, { release, ignoreDistance, ignoreEnabled })` → `triggered, cancelReason`. Holds are validated every frame (prompt enabled and in Workspace, `ProximityPromptService.Enabled`, character alive, HumanoidRootPart within `MaxActivationDistance`), `HoldDuration` is re-read every frame, `Triggered` fires once held long enough, `PromptButtonHoldEnded`/`TriggerEnded` fire on release or cancel. **The prompt is read as the holding client sees it**: a client-local `Enabled = false`, `MaxActivationDistance = 0` (0 or less is never in range) or `HoldDuration` written by that client's LocalScripts applies to its holds only, so a prompt a client hid cannot be held there ("prompt disabled" / "out of range (5.0 > 0.0)"); `ignoreEnabled` / `ignoreDistance` skip those checks, local values included. Events reach the holding client at once and the server after `remoteLatency` (in the order they happened; with no latency both in the same frame), plus `ProximityPromptService.Prompt*`. Non-blocking: `sim:BeginHold(p, prompt) -> hold` (`hold.triggered`, `hold.active`, `hold.cancelReason`), `sim:ReleasePrompt(p, prompt)`, `sim:CanUsePrompt(p, prompt, opts?)`.
- `sim:FirePromptEvent(p, prompt, kind)` with `kind` = `"HoldBegan"`, `"HoldEnded"`, `"Triggered"` or `"TriggerEnded"`: one prompt event as the player's client would send it (an exploit's `fireproximityprompt`, a HoldBegan from 200 studs, a HoldEnded before its Triggered). It reaches the **server only** (the prompt's event and its `ProximityPromptService` twin; the sender's own LocalScripts hear nothing), with **no validation** (Enabled, range, alive, hold time, a hold in progress), after `remoteLatency` like a real one, and successive calls arrive in call order. It never starts or ends a sim hold. A player who already left may still send one (an event in flight when he disconnected: the server sees a `Player` whose `Parent` is nil).
- `sim:EquipTool(p, toolOrName)`, `sim:ActivateTool(p, tool?)` (`Activated`/`Deactivated` on server + owner client), `sim:UnequipTools(p)`; `Equipped`/`Unequipped` fire when a Tool moves into/out of a character.
- `sim:Touch(partA, partB)` fires `Touched` on both.

### DataStores (`sim.DataStore`)

`FailNext(count, message?, ops?)`, `SetFailRate(p, message?)`, `SetLatency(s)` (default 0.05),
`SetEnabled(false)` (Studio-API-access error), `SetWriteCooldown(s)` (default 6 s per key;
faster writes warn and wait), `Peek(store, key, scope?)`, `Poke(store, key, value, scope?)`,
`Keys(store)`, `Snapshot()`, `Calls` (`{op, store, scope, key, time, failed?, landed?}`),
`CountCalls(op?, store?)`, `ClearCalls()`.

Per key (any store; for "one side's save fails or is slow while the other's succeeds"):

- `FailKey(key, count?, message?, opts?)`: the next `count` (default 1; `math.huge` = until
  cleared; `0` clears the key) requests on that key fail with `message` (default the 502 text).
  `opts` limits it to some operations — `{ "UpdateAsync", "SetAsync" }` or `opts.ops` — and
  `opts.after = true` makes each an **ambiguous commit**: the request completes (the write
  lands, `Peek` shows it) and then the call errors (`Calls` entry `failed = true, landed =
  true`). A key's failures are taken before `FailNext`'s, one per request.
- `SetKeyLatency(key, seconds?)`: that key's requests wait `seconds` instead of `SetLatency`'s
  (`0` = no wait); `nil` clears it.

Scripts get `GetDataStore/GetGlobalDataStore` with `GetAsync`, `SetAsync`, `UpdateAsync`
(transform may return nil to cancel; yielding inside it errors), `RemoveAsync`,
`IncrementAsync`; values are deep-copied through JSON and validated (no userdata,
functions, NaN/inf, invalid UTF-8, mixed/sparse tables or non-string keys; 4 MB, keys ≤ 50
chars). Requests are server-only. `GetRequestBudgetForRequestType` returns 100.
Ordered/versioned/listing APIs raise "not supported".

### Diagnostics

- `sim.Errors` `{ time, context, message, traceback, source }` — every uncaught error in any thread, script compile errors, module load failures, BindToClose failures. `sim:AssertNoErrors({ warnings = true? })`, `sim:FormatErrors()`, `sim:ClearErrors()`.
- `sim.Logs` (`print`/`warn`/`error` with context), `sim.Warnings` (script `warn`, infinite-yield warnings, remote serialization warnings, DataStore throttling), `sim.Notes` (replication notes), `sim:Output(contextName?)`, `sim:PrintLogs(kind?)`.
- `sim:CountConnections(filter?)` — live connections; filter `"server"`, `"client"`, a context name, a Player or `function(conn)`. `sim:ConnectionReport(filter?)` / `sim:FormatConnections()` group them by signal, context and owning script — use before/after `RemovePlayer` to find leaks.
- `sim.ClientWrites` — client writes to instances the client does not own (see below).
- Other logs: `sim.TerrainOps` (`{op, args, time}`), `sim.Kicks`, `sim.CoreCalls` (StarterGui:SetCore), `sim.Purchases`, `sim.Teleports`, `sim.Badges`.
- `sim:SetRaycastHandler(fn(origin, dir, params, default))` overrides `Workspace:Raycast` (call `default(...)` to fall back).

## Script environment

Each script gets `game/workspace/script`, instance `require` (per-context cache; errors
for asset ids, server-only modules on clients, cycles —
`Requested module was required recursively: A -> B -> A` — and modules not returning
exactly one value), virtual `task` (`spawn`, `defer`, `delay`, `wait`, `cancel`,
`synchronize`/`desynchronize` no-ops), legacy `wait/delay/spawn`, `tick`, `time`,
`elapsedTime`, `os` (`time`/`clock` virtual; `date`, `difftime`), `print`/`warn`
(captured), Roblox `typeof`, `Instance.new/fromExisting`, all Lune datatypes
(`Vector3`, `CFrame`, `Color3`, `UDim2`, `BrickColor`, `NumberSequence`, `Font`, ...),
a wrapped `Enum` (`Enum.KeyCode.Unknown` maps to Lune's value-0 item `None`;
`FromName`/`FromValue`), deterministic `Random` and `math.random`, `TweenInfo`,
`RaycastParams`, `OverlapParams`, `DateTime`, `PathWaypoint`, `settings`,
`UserSettings`, `version`, `_G`/`shared` per context, `debug` (+ no-op
`profilebegin/profileend`), `coroutine` (threads inherit context), standard libs.

## Emulated engine surface (highlights)

- **Instance**: all events above, `GetAttributeChangedSignal`, `GetPropertyChangedSignal` (validated), `SetAttribute/GetAttribute(s)`, `Destroy` (Roblox semantics), `ClearAllChildren`, `Clone` (respects `Archivable`), `WaitForChild(name, timeout?)` (virtual-time, infinite-yield warning after 5 s), `FindFirstDescendant`, `AddTag/RemoveTag`; built-ins (`FindFirstChild*`, `GetChildren`, `IsA`, ...) pass through; reading a property Lune has no default for returns a type-appropriate default; numbers/strings coerce on assignment like Roblox; circular parenting errors.
- **BasePart/Model/PVInstance**: `CFrame`, `Position`, `Orientation`, `Rotation`, `BrickColor`, `Mass`, velocities (stored), `GetPivot/PivotTo` (rigid move of all parts; pivot = PrimaryPart × PivotOffset, else `WorldPivotData`, else bounding-box centre which then persists), `GetBoundingBox`, `GetExtentsSize`, `MoveTo`, `TranslateBy`, `SetPrimaryPartCFrame`, `ScaleTo/GetScale`; moving a character's HumanoidRootPart moves the whole character. Attachments: `WorldPosition/WorldCFrame/...`.
- **Workspace**: built-in `Raycast` (oriented boxes for parts with `CanQuery`, terrain volumes recorded from `Fill*`; `RaycastParams` filters, `IgnoreWater`, `RespectCanCollide`), `Spherecast/Blockcast/Shapecast` (as rays), `FindPartOnRay*`, `GetPartBoundsInBox/InRadius`, `GetPartsInPart` (AABB), `GetServerTimeNow`, `DistributedGameTime`, `BulkMoveTo`; `Terrain` fill/clear calls are recorded; `Camera.ViewportSize` follows the client's device, `WorldToViewportPoint`/`ScreenPointToRay` use a 70° pinhole camera (the "screen" variants return the same px as the "viewport" ones: RbxSim's `AbsolutePosition` is in viewport px too, so `WorldToScreenPoint(p) - gui.AbsolutePosition` matches Roblox).
- **Humanoid**: `Health` (clamped, `HealthChanged`, `Died` once, Dead state), `TakeDamage` (ForceField aware), `MoveTo` (walks; `MoveToFinished`), `GetState/ChangeState`, `EquipTool/UnequipTools`, `LoadAnimation` (tracks with timing; `SimLength` attribute on the Animation sets the length), `RootPart`.
- **Players/Player**: listed above; `GetMouse()` (PlayerMouse with Hit/Target stubs), group/friends stubs, `DistanceFromCharacter`.
- **Remotes**: `RemoteEvent`/`UnreliableRemoteEvent` (`FireServer`, `FireClient`, `FireAllClients`; events fired before anyone listens are queued per receiver), `RemoteFunction` (`InvokeServer`/`InvokeClient` yield until the callback (set via `OnServerInvoke`/`OnClientInvoke`) returns; errors propagate to the caller; waits for a callback to be set; `InvokeClient` fails if the player leaves), `BindableEvent/BindableFunction` (same-context only). Serialization: tables deep-copied, metatables dropped, functions/threads/signals/cyclic tables raise, mixed or sparse arrays keep only the array part (warning), non-string dictionary keys become strings (warning), instances by reference except server-only or unparented instances sent to clients (arrive as `nil`, noted).
- **RunService**: `IsServer/IsClient/IsStudio(true)/IsRunning(true)`, `Heartbeat`, `Stepped`, `PreAnimation`, `PreSimulation`, `PostSimulation`, client-only `RenderStepped`/`PreRender`/`BindToRenderStep`.
- **TweenService**: `Create` (validates properties/types), per-frame interpolation with Roblox easing styles/directions, `RepeatCount`, `Reverses`, `DelayTime`, `Play/Pause/Cancel`, `PlaybackState`, `Completed(state)`, newer tweens cancel older ones on the same property (per context: each client has its own TweenService, so two clients tweening the same server part never cancel each other), `GetValue`; legacy `GuiObject:TweenSize/TweenPosition/TweenSizeAndPosition` with callbacks.
- **GUI**: `AbsoluteSize/AbsolutePosition` from UDim2 + AnchorPoint + SizeConstraint + UIPadding + UISizeConstraint + UIAspectRatioConstraint + basic UIListLayout/UIGridLayout placement against the player's viewport (desktop 1280×720, phone 844×390, tablet 1024×768, console 1920×1080; 58 px top inset unless `IgnoreGuiInset`), `AbsoluteContentSize`, `TextBounds` (≈ 0.5 × TextSize per character), `TextFits`, GuiButton/GuiObject/TextBox events.
- **Input**: `UserInputService` device flags per client, `InputBegan/Ended/Changed`, touch events, `IsKeyDown`, `GetKeysPressed`, `GetLastInputType`, ...; `ContextActionService` bindings and info.
- **Others**: `ProximityPrompt(Service)`, `CollectionService` (`GetTagged`, instance added/removed signals incl. tagged instances entering/leaving the DataModel), `Debris`, `HttpService` (`GenerateGUID`, Roblox-style `JSONEncode` (`{}` → `[]`), `JSONDecode`, `UrlEncode`; HTTP disabled), `Sound` (play/stop/ended timing via `SimTimeLength` attribute), `StarterGui:SetCore*`, `GuiService:GetGuiInset`, `TextService`, `MarketplaceService`, `PhysicsService`, `PathfindingService` (straight-line paths), `Teams`, `TeleportService`, `BadgeService`, `PolicyService` stubs.

## Fidelity limits and known differences

- **No physics or rendering.** Parts move only when code moves them; nothing falls, collides or is touched automatically (`sim:Touch` exists). Welds/constraints are not simulated except that moving a character's HumanoidRootPart carries the character. Humanoid walking is a straight line at `WalkSpeed` ignoring obstacles; no jumping/falling.
- **Replication is instant and the DataModel is shared.** Exceptions emulated: ServerStorage/ServerScriptService look empty to clients, server-only instances arrive as `nil` through remotes, and a client's writes to instances it does not own (properties, attributes, part CFrames) stay **client-local** (visible to that client only) and are listed in `sim.ClientWrites` (`strictReplication` turns them into errors). As in Roblox, a replicated write that **changes** the value (the server's, or the owner's) overwrites every client-local value of that property / attribute / part CFrame and fires the change on each client whose view changed; a write of the value the instance already has does not replicate, so the local value stays. (So a client filter that must survive server writes uses a property the server never writes, e.g. a local `MaxActivationDistance = 0` instead of `Enabled = false`.) "Owned" = created by that client, inside its PlayerGui/PlayerScripts/Backpack, the camera, Lighting/SoundService/StarterGui, or physical properties (CFrame, Position, velocities) of its own character's parts (not e.g. attachment frames, joint `Transform` / `C0`: those stay client-local like in Roblox). Attachment `WorldPosition`/`WorldCFrame` read the running client's view. Tweens write in the context that created them. Not emulated: client `Parent`/`Destroy`/`Health` changes on server instances (applied globally, still reported), client-created instances being invisible to the server, and client edits inside its PlayerGui being invisible to server code that reads the GUI.
- **Deferred signals only** (`Workspace.SignalBehavior` is ignored). Handlers queued during `Destroy` still run although the connections are then disconnected. Events fired from the harness run on the next `sim:Flush()`/`Step`. Handlers of one event start in connection order (Roblox promises none; `removingOrder = "reverse"` flips `Players.PlayerRemoving`).
- **No preemption.** A script looping without yielding hangs the process (the runner's per-file timeout catches it). There is no script execution timeout or re-entrancy depth limit beyond a 200 000-item flush guard.
- **ProximityPrompts** have no automatic `PromptShown/PromptHidden`, `Exclusivity` (one player may hold two prompts at once) or line-of-sight (`RequiresLineOfSight` is ignored; Roblox defaults it to true); distance is measured from the HumanoidRootPart to the prompt's parent part/attachment/model pivot (the replicated position; the prompt's properties as the holding client sees them). A hold of a player who leaves vanishes without `PromptButtonHoldEnded`. `KeyboardKeyCode` presses do not start holds (use `HoldPrompt` / `InputHoldBegin`).
- **GUI layout** is approximate: no AutomaticSize, text wrapping, UIScale, UIFlexItem, alignment in list/grid layouts or ScrollingFrame clipping; `TextBounds` is an estimate.
- **Raycasts/overlaps** treat every part as its oriented box (spheres, wedges, meshes, unions too); overlap queries compare axis-aligned bounds. Terrain exists only as the recorded `Fill*` volumes.
- **Players**: no avatar appearance or accessories; limbs only with the `rig` option (default character = HumanoidRootPart + Head + Humanoid + Animator); the Animator stand-in plays no AnimationTracks (only `SetAnimatorPose`); no IKControl solver. Whole-number attribute values are stored with float32 precision by Lune (keep server times like `CastTime` fractional in tests). Player objects are parented to nil, not destroyed, on leave unless `destroyPlayerOnLeave`.
- **Lune enum database** differs slightly from Roblox (e.g. `KeyCode.Unknown` is `KeyCode.None`, value 0, so its `Name` is `"None"`).
- **Script globals are per script but `getfenv()` returns a Lune-created wrapper table.** `loadstring` is unavailable. `require(assetId)` is unsupported.
- **DataStores** are a single in-memory backend per sim with simplified throttling (per-key write cooldown only; no request budgets or queue drops).
- **Errors** inside sim emulation code surface as script errors at the calling line (with the sim frame in the traceback).
- Not implemented: MemoryStore, MessagingService, OrderedDataStore queries, versioned DataStore APIs, TextChatService, Actors/parallel Luau (ConnectParallel = Connect), animations beyond timing, sound playback, Camera manipulation effects.

## Notes for code that builds places with Lune

Learned while building the sim (Lune 0.11.0): setting `part.Position` on a raw Lune
instance stores a separate value and does **not** move `CFrame` (set `CFrame`
instead); reading `Position`, `Orientation`, `AbsoluteSize`, `Humanoid.Health`,
`ScreenGui.IgnoreGuiInset`, `game.PlaceId`, … on raw instances errors ("missing
default value") until assigned; `Destroy()` makes a Lune instance unreadable; Lune
allows circular parenting without an error; `implementProperty/implementMethod` cannot
override reflected members.
