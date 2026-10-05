%% stage9_feature_analysis.m
% Offline analysis of the Stage 9 feature dataset. Loads the exported
% CSVs (deployment features + evaluation metadata, already kept as
% separate column blocks by stage9_build_dataset). Ground truth is used
% HERE, for evaluation only -- never fed back into any feature. No ML,
% no thresholds invented for classification -- purely descriptive/
% correlational, per Stage 9's own scope boundary.

close all;
plotsDir = 'Stage9_Plots';
if ~exist(plotsDir,'dir'), mkdir(plotsDir); end

P = readtable('Stage9_PV_Features.csv');
B = readtable('Stage9_Battery_Features.csv');

scenarios = unique(P.Scenario_Name, 'stable');
healthyMask   = strcmp(P.Scenario_Name, 'Healthy_Baseline');
healthyMaskB  = strcmp(B.Scenario_Name, 'Healthy_Baseline');

% Derived RMS (exact identity, not logged separately -- see note in chat)
P.PV_Residual_Current_RMS = sqrt(P.PV_Residual_Current_Mean.^2 + P.PV_Residual_Current_Std.^2);
P.PV_Residual_Power_RMS   = sqrt(P.PV_Residual_Power_Mean.^2   + P.PV_Residual_Power_Std.^2);
B.Battery_Residual_Voltage_RMS = sqrt(B.Battery_Residual_Voltage_Mean.^2 + B.Battery_Residual_Voltage_Std.^2);

fprintf('=========================================================\n');
fprintf('STAGE 9 FEATURE ANALYSIS\n');
fprintf('=========================================================\n');
fprintf('%d PV rows, %d Battery rows, %d scenarios\n\n', height(P), height(B), numel(scenarios));

%% ============ Section 1: Descriptive statistics per scenario ============
fprintf('--- Descriptive statistics: PV_AbsResidual_Current by scenario ---\n');
for k = 1:numel(scenarios)
    m = strcmp(P.Scenario_Name, scenarios{k});
    x = P.PV_AbsResidual_Current(m);
    fprintf('%-36s mean=%8.4f std=%8.4f min=%8.4f max=%8.4f\n', ...
        scenarios{k}, mean(x), std(x), min(x), max(x));
end

fprintf('\n--- Descriptive statistics: Battery_AbsResidual_Voltage by scenario ---\n');
for k = 1:numel(scenarios)
    m = strcmp(B.Scenario_Name, scenarios{k});
    x = B.Battery_AbsResidual_Voltage(m);
    fprintf('%-36s mean=%8.4f std=%8.4f min=%8.4f max=%8.4f\n', ...
        scenarios{k}, mean(x), std(x), min(x), max(x));
end

%% ============ Section 2: Plots 1-4 (PV), using Healthy_Baseline ============
tP = P.t_grid(healthyMask);

figure('Name','Plot 1: PV Measured vs Twin Current');
subplot(2,1,1);
plot(tP, P.PV_Current_Final(healthyMask), tP, P.PV_Twin_Current(healthyMask));
legend('Measured','Twin'); xlabel('Time (s)'); ylabel('Current (A)');
title('Plot 1a: PV Measured vs Twin Current (Healthy Baseline)');
subplot(2,1,2);
plot(tP, P.PV_Residual_Current(healthyMask));
xlabel('Time (s)'); ylabel('Residual (A)'); title('Plot 1b: PV Current Residual');
exportgraphics(gcf, fullfile(plotsDir,'Plot01_PV_Measured_vs_Twin_Current.png'), 'Resolution',150);

figure('Name','Plot 2: PV Residual Magnitude vs Time');
plot(tP, P.PV_AbsResidual_Current(healthyMask));
xlabel('Time (s)'); ylabel('|Residual| (A)'); title('Plot 2: PV Residual Magnitude vs Time');
exportgraphics(gcf, fullfile(plotsDir,'Plot02_PV_Residual_Magnitude.png'), 'Resolution',150);

