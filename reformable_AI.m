%% ===================== Stage1_PV_ParamExtraction.m (FIXED v6 — fixed Rsh, exact 3-eq solve) =====================
clear; clc;

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