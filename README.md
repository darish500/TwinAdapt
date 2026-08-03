# TwinAdapt-PHM

A research-grade Prognostics and Health Management (PHM) framework built in MATLAB 2026 and Simulink, centered on a 30W photovoltaic (PV) panel + Sealed Lead-Acid (SLA) battery system. The project is being built progressively, one verified stage at a time, inside a single Simulink model file (`Reformable_AI.slx`), with the eventual goal of full digital-twin and adaptive health-monitoring capability.

## Repo contents

| File | Purpose |
|---|---|
| `Reformable_AI.slx` | The single Simulink model. All stages live here as subsystems. |
| `reformable_AI.m` | Stage 1 parameter extraction script (single-diode PV model fit). |
| `PV_Params_Stage1.mat` | Locked healthy-baseline PV parameters. |
| `PV_Params_Stage2.mat` | PV degradation scaling constants. |
| `Stage3_Battery_ParamDefinition.m` | Battery ECM parameter definition script — run this (F5) before simulating, it populates the base workspace. |
| `Battery_Params_Stage3.mat` | Saved output of the above — locked battery baseline parameters. |

## Build philosophy

- **One stage at a time.** Each stage has explicit acceptance criteria and is validated with real simulation output before the next stage begins.
- **Everything in one model.** Each stage is a subsystem added to the same `.slx`, not a separate file — this mirrors how the final integrated system will actually look.
- **No masked subsystems.** All parameters are explicit MATLAB Function inports / Simscape block fields, fed by top-level `Constant` blocks referencing base-workspace variables. Masking was tried early on and caused persistent UI issues — abandoned in favor of this explicit pattern, kept consistent across all stages since.
- **Parameters are never hardcoded.** Every physical constant (`Rs`, `Rsh`, `R0`, `Q`, etc.) lives in the base workspace, loaded from a `.mat` file via a dedicated `_ParamDefinition.m` script for each stage. This means degradation/aging stages only need to change parameter values, not redesign blocks.

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

## Lessons learned (worth remembering before the next stage)

- **Simscape components don't inherit sensible defaults.** New Resistor/Capacitor blocks start at factory values (e.g. 1Ω, 1µF) — these must be explicitly set to workspace variables or the simulation will run "successfully" on the wrong physics, or blow up if the mismatch is severe enough.
- **Polarity belongs in the wiring, not in a sign flip.** When a current/voltage source comes out backwards, swap its physical terminals rather than negating the driving signal upstream.
- **"Repeating Sequence" ≠ "Repeating Sequence Stair."** The former linearly interpolates between points (a ramp); the latter holds each value flat until the next timestamp (a true step). Easy to grab the wrong one from the library browser.
- **Scope y-axis auto-scaling can hide a correct signal.** Before concluding a signal is "flat" or "broken," check the expected magnitude of change against the axis range — several apparent bugs in this project turned out to be a signal moving correctly but too small to see at the current scale.
- **`.slx` files are just zip archives.** They can be unzipped and their internal XML (block diagram, parameters, wiring) inspected directly — useful for verifying actual model state rather than reasoning about it secondhand.
- **Workspace variables don't persist across MATLAB sessions.** Always re-run the relevant `_ParamDefinition.m` script (or `load()` the `.mat`) after reopening MATLAB, before simulating.

## Roadmap (not yet built)

Per the original TwinAdapt-PHM architecture, `Battery_Model` is intentionally electrically isolated from `PV_model`/`PV_Degradation_Model` for now — they share only the root `Clock` (simulation-time reference, not a functional coupling). Future stages, in roughly the order they'll depend on each other:

1. **Battery_Degradation_Model** — capacity fade, internal resistance growth, SOH estimation (mirrors the PV degradation pattern)
2. **Integrated Energy System** — the actual PV→Battery coupling (charging current from PV output into `I_batt`)
3. **Battery_Fault_Model** / PV fault injection
4. **Digital Twin** logic
5. **Sensor Data Generator**
6. **Residual Engine**
7. **Dataset Generator**
8. **Adaptive TinyML**
9. **Health-Aware Optimization**
