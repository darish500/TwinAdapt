function Stage10_cv_compare()
rng(1);
files  = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
assets = {'PV','Battery'};
schemes = {'A: leave-one-level-out',   'level',   [1 2 3]; ...
           'B: leave-one-profile-out', 'profile', [1 2 3 4]};

rows = {};   wins = {};
for a = 1:2
    F = readtable(files{a});
    F = [F engineer(F, assets{a})];                      % add the E_ columns (10a)
    vn = F.Properties.VariableNames;
    Sc = vn(startsWith(vn,'S_'));  Ec = vn(startsWith(vn,'E_'));  Tc = vn(startsWith(vn,'T_'));
    sets = {'sensor-basic', Sc; 'sensor-strong', [Sc Ec]; 'strong+Twin', [Sc Ec Tc]};
    y = F.D;
    for k = 1:size(schemes,1)
        gcol = schemes{k,2};  folds = schemes{k,3};
        for m = ["trees","ridge"]
            fm = zeros(size(sets,1), numel(folds));          % MAE of each set in each fold
            for s = 1:size(sets,1)
                X = F{:, sets{s,2}};
                yhat = nan(height(F),1);
                for f = 1:numel(folds)
                    te = F.(gcol) == folds(f);               % the held-out runs
                    yhat(te) = fit_predict(m, X(~te,:), y(~te), X(te,:));
                    fm(s,f)  = mean(abs(yhat(te) - y(te)));
                end
                held = ~isnan(yhat);
                mae  = mean(abs(yhat(held) - y(held)));
                r2   = 1 - sum((yhat(held)-y(held)).^2) / sum((y(held)-mean(y(held))).^2);
                rows(end+1,:) = {assets{a}, schemes{k,1}, char(m), sets{s,1}, round(mae,4), round(r2,3), ...
                                 sprintf('%.3f +- %.3f', mean(fm(s,:)), std(fm(s,:)))}; %#ok<AGROW>
            end
            nw = sum(fm(3,:) < fm(2,:));                     % folds where Twin beats strong sensor-only
            wins(end+1,:) = {assets{a}, schemes{k,1}, char(m), sprintf('%d of %d', nw, numel(folds))}; %#ok<AGROW>
        end
    end
end
R = cell2table(rows, 'VariableNames', {'Asset','Scheme','Model','Features','pooledMAE','pooledR2','foldMAE_mean_std'});
W = cell2table(wins, 'VariableNames', {'Asset','Scheme','Model','Twin_beats_strong_sensor_in_folds'});
disp(R);  disp(W);
writetable(R, 'Stage10_CV_Results_DatasetA.csv');
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
    E.E_V_over_I     = V ./ I;
    E.E_P            = V .* I;
    E.E_Vstd_over_Istd = F.S_Battery_Voltage_Final_std20 ./ (F.S_Battery_Current_Final_std20 + 0.05);
end
end

function yhat = fit_predict(m, Xtr, ytr, Xte)
if m == "trees"
    mdl  = fitrensemble(Xtr, ytr, 'Method','Bag', 'NumLearningCycles',100, ...
                        'Learners', templateTree('MinLeafSize',5));
    yhat = predict(mdl, Xte);
else
    mu = mean(Xtr);  sd = std(Xtr) + 1e-12;
    Z  = (Xtr - mu) ./ sd;
    beta = (Z'*Z + 1*eye(size(Z,2))) \ (Z' * (ytr - mean(ytr)));
    yhat = mean(ytr) + ((Xte - mu) ./ sd) * beta;
end
yhat = min(max(yhat, 0), 1);
end