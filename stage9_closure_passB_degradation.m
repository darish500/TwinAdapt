function stage9_closure_passB_degradation()
% stage9_closure_passB_degradation  Stage 9 Closure Pass B -- isolated
% PV and Battery degradation scenarios, requested explicitly because the
% Healthy_Baseline run (which sweeps both domains' aging together across
% its own timeline) cannot answer "what happens when degradation is the
% ONLY changing variable in ONE domain, with everything else controlled."
%
% Scenario B: PV ages normally. Battery aging FROZEN (k_R0=k_R1=k_Q=0,
%             so R0_aged/R1_aged/Q stay pinned at their t=0 reference
%             value the whole run). No asset faults, no sensor faults,
%             G fixed at 1000 W/m^2 (controlled environment).
%
% Scenario C: mirror image -- Battery ages normally, PV aging FROZEN
%             (k_Rs=k_Rsh=k_Iph=0). Same controls otherwise.
%
% These are compared against the existing Healthy_Baseline run (loaded
% from Stage9_FeatureDataset.mat, already on disk from the main dataset
% build) to check the actual claim this closure pass exists to verify:
% in Scenario B the PV residual should behave like Healthy_Baseline's own
% PV side (since PV ages the same way in both) while the Battery residual
% should stay flat/uncorrelated with time (since R0_aged is pinned);
% Scenario C should show the mirror pattern.

cfgB = struct('Freeze_Battery_Aging', true, 'G_test', 1000, ...
    'Scenario_Name','Scenario_B_PV_Degradation_Isolated', ...
    'Asset_State','PV_Degradation_Only', 'Sensor_State','Healthy', ...
    'Environment_State','Nominal_G1000_Controlled', 'Twin_State','Reference');
T_B = stage9_run_scenario_v3(cfgB);

cfgC = struct('Freeze_PV_Aging', true, 'G_test', 1000, ...
    'Scenario_Name','Scenario_C_Battery_Degradation_Isolated', ...
    'Asset_State','Battery_Degradation_Only', 'Sensor_State','Healthy', ...
    'Environment_State','Nominal_G1000_Controlled', 'Twin_State','Reference');
T_C = stage9_run_scenario_v3(cfgC);

writetable(T_B, 'Stage9_ScenarioB_PVDegradation.csv');
writetable(T_C, 'Stage9_ScenarioC_BatteryDegradation.csv');

%% ---- Sanity checks: did freezing actually freeze the right thing? ----
fprintf('=== Scenario B (PV ages, Battery frozen) ===\n');
fprintf('Rs_aged   : starts %.6f, ends %.6f (should RISE)\n', T_B.Rs_aged(1), T_B.Rs_aged(end));
fprintf('R0_aged   : starts %.6f, ends %.6f (should stay CONSTANT)\n', T_B.R0_aged(1), T_B.R0_aged(end));
R0_B_range = max(T_B.R0_aged) - min(T_B.R0_aged);
fprintf('R0_aged range over the run: %.8f (expect ~0)\n\n', R0_B_range);

fprintf('=== Scenario C (Battery ages, PV frozen) ===\n');
fprintf('R0_aged   : starts %.6f, ends %.6f (should RISE)\n', T_C.R0_aged(1), T_C.R0_aged(end));
fprintf('Rs_aged   : starts %.6f, ends %.6f (should stay CONSTANT)\n', T_C.Rs_aged(1), T_C.Rs_aged(end));
Rs_C_range = max(T_C.Rs_aged) - min(T_C.Rs_aged);
fprintf('Rs_aged range over the run: %.8f (expect ~0)\n\n', Rs_C_range);

%% ---- The actual question: does the residual follow the aging domain ----
% Correlate |PV residual| and |Battery residual| against time (a crude
% but honest proxy for "is this residual moving with degradation or not"
% -- the same Spearman-vs-ground-truth logic already used in
% stage9_feature_analysis.m, applied per-domain here).
rho_B_PV   = corr(T_B.t_grid, T_B.PV_AbsResidual_Current, 'type','Spearman');
rho_B_Batt = corr(T_B.t_grid, T_B.Battery_AbsResidual_Voltage, 'type','Spearman');
rho_C_PV   = corr(T_C.t_grid, T_C.PV_AbsResidual_Current, 'type','Spearman');
rho_C_Batt = corr(T_C.t_grid, T_C.Battery_AbsResidual_Voltage, 'type','Spearman');

fprintf('--- Isolation check (Spearman rho of |residual| vs time) ---\n');
fprintf('Scenario B: PV |residual| vs time       rho = %+.3f  (expect clearly positive -- PV is aging)\n', rho_B_PV);
fprintf('Scenario B: Battery |residual| vs time  rho = %+.3f  (expect near zero -- Battery is frozen)\n', rho_B_Batt);
fprintf('Scenario C: Battery |residual| vs time  rho = %+.3f  (expect clearly positive -- Battery is aging)\n', rho_C_Batt);
fprintf('Scenario C: PV |residual| vs time       rho = %+.3f  (expect near zero -- PV is frozen)\n\n', rho_C_PV);

if isfile('Stage9_FeatureDataset.mat')
    S = load('Stage9_FeatureDataset.mat');
    healthy = S.FullDataset(strcmp(S.FullDataset.Scenario_Name,'Healthy_Baseline'),:);
    rho_H_PV   = corr(healthy.t_grid, healthy.PV_AbsResidual_Current, 'type','Spearman');
    rho_H_Batt = corr(healthy.t_grid, healthy.Battery_AbsResidual_Voltage, 'type','Spearman');
    fprintf('--- For comparison, Healthy_Baseline (both domains aging together) ---\n');
    fprintf('Healthy_Baseline: PV |residual| vs time       rho = %+.3f\n', rho_H_PV);
    fprintf('Healthy_Baseline: Battery |residual| vs time  rho = %+.3f\n\n', rho_H_Batt);
else
    fprintf('(Stage9_FeatureDataset.mat not found in this folder -- skipping Healthy_Baseline comparison.\n');
    fprintf(' Run stage9_build_dataset_v3() first if you want that comparison printed too.)\n\n');
end

fprintf('Saved Stage9_ScenarioB_PVDegradation.csv (%d rows) and Stage9_ScenarioC_BatteryDegradation.csv (%d rows).\n', ...
    height(T_B), height(T_C));

end