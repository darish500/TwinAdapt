function Stage11_build_features(tag)
M = readtable('Stage10_DatasetA_Manifest.csv');
folder = ['Stage11_' tag '_runs'];
pvS = {'PV_Irradiance_Final','PV_Temperature_Final','PV_Voltage_Final','PV_Current_Final'};
pvT = {'PV_Twin_Current','PV_Twin_Power','PV_Residual_Current','PV_Residual_Power', ...
       'PV_Residual_Current_Mean','PV_Residual_Current_Std','PV_Residual_Current_MaxAbs','PV_Residual_Current_Trend', ...
       'PV_Residual_Power_Mean','PV_Residual_Power_Std','PV_Residual_Power_MaxAbs','PV_Residual_Power_Trend'};
bS  = {'Battery_Voltage_Final','Battery_Current_Final','Battery_Temperature_Final'};
bT  = {'Battery_Twin_Voltage','Battery_Residual_Voltage', ...
       'Battery_Residual_Voltage_Mean','Battery_Residual_Voltage_Std','Battery_Residual_Voltage_MaxAbs','Battery_Residual_Voltage_Trend'};
P = cell(height(M),1);  B = P;
for i = 1:height(M)
    R = readtable(fullfile(folder, sprintf('run_%03d.csv', M.run(i))));
    mp = struct('run',M.run(i),'level',M.pvL(i),'profile',M.pvProf(i),'splitA',string(M.pvA(i)),'splitB',string(M.pvB(i)));
    mb = struct('run',M.run(i),'level',M.bL(i),'profile',M.bProf(i),'splitA',string(M.bA(i)),'splitB',string(M.bB(i)));
    P{i} = run_features(R, mp, 'D_index', pvS, pvT);
    B{i} = run_features(R, mb, 'D_batt',  bS,  bT);
end
writetable(vertcat(P{:}), ['Stage11_Features_' tag '_PV.csv']);
writetable(vertcat(B{:}), ['Stage11_Features_' tag '_Battery.csv']);
fprintf('%s features written (%d runs)\n', tag, height(M));
end

function F = run_features(R, meta, dcol, sensorCols, twinCols)
X = table();
for c = sensorCols
    x = R.(c{1});
    X.(['S_' c{1}])            = x;
    X.(['S_' c{1} '_mean20'])  = movmean(x, [199 0]);
    X.(['S_' c{1} '_std20'])   = movstd(x,  [199 0]);
    X.(['S_' c{1} '_slope60']) = slope(x, 600, 0.1);
end
for c = twinCols
    X.(['T_' c{1}]) = R.(c{1});
end
keep = R.t >= 60 - 1e-9 & mod(round(R.t*10), 10) == 0;
nk = nnz(keep);
M = table(repmat(meta.run,nk,1), R.t(keep), repmat(meta.level,nk,1), repmat(meta.profile,nk,1), ...
          repmat(meta.splitA,nk,1), repmat(meta.splitB,nk,1), R.(dcol)(keep), ...
          'VariableNames', {'run','t','level','profile','splitA','splitB','D'});
F = [M X(keep,:)];
end

function s = slope(x, W, dt)
k   = (0:numel(x)-1)' * dt;
mk  = movmean(k,   [W-1 0]);   mx  = movmean(x,     [W-1 0]);
mkx = movmean(k.*x,[W-1 0]);   mkk = movmean(k.^2,  [W-1 0]);
s = (mkx - mk.*mx) ./ (mkk - mk.^2 + eps);
end