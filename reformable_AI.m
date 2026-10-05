%% ===================== Stage1_PV_ParamExtraction.m (FIXED v6 — fixed Rsh, exact 3-eq solve) =====================
%clear; clc;

%% Physical constants
k_B = 1.380649e-23;
q   = 1.602176634e-19;
Eg  = 1.12;

%% Datasheet nameplate values (STC: 1000 W/m^2, 25 C)
Voc_ref  = 21.5;
Isc_ref  = 1.82;
Vmp_ref  = 17.5;
Imp_ref  = 1.72;
Pmax_ref = 30;
Tref_C   = 25;  Tref = Tref_C + 273.15;
Gref     = 1000;
Ns = 36;
n  = 1.3;
Ki = 0.0006;

Vt_ref = Ns*k_B*Tref/q;

%% ---- Rsh: FIXED at a literature-representative value (unidentifiable from datasheet alone) ----
% Justification (cite in your methodology): Rs/Rsh sensitivity analysis (this
% script's history) showed the datasheet's 4 operating points push Rsh toward
% its unconstrained optimum (>1 MOhm), i.e. Rsh is not identifiable from STC
% points alone for a healthy small c-Si module. We fix Rsh at a representative
% value from small-module PV literature and treat it as the HEALTHY BASELINE
% that Stage 5 fault/degradation models will reduce from.
Rsh = 500;   % ohm — literature-representative baseline for a healthy small c-Si module
T_life = 25;      % simulated years to end-of-life
k_Rs   = 0.5;     % Rs increases 50% by EOL
k_Rsh  = 0.6;     % Rsh decreases 60% by EOL
k_Iph  = 0.2;     % Iph decreases 20% by EOL
T_life_batt = 10; 

Q = 7;      % Ah   - nominal capacity (used by Coulomb counting)
V_nom        = 12;     % V    - nominal voltage
V_charge_max = 14.7;   % V    - cycle charging voltage (midpoint of 14.5-14.9 V range)
V_standby    = 13.65;  % V    - standby/float voltage (midpoint of 13.5-13.8 V range)
I_charge_max = 2.1;    % A    - maximum initial charging current

%% ---- Equivalent circuit parameters (HEALTHY baseline) ----
% Kept as separate scalar parameters (not hardcoded inline) so that a
% future Battery_Degradation_Model can grow R0/R1 and shrink C1 over
% time, mirroring how Rs/Rsh/Iph_ref were treated in the PV stages.
R0   = 0.03;      % Ohm  - internal (ohmic) resistance
R1   = 0.015;     % Ohm  - polarization (charge-transfer) resistance
C1   = 2200;      % F    - polarization capacitance
tau1 = R1 * C1;   % s    - RC time constant (~33 s) -- sanity check only

%% ---- OCV-SOC lookup table (healthy lead-acid characteristic) ----
% Ascending breakpoints, as required by Simulink's 1-D Lookup Table block.
SOC_bp  = [0 10 20 30 40 50 60 70 80 90 100];                       % % , ascending
OCV_tbl = [11.6 11.8 11.9 12.1 12.2 12.3 12.4 12.5 12.6 12.7 12.8]; % V , matches SOC_bp order

%% ---- Initial conditions ----
SOC_init = 100;   % %  - start fully charged (Test 1/2/3 all assume this)
Vp_init  = 0;     % V  - polarization voltage starts relaxed
k_R0 = 0.5;
k_R1 = 0.6;
k_Q = 0.2;

%% ===================== Stage 5: PV_Fault_Model parameters =====================
% Extracted from the literals hardcoded inside the PV_Fault_Model MATLAB
% Function block (chart_89) so they live in the base workspace like every
% other tunable in this file. Wire these into the block as Constant-block
% or base-workspace reads to close the "no hardcoding" deviation noted in
% the Stage 5 acceptance summary. Values are UNCHANGED from what the block
% currently uses -- this is an extraction, not a re-tune.
%
% FaultType_select codes: 0=Healthy 1=Shading 2=Soiling 3=Hotspot 4=PID
%                          5=OpenCircuit 6=ShortCircuit
k_soiling_Iph      = 0.3;    % frac  - soiling Iph reduction at full severity (gentler than shading)
TempRise_soiling   = 5;      % degC  - soiling max temp rise at full severity
k_hotspot          = 4.0;    % --    - hotspot Rs multiplier gain at full severity
TempRise_hotspot   = 40;     % degC  - hotspot max temp rise at full severity
k_pid              = 0.95;   % frac  - PID max Rsh reduction at full severity
k_open_Rs          = 50;     % --    - open-circuit series-resistance inflation gain
k_short_Rsh        = 0.999;  % frac  - short-circuit Rsh collapse at full severity

%% ===================== Stage 6: Battery_Fault_Model parameters =====================
% New. Battery_Fault_Model does not exist yet in Reformable_AI.slx -- these
% are the initial tunable values for its MATLAB Function block, following
% the same "Fault Parameter = Aged Parameter x Fault Multiplier" pattern
% as Stage 5, and the temp-rise table locked in the Stage 6 architecture
% discussion. Treat these as literature/engineering-judgment starting
% points (same status Rsh=500 had at Stage 1) -- adjust after Test 1-8
% acceptance runs if the resulting behavior looks unrealistic.
%
% FaultType_select codes: 0=Healthy 1=CellImbalance 2=OverDischarge
%                          3=OverCharge 4=ThermalRunawayOnset 5=InternalShort
%                          6=OpenCircuit 7=SensorFault
k_imbalance_R0     = 0.15;   % frac  - cell imbalance R0 increase at full severity
k_imbalance_OCV    = 0.05;   % frac  - cell imbalance OCV uncertainty band at full severity
TempRise_imbalance = 5;      % degC  - max temp rise, cell imbalance

k_overdischarge_Q  = 0.4;    % frac  - permanent capacity loss at full severity
k_overdischarge_R0 = 0.3;    % frac  - R0 increase at full severity
TempRise_overdischarge = 8;  % degC  - max temp rise, over-discharge

k_overcharge_R1    = 0.5;    % frac  - R1 increase at full severity
k_overcharge_OCV   = 0.05;   % V     - small OCV increase at full severity
TempRise_overcharge = 10;    % degC  - max temp rise, over-charge

k_runaway_R0       = 5.0;    % --    - thermal runaway R0 multiplier gain at full severity
TempRise_runaway   = 40;     % degC  - max temp rise, thermal runaway onset

k_short_R0         = 0.98;   % frac  - internal short R0 collapse at full severity
TempRise_short     = 35;     % degC  - max temp rise, internal short

k_open_R0          = 100;    % --    - open-circuit series-resistance inflation gain (battery side)

% Sensor-fault biases (Fault 7): applied to MEASUREMENTS, not battery physics
SensorBias_Temp    = 8;      % degC  - temperature sensor offset at full severity
SensorBias_Volt    = -0.4;   % V     - voltage sensor bias at full severity
SensorBias_Curr    = 0.05;   % frac  - current sensor bias at full severity

% Safety_Flag thresholds, applied to Battery_TempRise (deg C above nominal).
% Re-derived so they actually fall inside the fault library's max TempRise
% (40 degC at s=1 for Thermal Runaway, the hottest fault) -- the original
% 50/60/70 set was unreachable given this library and never would have
% fired. Emergency now triggers only for Thermal Runaway at high severity.
SafetyFlag_Warning_ThresholdC  = 25;  % degC -> Safety_Flag = 1 (Warning)
SafetyFlag_Critical_ThresholdC = 32;  % degC -> Safety_Flag = 2 (Critical)
SafetyFlag_Emergency_ThresholdC = 38; % degC -> Safety_Flag = 3 (Emergency)

%% ===================== Stage 7 (Step 1): PV_Sensor_Model parameters =====================
% Baseline sensor realism ONLY (noise, bias, drift, quantization, saturation
% range). No fault injection here -- that's PV_Sensor_Fault_Model, a later
% step. Each parameter's default is an engineering-judgment starting point
% (same status as Rsh=500 at Stage 1) -- adjust after acceptance Tests 1-7
% if a value looks unrealistic for your actual hardware.
%
% NOTE for Test 1 (zero-noise reproduction): to "disable" quantization,
% set the dX values very small (e.g. 1e-6) rather than exactly 0 --
% round(x/0) is undefined and will throw.

% --- Irradiance sensor (G) ---
noise_G = 5;      % W/m^2 std dev
bias_G  = 0;      % W/m^2 fixed bias
drift_G = 0;      % W/m^2 per second, bias growth rate
dG      = 1;      % W/m^2 ADC resolution
G_min   = 0;      % W/m^2 sensor range floor
G_max   = 1200;   % W/m^2 sensor range ceiling (allows above-1-sun readings)

% --- Module temperature sensor (Tc) ---
noise_Tc = 0.3;   % degC std dev
bias_Tc  = 0;     % degC fixed bias
drift_Tc = 0;     % degC per second, bias growth rate
dTc      = 0.1;   % degC ADC resolution
Tc_min   = -20;   % degC sensor range floor
Tc_max   = 90;    % degC sensor range ceiling

% --- PV voltage sensor (V) ---
noise_V_pv = 0.05;  % V std dev
bias_V_pv  = 0;     % V fixed bias
drift_V_pv = 0;     % V per second, bias growth rate
dV_pv      = 0.01;  % V ADC resolution
V_pv_min   = 0;     % V sensor range floor
V_pv_max   = 25;    % V sensor range ceiling (module Voc ~21.5V + margin)

% --- PV current sensor (I) ---
noise_I_pv = 0.02;  % A std dev
bias_I_pv  = 0;     % A fixed bias
drift_I_pv = 0;     % A per second, bias growth rate
dI_pv      = 0.005; % A ADC resolution
I_pv_min   = 0;     % A sensor range floor
I_pv_max   = 3;     % A sensor range ceiling (module Isc ~1.82A + margin)
%
% NOTE: PV_Measured_Power is NOT independently sensed -- it's derived as
% PV_Measured_Voltage * PV_Measured_Current inside the block, matching how
% a real deployed system would compute power from its actual V/I sensors
% rather than having a dedicated power transducer.

%% ===================== Stage 7 (Step 2): PV_Sensor_Fault_Model parameters =====================
% Measurement-layer faults, distinct from PV_Sensor_Model's baseline
% realism above and from PV_Fault_Model's physical-asset faults (Stage 5).
% One fault is injected onto ONE targeted channel per run (TargetSignal_select
% picks which of Irradiance/Temperature/Voltage/Current is affected), so
% these tunables are shared/generic rather than per-channel -- set the
% ones relevant to whichever channel+fault you're testing before each run,
% the same way V_pv_max was adjusted ad hoc for the Test 7 saturation check.
%
% FaultType_select: 0=Healthy 1=Bias(extra) 2=StuckAt 3=Dropout
%                   4=Intermittent 5=ForcedSaturation 6=ExcessiveNoise 7=ExtraDrift
% TargetSignal_select: 0=Irradiance 1=Temperature 2=Voltage 3=Current

StuckAt_G      = 250;   % W/m^2 -- stuck-sensor reading for Irradiance
StuckAt_Tc     = 10;    % degC  -- stuck-sensor reading for Temperature
StuckAt_V_pv   = 5;     % V     -- stuck-sensor reading for Voltage
StuckAt_I_pv   = 0.5;   % A     -- stuck-sensor reading for Current

IntermittentDropoutProb = 0.3;  % probability per sample at full severity

FaultSat_Min = 0;       % forced-saturation floor -- set per-test to the channel's realistic value
FaultSat_Max = 1e6;     % forced-saturation ceiling -- effectively "off" by default, set per-test

ExcessiveNoise_Sigma = 5;   % extra noise std dev at full severity -- set per-test to channel scale
ExtraDrift_Rate      = 0.1; % extra bias growth per second at full severity -- set per-test
FaultBias_Value      = 10;  % extra fixed bias at full severity -- set per-test to channel scale

%% ===================== Stage 7 (Step 3): Battery_Sensor_Model parameters =====================
% Baseline sensor realism ONLY (noise, bias, drift, quantization, saturation
% range), same pattern as PV_Sensor_Model above. No fault injection here --
% that's Battery_Sensor_Fault_Model, a later step. Ranges account for
% Stage 6 fault behavior (e.g. Thermal Runaway can push TempRise to 40degC
% on top of nominal, so T_batt_max allows margin above that).

% --- Battery terminal voltage sensor ---
noise_V_batt = 0.05;  % V std dev
bias_V_batt  = 0;     % V fixed bias
drift_V_batt = 0;     % V per second, bias growth rate
dV_batt      = 0.01;  % V ADC resolution
V_batt_min   = 0;     % V sensor range floor
V_batt_max   = 16;    % V sensor range ceiling (12V SLA, allows headroom above full charge)

% --- Battery current sensor ---
noise_I_batt = 0.02;  % A std dev
bias_I_batt  = 0;     % A fixed bias
drift_I_batt = 0;     % A per second, bias growth rate
dI_batt      = 0.005; % A ADC resolution
I_batt_min   = 0;     % A sensor range floor
I_batt_max   = 20;    % A sensor range ceiling (covers fault-driven current spikes, e.g. Internal Short)

% --- Battery temperature sensor ---
noise_T_batt = 0.3;   % degC std dev
bias_T_batt  = 0;     % degC fixed bias
drift_T_batt = 0;     % degC per second, bias growth rate
dT_batt      = 0.1;   % degC ADC resolution
T_batt_min   = -10;   % degC sensor range floor
T_batt_max   = 80;    % degC sensor range ceiling (covers +40degC Thermal Runaway TempRise on top of nominal)

%% ===================== Stage 7 (Step 4): Battery_Sensor_Fault_Model parameters =====================
% Measurement-layer faults for the battery side, mirroring
% PV_Sensor_Fault_Model exactly but for 3 channels instead of 4 (no
% irradiance equivalent on the battery side). Distinct _batt-suffixed
% names throughout so PV and battery sensor-fault tuning stay independent
% -- same reasoning as T_life vs T_life_batt.
%
% FaultType_select: 0=Healthy 1=Bias(extra) 2=StuckAt 3=Dropout
%                   4=Intermittent 5=ForcedSaturation 6=ExcessiveNoise 7=ExtraDrift
% TargetSignal_select: 0=Voltage 1=Current 2=Temperature

StuckAt_V_batt = 5;     % V     -- stuck-sensor reading for Voltage
StuckAt_I_batt = 0.5;   % A     -- stuck-sensor reading for Current
StuckAt_T_batt = 10;    % degC  -- stuck-sensor reading for Temperature

IntermittentDropoutProb_batt = 0.3;  % probability per sample at full severity

FaultSat_Min_batt = 0;      % forced-saturation floor -- set per-test to the channel's realistic value
FaultSat_Max_batt = 1e6;    % forced-saturation ceiling -- effectively "off" by default, set per-test

ExcessiveNoise_Sigma_batt = 5;   % extra noise std dev at full severity -- set per-test to channel scale
ExtraDrift_Rate_batt      = 0.1; % extra bias growth per second at full severity -- set per-test
FaultBias_Value_batt      = 10;  % extra fixed bias at full severity -- set per-test to channel scale

%% ---- Solve Rs, Iph, I0 exactly from 3 conditions: Isc, Voc, Imp ----
% x = [Rs, Iph, ln(I0)]
x0 = [0.4, Isc_ref, log(1e-8)];

opts = optimoptions('fsolve', 'Display','iter', 'FunctionTolerance',1e-14, 'StepTolerance',1e-14);

[x_sol, fval, exitflag] = fsolve(@(x) pv_residuals_3eq(x, Voc_ref, Isc_ref, Vmp_ref, Imp_ref, Vt_ref, n, Rsh), x0, opts);

Rs      = x_sol(1);
Iph_ref = x_sol(2);
I0_ref  = exp(x_sol(3));

fprintf('\n--- EXACT 3-EQ SOLVE (Rsh fixed=%.1f ohm), exitflag=%d ---\n', Rsh, exitflag);
fprintf('Rs      = %.4f ohm\n', Rs);
fprintf('Iph_ref = %.4f A\n', Iph_ref);
fprintf('I0_ref  = %.4e A\n', I0_ref);
fprintf('Residual norm = %.4e\n', norm(fval));

%% ---- Verification (including Pmax/MPP as an independent check, NOT a fitting constraint) ----
I_at_Vmp = solve_I_newton(Vmp_ref, Iph_ref, I0_ref, Rs, Rsh, n, Vt_ref);
fprintf('Model I at Vmp = %.4f A (target %.4f A, diff %.4f A)\n', I_at_Vmp, Imp_ref, I_at_Vmp - Imp_ref);

I_at_Voc = solve_I_newton(Voc_ref, Iph_ref, I0_ref, Rs, Rsh, n, Vt_ref);
fprintf('Model I at Voc = %.4f A (target 0 A)\n', I_at_Voc);

I_at_0 = solve_I_newton(0, Iph_ref, I0_ref, Rs, Rsh, n, Vt_ref);
fprintf('Model I at V=0 = %.4f A (target Isc = %.4f A)\n', I_at_0, Isc_ref);

Pmax_model = Vmp_ref * I_at_Vmp;
fprintf('Model Pmax = %.4f W (target %.4f W, diff %.4f W, %.2f%%)\n', ...
    Pmax_model, Pmax_ref, Pmax_model - Pmax_ref, 100*(Pmax_model-Pmax_ref)/Pmax_ref);

%% Save for Simulink
save('PV_Params_Stage1.mat', 'Rs','Rsh','Iph_ref','I0_ref','n','Vt_ref', ...
     'Ns','Ki','Eg','Tref','Gref','Voc_ref','Isc_ref','Vmp_ref','Imp_ref','Pmax_ref');

%% ===================== Stage 8 (Step 1): PV_Digital_Twin parameters =====================
% Independently-named copies of the Stage 1 reference physical parameters.
% Same numeric values today (calibrated/reference Twin, per the Stage 8
% doc's instruction to validate the baseline before introducing mismatch),
% but stored under separate variable names so they can be perturbed later
% (Test 7: Twin parameter mismatch) WITHOUT touching the physical model's
% own Rs/Iph_ref/I0_ref/etc -- that decoupling is the entire point.
%
% k_B and q are shared as-is (true universal physical constants, not
% tunable model parameters -- no independence concern there).
PV_Twin_Rs      = Rs;
PV_Twin_Rsh     = Rsh;
PV_Twin_Iph_ref = Iph_ref;
PV_Twin_I0_ref  = I0_ref;
PV_Twin_n       = n;
PV_Twin_Ns      = Ns;
PV_Twin_Ki      = Ki;
PV_Twin_Eg      = Eg;
PV_Twin_Tref    = Tref;   % Kelvin
PV_Twin_Gref    = Gref;   % W/m^2

save('PV_Twin_Params.mat', ...
    'PV_Twin_Rs','PV_Twin_Rsh','PV_Twin_Iph_ref','PV_Twin_I0_ref', ...
    'PV_Twin_n','PV_Twin_Ns','PV_Twin_Ki','PV_Twin_Eg','PV_Twin_Tref','PV_Twin_Gref', ...
    'k_B','q');

fprintf('--- Stage 8 Step 1 parameters saved (PV_Twin_Params.mat) ---\n');

%% ===================== Stage 8 (Step 3): Battery_Digital_Twin parameters =====================
% Independently-named copies of the Stage 3 healthy-baseline ECM values
% (same reasoning as PV_Twin_* above: identical numbers today, separate
% variable names so Test 7 can perturb the Twin's copy without ever
% touching R0/R1/C1/Q, which Battery_Degradation_Model actively ages).
% SOC_bp/OCV_tbl also copied independently (not shared) for the same
% reason, even though the OCV-vs-SOC curve is a known chemistry
% characteristic rather than a hidden state -- keeps PV and battery Twins
% architecturally symmetric for future mismatch experiments.
Battery_Twin_R0       = R0;
Battery_Twin_R1       = R1;
Battery_Twin_C1       = C1;
Battery_Twin_Capacity = Q;
Battery_Twin_SOC_bp   = SOC_bp;
Battery_Twin_OCV_tbl  = OCV_tbl;
Battery_Twin_SOC_init = SOC_init;   % % , Integrator IC for the SOC estimator
Battery_Twin_Vp_init  = Vp_init;    % V , Integrator IC for the polarization-voltage state (0 = relaxed)

save('Battery_Twin_Params.mat', ...
    'Battery_Twin_R0','Battery_Twin_R1','Battery_Twin_C1','Battery_Twin_Capacity', ...
    'Battery_Twin_SOC_bp','Battery_Twin_OCV_tbl', ...
    'Battery_Twin_SOC_init','Battery_Twin_Vp_init');

fprintf('--- Stage 8 Step 3 parameters saved (Battery_Twin_Params.mat) ---\n');

%% ===================== Stage 9 (Step 1): PV_Feature_Engineering (Group A+B) parameters =====================
% Instantaneous + magnitude features. No temporal buffering yet -- that's
% Group C, a separate step once the solver's variable-step timing is
% accounted for (confirmed: ode23t, variable-step -- rolling windows must
% buffer by elapsed TIME, not sample count).
%
% Normalization uses FIXED nameplate ratings (Isc_ref, Pmax_ref) as the
% denominator, not a live signal like PV_Twin_Current -- this is what
% makes the normalization itself always safe (a nameplate rating never
% approaches zero). Stage9_Min_Irradiance is a SEPARATE, purely
% interpretive flag: below this level the panel is barely generating
% (dawn/dusk regime for this panel's 1000 W/m^2 rating), so a small
% absolute residual there is less physically meaningful even though the
% normalized math itself never breaks.
Stage9_Min_Irradiance = 50;   % W/m^2 -- below this, PV generation is negligible (dawn/dusk regime)

save('Stage9_PV_InstantFeature_Params.mat', 'Stage9_Min_Irradiance');

fprintf('--- Stage 9 Step 1 parameters saved (Stage9_PV_InstantFeature_Params.mat) ---\n');

%% ===================== Stage 9 (Step 2): Rolling-window (Group C) parameters =====================
% Windows are in SECONDS, not sample counts -- required because the
% solver is ode23t (confirmed variable-step: ode23t is not a valid
% fixed-step solver name). Consecutive samples are unevenly spaced in
% time, so a fixed-count window would cover a different amount of real
% time depending on how fast the solver was stepping at that moment.
% The feature block buffers (time, value) pairs and trims by elapsed
% time, not by index.
Stage9_Window_Short  = 5;    % seconds -- fast-reacting, catches sudden spikes
Stage9_Window_Medium = 20;   % seconds -- general-purpose mean/std indicator
Stage9_Window_Long   = 60;   % seconds -- reserved for the Group D trend feature (not used in Group C)

% Fixed-size persistent buffer capacity (samples), generously sized so
% ode23t's adaptive stepping doesn't fill the buffer before it spans
% Stage9_Window_Medium seconds of real time. ASSUMPTION: 20000 samples is
% enough headroom for this model's step-size behavior over a 20s window.
% If Test 11 (startup/window validity) shows the buffer filling
% completely while covering LESS than Stage9_Window_Medium seconds of
% real time, this needs to be increased.
Stage9_Max_Buffer_Samples = 20000;

% Discrete sample time (seconds) for any MATLAB Function block holding
% persistent rolling-buffer state (like the Group C block above). ode23t
% is an implicit variable-step solver -- it evaluates candidate/trial
% time points internally before accepting a step, and a block with
% continuous (unsampled) inputs gets called on EVERY trial, not just
% accepted ones. That corrupts a persistent buffer's sense of elapsed
% time. Setting this block's own Sample Time (in its Block Parameters
% dialog, not the Symbols pane) to this value forces it to only actually
% execute once per this many real accepted seconds, insulating the
% buffer from solver-internal noise.
Stage9_Feature_SampleTime = 0.1;   % seconds

%% ===================== Stage 9 (Step 4): PV Twin operating-domain validity =====================
% Operationalizes the Stage 8 Test 6 finding: PV_Digital_Twin's
% Newton-Raphson solve diverges when the measured voltage exceeds what a
% healthy panel could physically produce (a sensor-fault bias pushed
% 17V -> 27V, past Voc~21.5V, and the residual came back as a
% non-physical 76.6A). Per Stage 9 Section 46, this does NOT fix that
% Stage 8 limitation -- it flags when the Twin is operating outside the
% domain it was validated for, so later PHM stages don't mistake solver
% breakdown for genuine physical degradation.
Stage9_PV_Voltage_Min = 0;            % V -- below this, no meaningful PV operation
Stage9_PV_Voltage_Max = 0.95*Voc_ref; % V -- safety margin below Voc_ref where the Newton-Raphson
                                       %      solve stays well-conditioned (documented Stage 8 finding)

save('Stage9_PV_TwinValidity_Params.mat', 'Stage9_PV_Voltage_Min', 'Stage9_PV_Voltage_Max');

fprintf('--- Stage 9 Step 4 parameters saved (Stage9_PV_TwinValidity_Params.mat) ---\n');

%% ===================== Stage 9 (Step 5): Battery_Feature_Engineering (Group A+B) parameters =====================
% Mirrors the PV Group A+B block, but only one residual exists on the
% battery side (Battery_Residual_Voltage -- Battery_Digital_Twin never
% produces a Current/Power prediction, per the Stage 8 design decision),
% so this block is correspondingly smaller.
%
% Battery_V_nominal is the normalization denominator, same safety
% reasoning as PV's Isc_ref/Pmax_ref: a FIXED reference, never a live
% signal that could approach zero. Computed from the battery's own
% characterization data (max(OCV_tbl), the fully-charged OCV) rather
% than a new hardcoded number, so it's tied to something already
% physically justified rather than an arbitrary constant.
Battery_V_nominal = max(OCV_tbl);   % V -- fully-charged OCV, used as the fixed normalization reference

save('Stage9_Battery_InstantFeature_Params.mat', 'Battery_V_nominal');

fprintf('--- Stage 9 Step 5 parameters saved (Stage9_Battery_InstantFeature_Params.mat) ---\n');

save('Stage9_Window_Params.mat', ...
    'Stage9_Window_Short','Stage9_Window_Medium','Stage9_Window_Long', ...
    'Stage9_Max_Buffer_Samples','Stage9_Feature_SampleTime');

fprintf('--- Stage 9 Step 2 parameters saved (Stage9_Window_Params.mat) ---\n');

%% Save Stage 2 (PV degradation) + Stage 4 (battery degradation) rate constants
save('PV_Degradation_Params.mat', 'T_life','k_Rs','k_Rsh','k_Iph');
save('Battery_Degradation_Params.mat', 'T_life_batt','k_R0','k_R1','k_Q');

%% Save Stage 5 (PV fault) parameters -- extracted from the previously hardcoded block literals
save('PV_Fault_Params.mat', ...
    'k_soiling_Iph','TempRise_soiling', ...
    'k_hotspot','TempRise_hotspot', ...
    'k_pid', ...
    'k_open_Rs', ...
    'k_short_Rsh');

%% Save Stage 6 (battery fault) parameters -- new, initial tunable values
save('Battery_Fault_Params.mat', ...
    'k_imbalance_R0','k_imbalance_OCV','TempRise_imbalance', ...
    'k_overdischarge_Q','k_overdischarge_R0','TempRise_overdischarge', ...
    'k_overcharge_R1','k_overcharge_OCV','TempRise_overcharge', ...
    'k_runaway_R0','TempRise_runaway', ...
    'k_short_R0','TempRise_short', ...
    'k_open_R0', ...
    'SensorBias_Temp','SensorBias_Volt','SensorBias_Curr', ...
    'SafetyFlag_Warning_ThresholdC','SafetyFlag_Critical_ThresholdC','SafetyFlag_Emergency_ThresholdC');

fprintf('\n--- Stage 5/6 fault parameters saved (PV_Fault_Params.mat, Battery_Fault_Params.mat) ---\n');

%% Save Stage 7 Step 1 (PV_Sensor_Model) parameters
save('PV_Sensor_Params.mat', ...
    'noise_G','bias_G','drift_G','dG','G_min','G_max', ...
    'noise_Tc','bias_Tc','drift_Tc','dTc','Tc_min','Tc_max', ...
    'noise_V_pv','bias_V_pv','drift_V_pv','dV_pv','V_pv_min','V_pv_max', ...
    'noise_I_pv','bias_I_pv','drift_I_pv','dI_pv','I_pv_min','I_pv_max');

fprintf('--- Stage 7 Step 1 parameters saved (PV_Sensor_Params.mat) ---\n');

%% Save Stage 7 Step 2 (PV_Sensor_Fault_Model) parameters
save('PV_Sensor_Fault_Params.mat', ...
    'StuckAt_G','StuckAt_Tc','StuckAt_V_pv','StuckAt_I_pv', ...
    'IntermittentDropoutProb', ...
    'FaultSat_Min','FaultSat_Max', ...
    'ExcessiveNoise_Sigma','ExtraDrift_Rate','FaultBias_Value');

fprintf('--- Stage 7 Step 2 parameters saved (PV_Sensor_Fault_Params.mat) ---\n');

%% Save Stage 7 Step 3 (Battery_Sensor_Model) parameters
save('Battery_Sensor_Params.mat', ...
    'noise_V_batt','bias_V_batt','drift_V_batt','dV_batt','V_batt_min','V_batt_max', ...
    'noise_I_batt','bias_I_batt','drift_I_batt','dI_batt','I_batt_min','I_batt_max', ...
    'noise_T_batt','bias_T_batt','drift_T_batt','dT_batt','T_batt_min','T_batt_max');

fprintf('--- Stage 7 Step 3 parameters saved (Battery_Sensor_Params.mat) ---\n');

%% Save Stage 7 Step 4 (Battery_Sensor_Fault_Model) parameters
save('Battery_Sensor_Fault_Params.mat', ...
    'StuckAt_V_batt','StuckAt_I_batt','StuckAt_T_batt', ...
    'IntermittentDropoutProb_batt', ...
    'FaultSat_Min_batt','FaultSat_Max_batt', ...
    'ExcessiveNoise_Sigma_batt','ExtraDrift_Rate_batt','FaultBias_Value_batt');

fprintf('--- Stage 7 Step 4 parameters saved (Battery_Sensor_Fault_Params.mat) ---\n');

%% ================= Local functions =================
function F = pv_residuals_3eq(x, Voc, Isc, Vmp, Imp, Vt, n, Rsh)
    Rs  = x(1);
    Iph = x(2);
    I0  = exp(x(3));

    r1 = Iph - I0*(safe_exp(Isc*Rs/(n*Vt)) - 1) - Isc*Rs/Rsh - Isc;      % I=Isc @ V=0
    r2 = Iph - I0*(safe_exp(Voc/(n*Vt)) - 1) - Voc/Rsh;                    % I=0   @ V=Voc
    r3 = Iph - I0*(safe_exp((Vmp + Imp*Rs)/(n*Vt)) - 1) - (Vmp + Imp*Rs)/Rsh - Imp;  % I=Imp @ V=Vmp

    F = [r1; r2; r3];
end

function y = safe_exp(x)
    y = exp(min(x, 700));
end

function I = solve_I_newton(V, Iph, I0, Rs, Rsh, n, Vt)
    I = Iph;
    for i = 1:100
        expTerm = safe_exp((V + I*Rs)/(n*Vt));
        f  = Iph - I0*(expTerm - 1) - (V + I*Rs)/Rsh - I;
        df = -I0*(Rs/(n*Vt))*expTerm - Rs/Rsh - 1;
        if df == 0 || isnan(df); I = NaN; return; end
        I_new = I - f/df;
        if isnan(I_new); I = NaN; return; end
        if abs(I_new - I) < 1e-9; I = I_new; return; end
        I = I_new;
    end
end