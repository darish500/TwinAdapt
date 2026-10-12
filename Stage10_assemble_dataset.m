function Stage10_assemble_dataset()
M = readtable('Stage10_DatasetA_Manifest.csv');
pvCols = {'PV_Irradiance_Final','PV_Temperature_Final','PV_Voltage_Final','PV_Current_Final', ...
    'PV_Twin_Current','PV_Twin_Power','PV_Residual_Current','PV_Residual_Power', ...
    'PV_Residual_Current_Mean','PV_Residual_Current_Std','PV_Residual_Current_MaxAbs','PV_Residual_Current_Trend', ...
    'PV_Residual_Power_Mean','PV_Residual_Power_Std','PV_Residual_Power_MaxAbs','PV_Residual_Power_Trend', ...
    'PV_Feature_Window_Valid','PV_Trend_Window_Valid', ...
    'D_index','Rs_aged','Rsh_aged','Iph_ref_aged','True_PV_Current'};
bCols = {'Battery_Voltage_Final','Battery_Current_Final','Battery_Temperature_Final', ...
    'Battery_Twin_Voltage','Battery_Residual_Voltage', ...
    'Battery_Residual_Voltage_Mean','Battery_Residual_Voltage_Std','Battery_Residual_Voltage_MaxAbs','Battery_Residual_Voltage_Trend', ...
    'Battery_Feature_Window_Valid','Battery_Trend_Window_Valid','Battery_Twin_SOC_Estimate', ...
    'D_batt','R0_aged','R1_aged','Capacity_aged','OCV_deltaV','True_Battery_Voltage'};
PV = cell(height(M),1); BT = cell(height(M),1);
for i = 1:height(M)
    r = M.run(i);
    T = readtable(fullfile('Stage10_runs', sprintf('run_%03d.csv', r)));
    n = height(T);
    P = T(:, [{'t'} pvCols]);
    P.run = repmat(r, n, 1);  P.level = repmat(M.pvL(i), n, 1);  P.profile = repmat(M.pvProf(i), n, 1);
    P.splitA = repmat(string(M.pvA(i)), n, 1);  P.splitB = repmat(string(M.pvB(i)), n, 1);
    P.noiseSeed = repmat(M.noiseSeed(i), n, 1);
    B = T(:, [{'t'} bCols]);
    B.run = repmat(r, n, 1);  B.level = repmat(M.bL(i), n, 1);  B.profile = repmat(M.bProf(i), n, 1);
    B.splitA = repmat(string(M.bA(i)), n, 1);  B.splitB = repmat(string(M.bB(i)), n, 1);
    B.noiseSeed = repmat(M.noiseSeed(i), n, 1);
    PV{i} = P;  BT{i} = B;
end
PV = vertcat(PV{:});  BT = vertcat(BT{:});
writetable(PV, 'Stage10_PV_Controlled.csv');
writetable(BT, 'Stage10_Battery_Controlled.csv');
fprintf('PV rows: %d   Battery rows: %d   runs: %d\n', height(PV), height(BT), numel(unique(PV.run)));
end