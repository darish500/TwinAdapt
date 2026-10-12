function Stage10_ablation()
% Stage 10 ablations on the existing causal feature files (Stage10_Features_PV/Battery.csv).
rng(1);
assets  = {'PV','Battery'};
files   = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
regCol  = {'splitA','splitB'};
regName = {'A: unseen levels','B: unseen profile'};
models  = ["ridge","trees","nn"];
lams    = [0.01 0.1 1 10 100 1000];
R = {};  W = {};  L = {};  Red = {};  Aud = {};

for a = 1:2
    F  = readtable(files{a});  F = [F engineer(F, assets{a})];
    vn = F.Properties.VariableNames;
    S  = vn(startsWith(vn,'S_'));  E = vn(startsWith(vn,'E_'));  T = vn(startsWith(vn,'T_'));
    sT = endsWith(S,'_mean20') | endsWith(S,'_std20') | endsWith(S,'_slope60');   % temporal sensor features
    Si = S(~sT);                                                                   % instantaneous sensor features
    tW = endsWith(T,'_Mean') | endsWith(T,'_Std') | endsWith(T,'_MaxAbs') | endsWith(T,'_Trend');  % Stage 9 window summaries
    Ti = T(~tW);  Tw = T(tW);                                                      % instantaneous Twin / window Twin
    Tr = Ti(contains(Ti,'Residual'));                                              % raw residuals only

    fam = { 'S1 sensor instantaneous',                    Si;
            'S2 sensor + sensor windows',                 S;
            'S3 sensor strong (S + ratios)',              [S E];
            'T1 Twin only: all Twin features',            T;
            'T2 Twin only: raw residuals',                Tr;
            'T3 Twin only: residual windows',             Tw;
            'T4 Twin only: instantaneous',                Ti;
            'C1 strong + raw residuals',                  [S E Tr];
            'C2 strong + residual windows',               [S E Tw];
            'C3 strong + all Twin',                       [S E T];
            'C4 instantaneous sensor + instantaneous Twin', [Si Ti] };

    % ---------- feature audit rows ----------
    for c = [S E T]
        Aud(end+1,:) = {assets{a}, c{1}, group_of(c{1}), 'yes', 'no', 'used'}; %#ok<AGROW>
    end

    % ---------- redundancy: how similar is each Twin feature to a sensor feature? ----------
    Xs = F{:,[S E]};  Xt = F{:,T};
    okS = std(Xs) > 1e-12;  okT = std(Xt) > 1e-12;
    Sn = [S E];  Sn = Sn(okS);  Tn = T(okT);
    Cst = corr(Xt(:,okT), Xs(:,okS));
    [mx, ix] = max(abs(Cst), [], 2);
    for k = 1:numel(Tn)
        Red(end+1,:) = {assets{a}, Tn{k}, round(mx(k),3), Sn{ix(k)}}; %#ok<AGROW>
    end

    for r = 1:2
        sp = string(F.(regCol{r}));  tr = sp == "train";  te = sp == "test";
        % validation: 20% of the TRAINING runs (whole runs) are held back to choose the ridge lambda
        runsTr = unique(F.run(tr));  runsTr = runsTr(randperm(numel(runsTr)));
        nv = max(1, round(0.2*numel(runsTr)));
        inVal = tr & ismember(F.run, runsTr(1:nv));   inFit = tr & ~inVal;
        y = F.D(te);

        for f = 1:size(fam,1)
            cols = fam{f,2};  X = F{:,cols};  nF = numel(cols);
            errs = arrayfun(@(l) mean(abs(apply_ridge(fit_ridge(X(inFit,:),F.D(inFit),l), X(inVal,:)) - F.D(inVal))), lams);
            [~, ib] = min(errs);  lam = lams(ib);
            L(end+1,:) = {assets{a}, regName{r}, fam{f,1}, lam, round(min(errs),4)}; %#ok<AGROW>

            for m = models
                nP = NaN;
                switch m
                    case "ridge"
                        mdl = fit_ridge(X(tr,:), F.D(tr), lam);
                        p = apply_ridge(mdl, X(te,:));   nP = nF + 1;
                    case "trees"
                        mt = fitrensemble(X(tr,:), F.D(tr), 'Method','Bag', 'NumLearningCycles',60, ...
                                          'Learners', templateTree('MinLeafSize',5));
                        p = min(max(predict(mt, X(te,:)), 0), 1);
                        try, nP = sum(cellfun(@(q) q.NumNodes, mt.Trained)); catch, nP = NaN; end
                    case "nn"
                        try
                            mn = fitrnet(X(tr,:), F.D(tr), 'LayerSizes', 8, 'Standardize', true, ...
                                         'Activations','relu', 'IterationLimit', 300, 'Verbose', 0);
                            p = min(max(predict(mn, X(te,:)), 0), 1);   nP = (nF+1)*8 + 9;
                        catch
                            p = nan(size(y));
                        end
                end
                mae = mean(abs(p - y));
                r2  = 1 - sum((y - p).^2) / sum((y - mean(y)).^2);
                R(end+1,:) = {assets{a}, regName{r}, fam{f,1}, char(m), nF, nP, round(mae,4), round(r2,3)}; %#ok<AGROW>
                W(end+1,:) = {assets{a}, regName{r}, fam{f,1}, char(m), ...
                              round(rangeMAE(y,p,-inf,0.4),4), round(rangeMAE(y,p,0.4,0.6001),4), round(rangeMAE(y,p,0.6001,inf),4)}; %#ok<AGROW>
            end
        end
    end
end