figure('Name','Plot 3: PV Rolling RMS vs Time');
plot(tP, P.PV_Residual_Current_RMS(healthyMask));
xlabel('Time (s)'); ylabel('RMS (A)');
title('Plot 3: PV Rolling RMS Residual vs Time (derived: sqrt(Mean^2+Std^2))');
exportgraphics(gcf, fullfile(plotsDir,'Plot03_PV_Rolling_RMS.png'), 'Resolution',150);

figure('Name','Plot 4: PV Residual Trend vs Time');
plot(tP, P.PV_Residual_Current_Trend(healthyMask));
xlabel('Time (s)'); ylabel('Trend (A/s)'); title('Plot 4: PV Residual Trend vs Time');
exportgraphics(gcf, fullfile(plotsDir,'Plot04_PV_Residual_Trend.png'), 'Resolution',150);

%% ============ Section 3: Plots 5-7 (Battery), using Healthy_Baseline ============
tB = B.t_grid(healthyMaskB);

figure('Name','Plot 5: Battery Measured vs Twin Voltage');
subplot(2,1,1);
plot(tB, B.Battery_Voltage_Final(healthyMaskB), tB, B.Battery_Twin_Voltage(healthyMaskB));
legend('Measured','Twin'); xlabel('Time (s)'); ylabel('Voltage (V)');
title('Plot 5a: Battery Measured vs Twin Voltage (Healthy Baseline)');
subplot(2,1,2);
plot(tB, B.Battery_Residual_Voltage(healthyMaskB));
xlabel('Time (s)'); ylabel('Residual (V)'); title('Plot 5b: Battery Voltage Residual');
exportgraphics(gcf, fullfile(plotsDir,'Plot05_Battery_Measured_vs_Twin_Voltage.png'), 'Resolution',150);

figure('Name','Plot 6: Battery Rolling RMS vs Time');
plot(tB, B.Battery_Residual_Voltage_RMS(healthyMaskB));
xlabel('Time (s)'); ylabel('RMS (V)');
title('Plot 6: Battery Rolling RMS Residual vs Time (derived: sqrt(Mean^2+Std^2))');
exportgraphics(gcf, fullfile(plotsDir,'Plot06_Battery_Rolling_RMS.png'), 'Resolution',150);

figure('Name','Plot 7: Battery Residual Trend vs Time');
plot(tB, B.Battery_Residual_Voltage_Trend(healthyMaskB));
xlabel('Time (s)'); ylabel('Trend (V/s)'); title('Plot 7: Battery Residual Trend vs Time');
exportgraphics(gcf, fullfile(plotsDir,'Plot07_Battery_Residual_Trend.png'), 'Resolution',150);

%% ============ Section 4: Plot 8, correlation matrix ============
pvFeatureCols = {'PV_AbsResidual_Current','PV_AbsResidual_Power', ...
    'PV_Normalized_Current_Residual','PV_Normalized_Power_Residual', ...
    'PV_Residual_Current_Mean','PV_Residual_Current_Std','PV_Residual_Current_MaxAbs', ...
    'PV_Residual_Current_Trend','PV_Residual_Current_RMS'};
Cpv = corr(P{:, pvFeatureCols}, 'Rows','complete');

figure('Name','Plot 8: PV Feature Correlation Matrix');
imagesc(Cpv); colorbar; caxis([-1 1]); colormap(jet);
set(gca,'XTick',1:numel(pvFeatureCols),'XTickLabel',pvFeatureCols,'XTickLabelRotation',45, ...
        'YTick',1:numel(pvFeatureCols),'YTickLabel',pvFeatureCols,'FontSize',7);
title('Plot 8: PV Feature Correlation Matrix (Pearson)');
exportgraphics(gcf, fullfile(plotsDir,'Plot08_Feature_Correlation_Matrix.png'), 'Resolution',150);

fprintf('\n--- Highly correlated PV feature pairs (|r|>0.9, redundancy candidates) ---\n');
for i = 1:numel(pvFeatureCols)
    for j = i+1:numel(pvFeatureCols)
        if abs(Cpv(i,j)) > 0.9
            fprintf('%s  <->  %s : r=%.3f\n', pvFeatureCols{i}, pvFeatureCols{j}, Cpv(i,j));
        end
    end
end

