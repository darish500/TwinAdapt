# TwinAdapt-PHM

A research-grade Prognostics and Health Management (PHM) framework built in MATLAB 2026 and Simulink, centered on a 30W photovoltaic (PV) panel + Sealed Lead-Acid (SLA) battery system. The project is being built progressively, one verified stage at a time, inside a single Simulink model file (`Reformable_AI.slx`), with the eventual goal of full digital-twin and adaptive health-monitoring capability.

## Repo contents

| File | Purpose |
|---|---|
| `Reformable_AI.slx` | The single Simulink model. All stages live here as subsystems. |
| `reformable_AI.m` | Base-workspace parameter definition script — run this (F5) before simulating. Originally Stage 1's PV parameter-extraction script only; now also holds Stage 2 and Stage 4 aging-rate constants (`k_Rs, k_Rsh, k_Iph, T_life`, and `k_R0, k_R1, k_Q, T_life_batt`). Everything downstream traces back to this one file. |
| `PV_Params_Stage1.mat` | Locked healthy-baseline PV parameters. |
| `PV_Params_Stage2.mat` | PV degradation scaling constants. |
| `Stage3_Battery_ParamDefinition.m` | Battery ECM parameter definition script — run this (F5) before simulating, it populates the base workspace. |
| `Battery_Params_Stage3.mat` | Saved output of the above — locked battery baseline parameters. |
| `getting_plots_stage2.m` | Fault-sweep validation script for Stage 5 — drives `FaultType_select`/`FaultSeverity_select` via `set_param`, logs all 7 fault outputs, and plots Rs/Rsh/Iph vs. time. |

## Build philosophy

- **One stage at a time.** Each stage has explicit acceptance criteria and is validated with real simulation output before the next stage begins.
- **Everything in one model.** Each stage is a subsystem added to the same `.slx`, not a separate file — this mirrors how the final integrated system will actually look.
- **No masked subsystems.** All parameters are explicit MATLAB Function inports / Simscape block fields, fed by top-level `Constant` blocks referencing base-workspace variables. Masking was tried early on and caused persistent UI issues — abandoned in favor of this explicit pattern, kept consistent across all stages since.
- **Parameters are never hardcoded.** Every physical constant (`Rs`, `Rsh`, `R0`, `Q`, `k_R0`, `T_life_batt`, etc.) lives in the base workspace, loaded via a `_ParamDefinition.m` script or `reformable_AI.m`, not typed as literals into block dialogs. This was briefly violated during early Stage 4 development (aging-rate constants were typed directly into Constant blocks) and corrected before Stage 4 was closed out — see Lessons Learned. It is currently also violated in Stage 5 (fault-severity gains) — see Stage 5 notes below.
- **Every workspace variable name must be globally unique across stages**, even when two stages have conceptually "the same" parameter (e.g. PV and battery both have a "life" constant). Reusing a name causes silent overwrites, not errors — see Lessons Learned.

## Stage status

### ✅ Stage 1 — PV Physical Model (single-diode)
Datasheet: `Voc=21.5V, Isc=1.82A, Vmp=17.5V, Imp=1.72A, Pmax=30W, Ns=36`. Parameters extracted via a 4-residual/3-unknown `lsqnonlin` fit including the correct MPP slope condition (`dP/dV=0`) — this was the key fix after several earlier fitting strategies failed. `Rsh=500Ω` fixed by design (non-identifiable from datasheet alone). All 5 acceptance criteria passed.

### ✅ Stage 2 — PV Degradation Model
Scalar aging index `D(t) = min(1, t/T_life)`, `T_life=25` (1 simulated second = 1 aging year). Linearly scales `Rs` (up), `Rsh` (down), `Iph_ref` (down) via `k_Rs, k_Rsh, k_Iph`. Outputs `Health_State` (1=Healthy to 5=Critical) via `D_index` thresholds. Fully wired into `PV_model`'s parameter inputs — this is a closed-loop integration, not a standalone calculation.

### ✅ Stage 3 — Battery_Model (1RC Equivalent Circuit Model)
SLA battery, 12V/7Ah. Built as a genuine **Simscape physical network** (Foundation Library electrical primitives: `R0`, `R1‖C1`, controlled voltage/current sources, voltage sensor, ground, solver config) — not just MATLAB Function logic — paired with a Simulink signal-side chain (Coulomb-counting `SOC`, `1-D Lookup Table` for `OCV`, `Product`+`Integrator` for `Power`/`Energy`). All 6 outports live (`Terminal_Voltage`, `Battery_Current`, `SOC`, `OCV`, `Battery_Power`, `Battery_Energy`). All 3 original test profiles validated:
- Test 1 (constant discharge): SOC/OCV/Vt behave correctly
- Test 2 (constant charge, off-100% start): SOC rises correctly, saturation clamp confirmed
- Test 3 (0.5A→2A→0.5A pulse): correct instant-step (`R0`) + decay/recovery (`R1‖C1`) behavior, τ≈33s

