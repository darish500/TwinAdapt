%% ===================== Stage3_Battery_ParamDefinition.m =====================
% Defines healthy-baseline electrical parameters for the Battery_Model
% (First-Order Equivalent Circuit Model, 1RC ECM) and saves them to
% Battery_Params_Stage3.mat for use as base-workspace Constant-block
% sources inside Reformable_AI.slx (same pattern as Stage 1 / Stage 2).

%clear; clc;

%% ---- Battery nameplate spec (Sealed Lead-Acid, 12 V / 7 Ah) ----
Q            = 7;      % Ah   - nominal capacity (used by Coulomb counting)
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

%% ---- Save for Simulink ----
save('Battery_Params_Stage3.mat', ...
    'Q','V_nom','V_charge_max','V_standby','I_charge_max', ...
    'R0','R1','C1','tau1', ...
    'SOC_bp','OCV_tbl', ...
    'SOC_init','Vp_init');

fprintf('\n--- Stage 3 Battery parameters saved to Battery_Params_Stage3.mat ---\n');
fprintf('Q = %.1f Ah, R0 = %.3f Ohm, R1 = %.3f Ohm, C1 = %.0f F\n', Q, R0, R1, C1);
fprintf('R1*C1 time constant = %.1f s (expect voltage recovery on this timescale after a pulse)\n', tau1);
fprintf('OCV table: %d breakpoints from %.0f%% to %.0f%% SOC\n', numel(SOC_bp), SOC_bp(1), SOC_bp(end));