%% ============ Section 5: Plot 9, feature distributions across scenarios ============
% The sensor-fault-breakdown scenario (~76A, see earlier finding) is two
% orders of magnitude larger than every other scenario -- plotted
% together it swamps the y-axis and makes all 14 other scenarios look
% like flat zero. Split into a main panel (everything else, readable
% scale) and the outlier shown separately, rather than one unreadable
% combined plot.
outlierScenario = 'PV_SensorFault_VoltageBias';
normalMask = ~strcmp(P.Scenario_Name, outlierScenario);

figure('Name','Plot 9: Feature Distributions Across Scenarios');
subplot(2,1,1);
boxplot(P.PV_AbsResidual_Current(normalMask), P.Scenario_Name(normalMask));
xtickangle(45); ylabel('|PV Residual Current| (A)');
title('Plot 9a: PV Residual Magnitude by Scenario (14 scenarios, readable scale)');

subplot(2,1,2);
boxplot(P.PV_AbsResidual_Current(~normalMask), P.Scenario_Name(~normalMask));
ylabel('|PV Residual Current| (A)');
title('Plot 9b: PV\_SensorFault\_VoltageBias shown separately (~76A, two orders of magnitude larger)');
exportgraphics(gcf, fullfile(plotsDir,'Plot09_Feature_Distributions_By_Scenario.png'), 'Resolution',150);

%% ============ Section 6: Plot 10, degradation ground truth vs residual ============
figure('Name','Plot 10: Degradation Ground Truth vs Residual Trajectory');
yyaxis left; plot(tP, P.Rs_aged(healthyMask)); ylabel('Rs\_aged (Ohm)');
yyaxis right; plot(tP, P.PV_AbsResidual_Current(healthyMask));
ylabel('|PV Residual Current| (A)'); xlabel('Time (s)');
title('Plot 10: PV Degradation Ground Truth vs Residual Trajectory (Healthy Baseline)');
exportgraphics(gcf, fullfile(plotsDir,'Plot10_Degradation_vs_Residual.png'), 'Resolution',150);

%% ============ Section 7: Feature quality metrics (Section 30) ============
fprintf('\n--- Feature quality metrics ---\n');
qualityFeatures = {'PV_AbsResidual_Current','PV_Residual_Current_Std','PV_Residual_Current_RMS'};
for i = 1:numel(qualityFeatures)
    f = qualityFeatures{i};
    healthyVals = P.(f)(healthyMask);
    stability_mean = mean(healthyVals); stability_std = std(healthyVals);

    faultMask = strcmp(P.Scenario_Name,'PV_Fault_OpenCircuit');
    faultVals = P.(f)(faultMask);
    sensitivity = mean(faultVals) - mean(healthyVals);
    separation = (mean(faultVals)-mean(healthyVals)) / sqrt((std(faultVals)^2+std(healthyVals)^2)/2); % Cohen's d

    fprintf('%-30s Stability(mean/std)=%.4f/%.4f  Sensitivity(OpenCircuit-Healthy)=%.4f  Separation(Cohens d)=%.2f\n', ...
        f, stability_mean, stability_std, sensitivity, separation);
end

% Monotonicity check across the Healthy_Baseline aging trajectory (not assumed, tested)
d = diff(P.PV_AbsResidual_Current(healthyMask));
fracIncreasing = mean(d > 0);
fprintf('Monotonicity check (PV_AbsResidual_Current over aging trajectory): %.1f%% of steps increasing (100%% = perfectly monotonic)\n', 100*fracIncreasing);

%% ============ Section 8: Degradation relationship (Section 31, Spearman) ============
fprintf('\n--- Spearman correlation: feature vs ground-truth degradation (Healthy Baseline only) ---\n');
degradFeatures = {'PV_AbsResidual_Current','PV_Residual_Current_Std','PV_Residual_Current_Trend'};
for i = 1:numel(degradFeatures)
    rho = corr(P.Rs_aged(healthyMask), P.(degradFeatures{i})(healthyMask), 'Type','Spearman');
    fprintf('%-30s vs Rs_aged: Spearman rho = %.3f  (correlation, not causation)\n', degradFeatures{i}, rho);
end