### ✅ Stage 4 — Battery_Degradation_Model
Mirrors Stage 2's pattern exactly: a single MATLAB Function block (`Battery_Aging_Model`), fed by an `Inport t` and Constants referencing base-workspace variables, computing `D_batt = min(1, t/T_life_batt)` with `T_life_batt=10`. Ages `R0` (×1.5 at EOL), `R1` (×1.6 at EOL), and `Capacity` (down to 80% at EOL) linearly via `k_R0, k_R1, k_Q`; applies a small, capped `OCV_deltaV` shift (0.05·D_batt) rather than redesigning the OCV lookup table. Outputs the same six-signal pattern as PV_Degradation_Model, plus `Battery_Health_State` (1–5, same threshold scheme as PV).

**Required a genuine architecture change to Stage 3**, not just a new subsystem: `R0_block`/`R1_block` (plain Simscape `Resistor`) had to be swapped to **Variable Resistor** blocks (fed via `Simulink-PS Converter`), because standard Resistor/Capacitor `R`/`C` fields are compile-time parameters and cannot vary during a run — a normal Gain-driven signal into them would silently do nothing. The SOC-rate `Gain = -100/(3600*Q)` block was similarly replaced with a `Divide` block so `Capacity_aged` could drive it as a live signal.

All 5 validation tests passed:
- **Test 1** (Capacity fade): 7.0 → 5.6 Ah over 0–10 years, smooth and monotonic
- **Test 2** (R0/R1 growth): 1.5×/1.6× at year 10, monotonic, no discontinuities
- **Test 3** (voltage sag, year 0 vs 10): 0.030 V → 0.049 V under constant 1A discharge
- **Test 4** (SOC depletion rate, year 0 vs 10): 0.0040 → 0.0049 %/s, ratio matches capacity ratio (1.25×) almost exactly
- **Test 5** (discrete health state): clean 1→2→3→4→5 progression at years ≈2/4/6/8, no skipped states

`Battery_Model` still runs standalone without errors; no duplicated battery model was created.

### ✅ Stage 5 — PV_Fault_Model
Inserted between `PV_Degradation_Model` and `PV_model`, intercepting the three lines that used to go straight from degradation into the physical model. Same explicit-inport pattern as every other stage — no masking, no parameter-scope UI.

**I/O:** 6 inports (`t`, `Rs_aged`, `Rsh_aged`, `Iph_ref_aged`, `FaultType_select`, `FaultSeverity_select`) → 7 outports (`Rs_fault`, `Rsh_fault`, `Iph_fault`, `Fault_Type`, `Fault_Severity`, `Fault_Active`, `Fault_TempRise`). `FaultType_select`/`FaultSeverity_select` are driven by root-level `Constant` blocks (manual selection for now, same pattern as `G_test`/`Tc_test`/`V_test`), not yet time-windowed.

**Core rule enforced in the MATLAB Function:** every fault branch modifies the *aged* parameter values (`Rs_aged`, `Rsh_aged`, `Iph_ref_aged`), never the Stage 1 nameplate values — keeps aging and faults mathematically separable, same principle as the Stage 2/4 aged-parameter feedback pattern.

Seven fault modes (`FaultType_select` 0–6), each scaling continuously with `FaultSeverity_select` (0–1):

| Code | Fault | Mechanism |
|---|---|---|
| 0 | Healthy | Pass-through |
| 1 | Partial Shading | `Iph_fault` reduced proportionally to severity |
| 2 | Soiling | Gentler `Iph_fault` reduction + gradual `Fault_TempRise` |
| 3 | Hotspot | `Rs_fault` increases (×4 at severity=1), real `Fault_TempRise` |
| 4 | PID | `Rsh_fault` collapses (up to 95% reduction) |
| 5 | Open Circuit | `Iph_fault → 0`, `Rs_fault` driven very high (both mechanisms) |
| 6 | Short Circuit | `Rsh_fault → ~0` (0.1% of aged value) |

**Validation:** swept all 7 cases via `set_param` in `getting_plots_stage2.m`, logged through `To Workspace` blocks (same Timeseries/`-1` convention), plotted Rs/Rsh/Iph vs. time. Confirmed each fault modifies only its intended parameter(s) while every other output stays pinned to the Stage 2 aged baseline — e.g. Hotspot: `Rs_fault` 0.0154→0.0462, `Rsh_fault`/`Iph_fault` unchanged; PID: `Rsh_fault` 380→199.5, `Rs_fault`/`Iph_fault` unchanged. All 6 acceptance test cases (Healthy, Shading, Hotspot, PID, Open Circuit, Short Circuit) passed.

**Known deviation from the "never hardcoded" rule:** the fault-severity gains (`k_hotspot=4.0`, `k_pid=0.95`, the 40°C/5°C temp-rise scalars, the Open/Short-circuit multipliers) are currently literals inside the MATLAB Function block, not base-workspace variables. Flagged, not yet resolved — candidate for a `PV_Fault_ParamDefinition.m` + `.mat` pair mirroring the Stage 3 battery pattern, before this is called fully consistent with the rest of the repo.

