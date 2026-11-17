function Stage14_build_features(tag)
% Features for a stress-test dataset (tag = 'E1a','E1b','E1','E2','E3' or 'D'): reads Stage10F_Manifest.csv and Stage14_<tag>_runs/run_###.csv and
% writes Stage14_Features_<tag>_PV.csv and Stage14_Features_<tag>_Battery.csv. The feature code is the same as Stage10F_build_features
% (copied unchanged), which was self-tested against the Dataset A features. Checks before it finishes:
%   * for the mismatch tags the sensor columns (S_*) must equal those of the clean Dataset F features exactly (only the Twin changes);
%   * the health labels must equal those of the clean Dataset F features.
% It does NOT train or evaluate anything.
M = readtable('Stage10F_Manifest.csv');
pvS = {'PV_Irradiance_Final','PV_Temperature_Final','PV_Voltage_Final','PV_Current_Final'};
pvT = {'PV_Twin_Current','PV_Twin_Power','PV_Residual_Current','PV_Residual_Power', ...
       'PV_Residual_Current_Mean','PV_Residual_Current_Std','PV_Residual_Current_MaxAbs','PV_Residual_Current_Trend', ...
       'PV_Residual_Power_Mean','PV_Residual_Power_Std','PV_Residual_Power_MaxAbs','PV_Residual_Power_Trend'};
bS  = {'Battery_Voltage_Final','Battery_Current_Final','Battery_Temperature_Final'};
bT  = {'Battery_Twin_Voltage','Battery_Residual_Voltage', ...
       'Battery_Residual_Voltage_Mean','Battery_Residual_Voltage_Std','Battery_Residual_Voltage_MaxAbs','Battery_Residual_Voltage_Trend'};
pvFlags = {'PV_Feature_Window_Valid','PV_Trend_Window_Valid'};
bFlags  = {'Battery_Feature_Window_Valid','Battery_Trend_Window_Valid'};
folder = ['Stage14_' tag '_runs'];
P = cell(height(M),1);  B = P;
for i = 1:height(M)
    R = readtable(fullfile(folder, sprintf('run_%03d.csv', M.run(i))));
    assert(height(R) == 1501, 'run %d has %d rows (expected 1501)', M.run(i), height(R));
    P{i} = run_features(R, struct('run',M.run(i),'levelD',M.pvD(i),'profile',M.pvProf(i),'regime',string(M.regime(i))), 'D_index', pvS, pvT, pvFlags);
    B{i} = run_features(R, struct('run',M.run(i),'levelD',M.bD(i), 'profile',M.bProf(i),'regime',string(M.regime(i))), 'D_batt',  bS,  bT,  bFlags);
end
FP = vertcat(P{:});  FB = vertcat(B{:});
assert(~any(any(ismissing(FP))) && ~any(any(ismissing(FB))), 'NaN or missing values in the features');
% ---- consistency with the clean Dataset F features ----
nmz = {'PV','Battery'};
cl = {readtable('Stage10F_Features_PV.csv'), readtable('Stage10F_Features_Battery.csv')};
nw = {FP, FB};
for k = 1:2
    assert(isequal(cl{k}.run, nw{k}.run) && max(abs(cl{k}.t - nw{k}.t)) < 1e-9, 'rows do not line up with clean Dataset F');
    assert(max(abs(cl{k}.D - nw{k}.D)) < 1e-9, 'health labels differ from clean Dataset F');
    sc = cl{k}.Properties.VariableNames(startsWith(cl{k}.Properties.VariableNames,'S_'));
    dS = 0;  for c = sc, dS = max(dS, max(abs(cl{k}.(c{1}) - nw{k}.(c{1})))); end
    if strcmp(tag,'D')
        fprintf('%-8s sensor columns differ from clean F by up to %.4g (expected > 0: sensors are faulted)\n', nmz{k}, dS);
    else
        fprintf('%-8s sensor columns differ from clean F by up to %.3g (must be 0: only the Twin changes)\n', nmz{k}, dS);
        assert(dS < 1e-9, 'sensor columns changed although only the Twin was perturbed');
    end
end
writetable(FP, ['Stage14_Features_' tag '_PV.csv']);
writetable(FB, ['Stage14_Features_' tag '_Battery.csv']);
fprintf('Stage14_Features_%s_PV.csv / _Battery.csv written (%d rows each). Nothing was trained or evaluated.\n', tag, height(FP));
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