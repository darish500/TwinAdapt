function Stage10_build_features()
PV = readtable('Stage10_PV_Controlled.csv');
BT = readtable('Stage10_Battery_Controlled.csv');

% ---- causality check: a feature at sample 800 must not change if the future is removed ----
x = PV.PV_Current_Final(PV.run == 1);
a = movmean(x, [199 0]);                     % full run
b = movmean(x(1:800), [199 0]);              % run cut off at sample 800
fprintf('causal check (20 s mean at sample 800, full vs truncated): %s\n', ...
        ternary(abs(a(800)-b(800)) < 1e-12));

% ---- PV ----
pvSensor = {'PV_Irradiance_Final','PV_Temperature_Final','PV_Voltage_Final','PV_Current_Final'};
pvTwin   = {'PV_Twin_Current','PV_Twin_Power','PV_Residual_Current','PV_Residual_Power', ...
            'PV_Residual_Current_Mean','PV_Residual_Current_Std','PV_Residual_Current_MaxAbs','PV_Residual_Current_Trend', ...
            'PV_Residual_Power_Mean','PV_Residual_Power_Std','PV_Residual_Power_MaxAbs','PV_Residual_Power_Trend'};
FP = make_features(PV, 'D_index', pvSensor, pvTwin, {'PV_Feature_Window_Valid','PV_Trend_Window_Valid'});
writetable(FP, 'Stage10_Features_PV.csv');

% ---- Battery ----
bSensor = {'Battery_Voltage_Final','Battery_Current_Final','Battery_Temperature_Final'};
bTwin   = {'Battery_Twin_Voltage','Battery_Residual_Voltage', ...
           'Battery_Residual_Voltage_Mean','Battery_Residual_Voltage_Std','Battery_Residual_Voltage_MaxAbs','Battery_Residual_Voltage_Trend'};
FB = make_features(BT, 'D_batt', bSensor, bTwin, {'Battery_Feature_Window_Valid','Battery_Trend_Window_Valid'});
writetable(FB, 'Stage10_Features_Battery.csv');

for nm = ["PV","Battery"]
    if nm == "PV", F = FP; else, F = FB; end
    fprintf('%-8s rows %d | runs %d | sensor features %d | twin features %d\n', nm, height(F), numel(unique(F.run)), ...
        sum(startsWith(F.Properties.VariableNames,'S_')), sum(startsWith(F.Properties.VariableNames,'T_')));
end
end

function F = make_features(A, dcol, sensorCols, twinCols, flagCols)
runs = unique(A.run);
parts = cell(numel(runs),1);  allValid = true;
for i = 1:numel(runs)
    R = A(A.run == runs(i), :);
    X = table();
    for c = sensorCols
        x = R.(c{1});
        X.(['S_' c{1}])            = x;                           % current value
        X.(['S_' c{1} '_mean20'])  = movmean(x, [199 0]);         % 20 s causal mean
        X.(['S_' c{1} '_std20'])   = movstd(x,  [199 0]);         % 20 s causal std
        X.(['S_' c{1} '_slope60']) = slope(x, 600, 0.1);          % 60 s causal trend
    end
    for c = twinCols
        X.(['T_' c{1}]) = R.(c{1});
    end
    keep = R.t >= 60 - 1e-9 & mod(round(R.t*10), 10) == 0;        % one row per second, full windows only
    for f = flagCols, allValid = allValid && all(R.(f{1})(keep) == 1); end
    M = R(keep, {'run','t','level','profile','splitA','splitB',dcol});
    M.Properties.VariableNames{end} = 'D';
    parts{i} = [M X(keep,:)];
end
F = vertcat(parts{:});
fprintf('  Stage 9 window-valid flags all 1 in kept rows: %s\n', ternary(allValid));
end

function s = slope(x, W, dt)                                     % least-squares slope over the last W samples
k   = (0:numel(x)-1)' * dt;
mk  = movmean(k,   [W-1 0]);   mx  = movmean(x,     [W-1 0]);
mkx = movmean(k.*x,[W-1 0]);   mkk = movmean(k.^2,  [W-1 0]);
s = (mkx - mk.*mx) ./ (mkk - mk.^2 + eps);
end

function s = ternary(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end