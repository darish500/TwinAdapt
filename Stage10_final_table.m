function Stage10_final_table()
% Full metric set and the Stage 10 ablation table (spec section 24). Also saves test-set predictions for the plots.
rng(1);
assets  = {'PV','Battery'};
files   = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
regCol  = {'splitA','splitB'};
regKey  = {'A','B'};
selSens = {'nn','ridge'};   selSensSet = {'S3','S2'};     % sensor-only model chosen by Stage10_tinyml (PV, battery)
selFull = {'nn','ridge'};   selFullSet = {'C2','C2'};     % Twin-using model chosen by Stage10_tinyml
Long = {};  Pred = struct();

for a = 1:2
    F  = readtable(files{a});  F = [F engineer(F, assets{a})];
    vn = F.Properties.VariableNames;
    S  = vn(startsWith(vn,'S_'));  E = vn(startsWith(vn,'E_'));  T = vn(startsWith(vn,'T_'));
    tW = endsWith(T,'_Mean') | endsWith(T,'_Std') | endsWith(T,'_MaxAbs') | endsWith(T,'_Trend');
    Ti = T(~tW);  Tw = T(tW);  Tr = Ti(contains(Ti,'Residual'));
    sets = struct('S2',{S}, 'S3',{[S E]}, 'T1',{T}, 'C1',{[S E Tr]}, 'C2',{[S E Tw]});

    rowsDef = { 'base',   'Baseline predictor (training mean)',   'const',     '';
                'sensR',  'Sensor-only, ridge',                   'ridge',     'S2';
                'sensSel','Sensor-only, selected',                selSens{a},  selSensSet{a};
                'twin',   'Twin-only, ridge',                     'ridge',     'T1';
                'c1',     'Sensor + raw residual, ridge',         'ridge',     'C1';
                'c2',     'Sensor + temporal residual, ridge',    'ridge',     'C2';
                'full',   'Full selected Sensor + Twin',          selFull{a},  selFullSet{a} };

    for r = 1:2
        sp = string(F.(regCol{r}));  tr = sp == "train";  te = sp == "test";
        y  = F.D(te);
        for k = 1:size(rowsDef,1)
            key = rowsDef{k,1};  mdlName = rowsDef{k,3};  setName = rowsDef{k,4};
            if strcmp(mdlName,'const')
                p = mean(F.D(tr)) * ones(size(y));   nF = 0;   flash = 4;
            else
                cols = sets.(setName);  X = F{:,cols};  nF = numel(cols);
                if strcmp(mdlName,'ridge')
                    p = apply_ridge(fit_ridge(X(tr,:), F.D(tr), 1), X(te,:));   flash = 4*(nF+1);
                else
                    rng(1);
                    mn = fitrnet(X(tr,:), F.D(tr), 'LayerSizes', 8, 'Standardize', true, ...
                                 'Activations','relu', 'IterationLimit', 300, 'Verbose', 0);
                    p = min(max(predict(mn, X(te,:)), 0), 1);   flash = 4*((nF+1)*8 + 9);
                end
            end
            m = metrics(y, p);
            Pred.(assets{a}).(regKey{r}).(key) = struct('run',F.run(te), 't',F.t(te), 'y',y, 'p',p);
            Long(end+1,:) = {assets{a}, regKey{r}, key, rowsDef{k,2}, mdlName, setName, nF, flash, ...
                             round(m.MAE,4), round(m.RMSE,4), round(m.R2,3), round(m.nRMSE,4), round(m.Bias,4), round(m.MaxAE,4), round(m.Spearman,3)}; %#ok<AGROW>
        end
    end
end

Lt = cell2table(Long, 'VariableNames', {'Asset','Regime','RowKey','Label','Model','FeatureSet','Features','Flash_B', ...
                                        'MAE','RMSE','R2','nRMSE','Bias','MaxAE','Spearman'});
writetable(Lt, 'Stage10_Final_Metrics.csv');
save('Stage10_Predictions.mat', 'Pred');

fprintf('\n=== FULL METRICS (every row, both regimes) ===\n');
disp(Lt(:, {'Asset','Regime','RowKey','Model','FeatureSet','MAE','RMSE','R2','nRMSE','Bias','MaxAE','Spearman'}));

regTitle = {'Regime A: unseen health levels','Regime B: unseen operating profile'};
for r = 1:2
    W = {};
    for k = 1:size(rowsDef,1)
        key = rowsDef{k,1};
        p = Lt(strcmp(Lt.Asset,'PV')      & strcmp(Lt.Regime,regKey{r}) & strcmp(Lt.RowKey,key), :);
        b = Lt(strcmp(Lt.Asset,'Battery') & strcmp(Lt.Regime,regKey{r}) & strcmp(Lt.RowKey,key), :);
        W(end+1,:) = {rowsDef{k,2}, p.MAE, p.RMSE, p.R2, b.MAE, b.RMSE, b.R2, p.Features, b.Features, p.Flash_B, b.Flash_B}; %#ok<AGROW>
    end
    W = cell2table(W, 'VariableNames', {'Model_Input','PV_MAE','PV_RMSE','PV_R2','Batt_MAE','Batt_RMSE','Batt_R2', ...
                                        'PV_Features','Batt_Features','PV_Size_B','Batt_Size_B'});
    fprintf('\n=== ABLATION TABLE (spec section 24), %s ===\n', regTitle{r});
    disp(W);
    writetable(W, sprintf('Stage10_Ablation_Table_%s.csv', regKey{r}));
end
fprintf(['\nNotes: size = float32 parameters in bytes. "Selected" rows use the neural network for PV (single seed 1) and ridge for the battery.\n' ...
         'The baseline predictor has no features and no meaningful Spearman correlation (NaN).\nSaved Stage10_Final_Metrics.csv, Stage10_Ablation_Table_A/B.csv, Stage10_Predictions.mat\n']);
end

function m = metrics(y, p)
e = p - y;
m.MAE   = mean(abs(e));
m.RMSE  = sqrt(mean(e.^2));
m.R2    = 1 - sum(e.^2) / sum((y - mean(y)).^2);
m.nRMSE = m.RMSE / (max(y) - min(y));
m.Bias  = mean(e);
m.MaxAE = max(abs(e));
if std(p) < 1e-12, m.Spearman = NaN; else, m.Spearman = corr(y, p, 'Type', 'Spearman'); end
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