% excluded items (audit)
ex = { 'Battery_Twin_SOC_Estimate', 'clock-like: correlation with time -1.000, almost none with health';
       'D_index, D_batt, Rs_aged, Rsh_aged, Iph_ref_aged, R0_aged, R1_aged, Capacity_aged, OCV_deltaV', 'true labels and hidden plant values';
       'True_PV_Current, True_Battery_Voltage', 'noise-free plant truth, not observable';
       'Fault_Active, PV_SensorFault_Active, Battery_SensorFault_Active, Battery_Fault_Active', 'ground-truth fault flags';
       '*_Valid and *_Window_Valid flags', 'validity indicators, not used as inputs';
       't, run, level, profile, split', 'metadata only' };
for k = 1:size(ex,1)
    Aud(end+1,:) = {'both', ex{k,1}, ex{k,2}, 'n/a', 'n/a', 'EXCLUDED'}; %#ok<AGROW>
end

R   = cell2table(R,   'VariableNames', {'Asset','Regime','FeatureSet','Model','nFeatures','nParams','MAE','R2'});
W   = cell2table(W,   'VariableNames', {'Asset','Regime','FeatureSet','Model','MAE_early_D_lt_0p4','MAE_mid_D_0p4_to_0p6','MAE_advanced_D_gt_0p6'});
L   = cell2table(L,   'VariableNames', {'Asset','Regime','FeatureSet','RidgeLambda','ValidationMAE'});
Red = cell2table(Red, 'VariableNames', {'Asset','TwinFeature','MaxAbsCorrWithSensorFeature','MostSimilarSensorFeature'});
Aud = cell2table(Aud, 'VariableNames', {'Asset','Feature','Group','Causal','UsesTrueLabel','Status'});
writetable(R,'Stage10_Ablation_Results.csv');   writetable(W,'Stage10_Ablation_ByWear.csv');
writetable(L,'Stage10_Ablation_Lambdas.csv');   writetable(Red,'Stage10_Redundancy.csv');
writetable(Aud,'Stage10_FeatureAudit.csv');

fprintf('\n=== ABLATION (ridge, test MAE; lower is better) ===\n');
disp(R(R.Model == "ridge", {'Asset','Regime','FeatureSet','nFeatures','MAE','R2'}));
fprintf('\n=== ABLATION (trees) ===\n');
disp(R(R.Model == "trees", {'Asset','Regime','FeatureSet','nFeatures','nParams','MAE','R2'}));
fprintf('\n=== ABLATION (small neural network, 8 hidden units) ===\n');
disp(R(R.Model == "nn", {'Asset','Regime','FeatureSet','nFeatures','nParams','MAE','R2'}));
fprintf('\n=== WEAR RANGE (ridge) ===\n');
disp(W(W.Model == "ridge", {'Asset','Regime','FeatureSet','MAE_early_D_lt_0p4','MAE_mid_D_0p4_to_0p6','MAE_advanced_D_gt_0p6'}));
fprintf('\n=== REDUNDANCY: Twin features that are almost copies of a sensor feature (|r| > 0.95) ===\n');
disp(Red(Red.MaxAbsCorrWithSensorFeature > 0.95, :));
fprintf('Twin features checked: %d, near-duplicates of a sensor feature: %d\n', height(Red), sum(Red.MaxAbsCorrWithSensorFeature > 0.95));
fprintf('\nSaved: Stage10_Ablation_Results/ByWear/Lambdas.csv, Stage10_Redundancy.csv, Stage10_FeatureAudit.csv\n');
end

function m = rangeMAE(y, p, lo, hi)
idx = y >= lo & y < hi;
if any(idx), m = mean(abs(p(idx) - y(idx))); else, m = NaN; end
end

function g = group_of(n)
if startsWith(n,'E_')
    g = 'ratio of measured sensors (causal 20 s means)';
elseif startsWith(n,'S_')
    if endsWith(n,'_mean20') || endsWith(n,'_std20') || endsWith(n,'_slope60')
        g = 'causal window of a measured sensor';
    else
        g = 'instantaneous measured sensor';
    end
else
    if endsWith(n,'_Mean') || endsWith(n,'_Std') || endsWith(n,'_MaxAbs') || endsWith(n,'_Trend')
        g = 'Stage 9 causal window summary of a Twin residual';
    elseif contains(n,'Residual')
        g = 'Twin residual (measured minus Twin)';
    else
        g = 'Twin output computed from measured inputs';
    end
end
end

function E = engineer(F, asset)
E = table();
if strcmp(asset,'PV')
    G = max(F.S_PV_Irradiance_Final_mean20, 1);  I = F.S_PV_Current_Final_mean20;  V = F.S_PV_Voltage_Final_mean20;
    E.E_I_over_G     = I ./ G;
    E.E_P_over_G     = V .* I ./ G;
    E.E_Iinst_over_G = F.S_PV_Current_Final ./ max(F.S_PV_Irradiance_Final, 1);
else
    V = F.S_Battery_Voltage_Final_mean20;  I = max(F.S_Battery_Current_Final_mean20, 0.05);
    E.E_V_over_I       = V ./ I;
    E.E_P              = V .* I;
    E.E_Vstd_over_Istd = F.S_Battery_Voltage_Final_std20 ./ (F.S_Battery_Current_Final_std20 + 0.05);
end
end

function mdl = fit_ridge(X, y, lam)
mu = mean(X);  sd = std(X) + 1e-12;  Z = (X - mu) ./ sd;
beta = (Z'*Z + lam*eye(size(Z,2))) \ (Z' * (y - mean(y)));
mdl = struct('mu',mu,'sd',sd,'beta',beta,'ybar',mean(y));
end

function yhat = apply_ridge(mdl, X)
yhat = mdl.ybar + ((X - mdl.mu) ./ mdl.sd) * mdl.beta;
yhat = min(max(yhat, 0), 1);
end