%% ============ Section 9: Named comparison -- asset vs sensor vs environment vs Twin mismatch ============
fprintf('\n--- Section 29 comparison: source-of-residual overlap check ---\n');
groups = struct( ...
    'AssetFault',      {{'PV_Fault_Hotspot','PV_Fault_PID','PV_Fault_OpenCircuit','PV_Fault_ShortCircuit'}}, ...
    'SensorFault',     {{'PV_SensorFault_VoltageBias'}}, ...
    'Environmental',   {{'Environmental_G700','Environmental_G1300'}}, ...
    'TwinMismatch',    {{'Twin_Mismatch_PV_Rs_plus5pct'}} );
gNames = fieldnames(groups);
for i = 1:numel(gNames)
    scenList = groups.(gNames{i});
    m = ismember(P.Scenario_Name, scenList);
    fprintf('%-15s |rI| mean=%8.4f  range=[%.4f, %.4f]\n', gNames{i}, ...
        mean(P.PV_AbsResidual_Current(m)), min(P.PV_AbsResidual_Current(m)), max(P.PV_AbsResidual_Current(m)));
end
fprintf(['NOTE: AssetFault''s range is wide (Hotspot sits near Healthy, the other three sit far above it) --\n' ...
         'asset-fault and healthy-aging residual signatures OVERLAP at the low end. This is reported as a\n' ...
         'finding, not resolved or hidden -- per Stage 9 Section 29, overlap is itself evidence, not a failure.\n']);

%% ============ Section 10: Named finding #1 -- Hotspot barely separates from Healthy ============
fprintf('\n--- Named finding: PV_Fault_Hotspot vs Healthy_Baseline ---\n');
mH = strcmp(P.Scenario_Name,'PV_Fault_Hotspot');
fprintf('Healthy |rI| mean=%.4f | Hotspot |rI| mean=%.4f | difference=%.4f (%.1f%% of Healthy''s own mean)\n', ...
    mean(P.PV_AbsResidual_Current(healthyMask)), mean(P.PV_AbsResidual_Current(mH)), ...
    mean(P.PV_AbsResidual_Current(mH))-mean(P.PV_AbsResidual_Current(healthyMask)), ...
    100*(mean(P.PV_AbsResidual_Current(mH))-mean(P.PV_AbsResidual_Current(healthyMask)))/mean(P.PV_AbsResidual_Current(healthyMask)));
fprintf(['INTERPRETATION: Hotspot only inflates Rs, which is small to begin with (~0.013 Ohm); at a fixed\n' ...
         'operating voltage near Vmp, the resulting voltage drop is only tens of mV -- not enough to move\n' ...
         'current meaningfully. This may be a genuine limitation of a fixed-voltage current residual for\n' ...
         'detecting Hotspot specifically, not a bug in the Twin or the fault model.\n']);

%% ============ Section 11: Named finding #2 -- OverDischarge residual LOWER than Healthy ============
fprintf('\n--- Named finding: Battery_Fault_OverDischarge residual below Healthy baseline ---\n');
mOD = strcmp(B.Scenario_Name,'Battery_Fault_OverDischarge');
fprintf('Healthy |rV| mean=%.4f | OverDischarge |rV| mean=%.4f (LOWER, not higher)\n', ...
    mean(B.Battery_AbsResidual_Voltage(healthyMaskB)), mean(B.Battery_AbsResidual_Voltage(mOD)));
fprintf(['UNRESOLVED: this is the only fault in the whole dataset where the residual moves in the\n' ...
         'unexpected direction. Plausible explanation not yet confirmed: Battery_Digital_Twin''s SOC estimate\n' ...
         'is driven purely by measured current (Coulomb counting) and does not know the battery''s TRUE\n' ...
         'capacity has been reduced -- it is possible the Twin''s OCV lookup and the physical model''s OCV\n' ...
         'happen to track each other more closely under this specific fault than under Healthy aging, by\n' ...
         'coincidence of where each trajectory sits on the OCV-SOC curve. Flagged here explicitly rather\n' ...
         'than hidden -- needs further investigation before drawing any conclusion from it.\n']);

fprintf('\n=========================================================\n');
fprintf('Analysis complete. 10 figures generated, no ML/classification performed.\n');
fprintf('=========================================================\n');