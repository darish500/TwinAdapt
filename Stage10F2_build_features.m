function Stage10F2_build_features()
% Features for Dataset F2 (the untouched final test). Reads Stage10F2_Manifest.csv and Stage10F2_runs/run_###.csv and writes
%   Stage10F2_Features_PV.csv  and  Stage10F2_Features_Battery.csv
% The feature definitions are copied unchanged from Stage11_build_features / Stage10_build_features:
%   current value, 20 s causal mean, 20 s causal std, 60 s causal least-squares slope of each measured sensor channel,
%   plus the Twin outputs, residuals and the Stage 9 residual-window summaries; one row per second from t >= 60 s.
% Columns: run, t, levelD (true health, 0..1), profile, regime ('A' = unseen health levels, 'B' = unseen profile family), D, S_*, T_*.
% It does NOT train or evaluate anything. Before writing, it runs a self-test: the same feature code applied to three Dataset A
% runs must reproduce the rows that Stage10_Features_PV/Battery.csv holds for those runs.
M = readtable('Stage10F2_Manifest.csv');
pvS = {'PV_Irradiance_Final','PV_Temperature_Final','PV_Voltage_Final','PV_Current_Final'};
pvT = {'PV_Twin_Current','PV_Twin_Power','PV_Residual_Current','PV_Residual_Power', ...
       'PV_Residual_Current_Mean','PV_Residual_Current_Std','PV_Residual_Current_MaxAbs','PV_Residual_Current_Trend', ...
       'PV_Residual_Power_Mean','PV_Residual_Power_Std','PV_Residual_Power_MaxAbs','PV_Residual_Power_Trend'};
bS  = {'Battery_Voltage_Final','Battery_Current_Final','Battery_Temperature_Final'};
bT  = {'Battery_Twin_Voltage','Battery_Residual_Voltage', ...
       'Battery_Residual_Voltage_Mean','Battery_Residual_Voltage_Std','Battery_Residual_Voltage_MaxAbs','Battery_Residual_Voltage_Trend'};
pvFlags = {'PV_Feature_Window_Valid','PV_Trend_Window_Valid'};
bFlags  = {'Battery_Feature_Window_Valid','Battery_Trend_Window_Valid'};

% ---------------- self-test on Dataset A (proves the new path = the original path) ----------------
if isfile('Stage10_Features_PV.csv') && isfile('Stage10_Features_Battery.csv') && isfile(fullfile('Stage10_runs','run_001.csv'))
    refP = readtable('Stage10_Features_PV.csv');  refB = readtable('Stage10_Features_Battery.csv');
    worst = 0;
    for r = [1 50 100]
        R  = readtable(fullfile('Stage10_runs', sprintf('run_%03d.csv', r)));
        Fp = run_features(R, struct('run',r,'levelD',0,'profile',0,'regime',"A"), 'D_index', pvS, pvT, pvFlags);
        Fb = run_features(R, struct('run',r,'levelD',0,'profile',0,'regime',"A"), 'D_batt',  bS,  bT,  bFlags);
        worst = max([worst, maxdiff(Fp, refP(refP.run == r,:)), maxdiff(Fb, refB(refB.run == r,:))]);
    end
    fprintf('self-test on Dataset A runs 1, 50, 100: largest absolute difference vs the saved A feature files = %.3g  (%s)\n', ...
        worst, ternary(worst < 1e-9));
    if worst >= 1e-9, error('Self-test failed: the F feature path does not reproduce the Dataset A features. Nothing was written.'); end
else
    warning('Dataset A feature files or runs not found: self-test skipped. Do not trust the F features until it has been run.');
end

% ---------------- Dataset F2 ----------------
P = cell(height(M),1);  B = P;
for i = 1:height(M)
    R = readtable(fullfile('Stage10F2_runs', sprintf('run_%03d.csv', M.run(i))));
    assert(height(R) == 1501, 'run %d has %d rows (expected 1501)', M.run(i), height(R));
    P{i} = run_features(R, struct('run',M.run(i),'levelD',M.pvD(i),'profile',M.pvProf(i),'regime',string(M.regime(i))), 'D_index', pvS, pvT, pvFlags);
    B{i} = run_features(R, struct('run',M.run(i),'levelD',M.bD(i), 'profile',M.bProf(i),'regime',string(M.regime(i))), 'D_batt',  bS,  bT,  bFlags);
end
FP = vertcat(P{:});  FB = vertcat(B{:});
assert(~any(any(ismissing(FP))) && ~any(any(ismissing(FB))), 'NaN or missing values in the F features');
writetable(FP, 'Stage10F2_Features_PV.csv');
writetable(FB, 'Stage10F2_Features_Battery.csv');
for nm = ["PV","Battery"]
    if nm == "PV", F = FP; else, F = FB; end
    vn = F.Properties.VariableNames;
    fprintf('%-8s rows %d | runs %d (A %d, B %d) | sensor features %d | twin features %d\n', nm, height(F), numel(unique(F.run)), ...
        numel(unique(F.run(F.regime == "A"))), numel(unique(F.run(F.regime == "B"))), sum(startsWith(vn,'S_')), sum(startsWith(vn,'T_')));
end
fprintf('Done. Nothing has been trained or evaluated on Dataset F2.\n');
end

function F = run_features(R, meta, dcol, sensorCols, twinCols, flagCols)
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
for f = flagCols
    assert(all(R.(f{1})(keep) == 1), 'window-valid flag %s is not 1 in kept rows of run %d', f{1}, meta.run);
end
nk = nnz(keep);
M = table(repmat(meta.run,nk,1), R.t(keep), repmat(meta.levelD,nk,1), repmat(meta.profile,nk,1), ...
          repmat(string(meta.regime),nk,1), R.(dcol)(keep), ...
          'VariableNames', {'run','t','levelD','profile','regime','D'});
F = [M X(keep,:)];
end

function d = maxdiff(Fnew, Fold)
% largest absolute difference over t, D and every S_/T_ column; sizes must agree
assert(height(Fnew) == height(Fold), 'row count differs in self-test (%d vs %d)', height(Fnew), height(Fold));
cols = [{'t','D'}, Fold.Properties.VariableNames(startsWith(Fold.Properties.VariableNames,'S_') | startsWith(Fold.Properties.VariableNames,'T_'))];
d = 0;
for c = cols
    assert(ismember(c{1}, Fnew.Properties.VariableNames), 'column %s missing in the new features', c{1});
    d = max(d, max(abs(Fnew.(c{1}) - Fold.(c{1}))));
end
end

function s = slope(x, W, dt)
k   = (0:numel(x)-1)' * dt;
mk  = movmean(k,   [W-1 0]);   mx  = movmean(x,     [W-1 0]);
mkx = movmean(k.*x,[W-1 0]);   mkk = movmean(k.^2,  [W-1 0]);
s = (mkx - mk.*mx) ./ (mkk - mk.^2 + eps);
end

function s = ternary(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end