## Lessons learned (worth remembering before the next stage)

- **Simscape components don't inherit sensible defaults.** New Resistor/Capacitor blocks start at factory values (e.g. 1Ω, 1µF) — these must be explicitly set to workspace variables or the simulation will run "successfully" on the wrong physics, or blow up if the mismatch is severe enough.
- **Simscape block parameters (`R`, `C`, etc. on Foundation Library elements) are compile-time constants, not runtime signals**, even when their field references a workspace variable name. To make a physical parameter change *during* a single run (e.g. for continuous aging), swap to the block's Variable variant (Variable Resistor, Variable Capacitor) and drive it through a `Simulink-PS Converter`. A plain `Gain` block with a variable-name expression has the same limitation — replace with `Divide`/`Product` fed by a live signal instead.
- **Workspace variable names must be unique across stages, not just within one.** Two stages having a conceptually similar constant (e.g. PV's `T_life=25` and the battery's `T_life=10`) will silently collide if given the same name — MATLAB just overwrites, it doesn't error. This caused a real bug twice in this project: once when a Battery_Degradation_Model Constant block accidentally referenced PV's `T_life`, and again when both were defined under the same name inside `reformable_AI.m` itself. Fixed by renaming the battery's constant to `T_life_batt`.
- **Current/voltage source sign convention determines charge vs. discharge — verify it explicitly, don't assume.** A `-1 A` `I_batt` Constant was silently driving the circuit as a *charge* current in this model's polarity, which combined with `SOC_init=100` (already at the Integrator's upper saturation limit) caused SOC to read completely flat for an entire test run with no error or warning. Confirmed via `out.SOC_data.Data(1) == out.SOC_data.Data(end)` before concluding it was a real physics result.
- **Coarse output sampling (`tout`) can make a real effect look like zero.** A depletion-rate calculation using `find(t >= x, 1)` against a ~59-point log over 150 s returned exactly `0` twice — not because nothing was happening, but because both ends of a 0.5 s window landed on the same logged sample. `interp1` against exact time values, rather than nearest-logged-sample lookups, resolved it.
- **Signal logging via right-click → "Log signal data" and a `To Workspace` block are not interchangeable.** The former populates `out.logsout.getElement(...)`, not `out.signalname.Data`. To keep the established `out.signalname.Data` access pattern, use explicit `To Workspace` blocks (Timeseries format, sample time `-1`) — consistent with how PV_Degradation_Model was already logging.
- **Polarity belongs in the wiring, not in a sign flip** — for *source terminal* polarity specifically (swap the physical terminals rather than negating the driving signal upstream). Note this is distinct from the `I_batt` sign-convention issue above, which was a discharge/charge direction problem in the driving signal itself, not a terminal-wiring problem.
- **"Repeating Sequence" ≠ "Repeating Sequence Stair."** The former linearly interpolates between points (a ramp); the latter holds each value flat until the next timestamp (a true step). Easy to grab the wrong one from the library browser.
- **Scope y-axis auto-scaling can hide a correct signal.** Before concluding a signal is "flat" or "broken," check the expected magnitude of change against the axis range — several apparent bugs in this project turned out to be a signal moving correctly but too small to see at the current scale.
- **`.slx` files are just zip archives.** They can be unzipped and their internal XML (block diagram, parameters, wiring) inspected directly — useful for verifying actual model state rather than reasoning about it secondhand.
- **A subsystem's visual block layout order and its actual output port order can differ.** `PV_Degradation_Model`'s outports are declared `D_index(1), H_Pv(2), Iph_ref_aged(3), Rsh_aged(4), Rs_aged(5)` internally — reversed from a naive top-to-bottom read of the canvas. Wiring `PV_Fault_Model`'s inports against the wrong assumed order would have silently swapped `Rs_aged`↔`Iph_ref_aged`. Verified correct by checking each port's actual index (via `.slx` XML inspection) rather than trusting layout position.
- **Workspace variables don't persist across MATLAB sessions.** Always re-run the relevant `_ParamDefinition.m` script (or `load()` the `.mat`) after reopening MATLAB, before simulating.

## Roadmap (not yet built)

Per the original TwinAdapt-PHM architecture, `Battery_Model` is intentionally electrically isolated from `PV_model`/`PV_Degradation_Model`/`PV_Fault_Model` for now — they share only the root `Clock` (simulation-time reference, not a functional coupling). Both PV and battery have independent aging behavior (Stages 2 and 4), and the PV side now has independent fault behavior (Stage 5) on top of that. Future stages, in roughly the order they'll depend on each other:

1. **Battery_Fault_Model** — discrete fault injection for the battery side (thermal runaway, cell imbalance, over-discharge, sensor failures, short/open circuits — explicitly excluded from Stage 4 by design)
2. **Integrated Energy System** — the actual PV→Battery coupling (charging current from PV output into `I_batt`)
3. **High-Fidelity Digital Twin**
4. **Sensor Data Generator**
5. **Residual Engine**
6. **Dataset Generator**
7. **Adaptive TinyML**
8. **Health-Aware Optimization**
