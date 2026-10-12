function Stage11_eval_mismatch(tag)
rng(1);
fa = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
fe = {['Stage11_Features_' tag '_PV.csv'], ['Stage11_Features_' tag '_Battery.csv']};
assets = {'PV','Battery'};  regCol = {'splitA','splitB'};  regName = {'A: unseen levels','B: unseen profile'};
rows = {};
for a = 1:2
    FA = readtable(fa{a});  FA = [FA engineer(FA, assets{a})];
    FE = readtable(fe{a});  FE = [FE engineer(FE, assets{a})];
    assert(isequal(FA.run, FE.run) && isequal(FA.t, FE.t), 'rows of A and %s do not line up', tag);
    vn = FA.Properties.VariableNames;
    Sc = vn(startsWith(vn,'S_'));  Ec = vn(startsWith(vn,'E_'));  Tc = vn(startsWith(vn,'T_'));
    for r = 1:2
        sp  = string(FA.(regCol{r}));
        tr  = sp == "train";   te = sp == "test";               % same runs in A and in the mismatched set
        for m = ["ridge","trees"]
            res = zeros(1,3);                                    % MAE: sensor-strong, Twin exact, Twin mismatched
            % sensor-strong (inputs are identical in A and the mismatched set)
            cols = [Sc Ec];
            yhat = fit_predict(m, FA{tr,cols}, FA.D(tr), FE{te,cols});
            res(1) = mean(abs(yhat - FE.D(te)));
            % strong + Twin: trained on exact-Twin data, scored on exact and on mismatched Twin
            cols = [Sc Ec Tc];
            mdl = fit_model(m, FA{tr,cols}, FA.D(tr));
            res(2) = mean(abs(apply_model(m, mdl, FA{te,cols}) - FA.D(te)));
            res(3) = mean(abs(apply_model(m, mdl, FE{te,cols}) - FE.D(te)));
            adv0 = res(1) - res(2);   adv1 = res(1) - res(3);
            rows(end+1,:) = {assets{a}, regName{r}, char(m), round(res(1),4), round(res(2),4), round(res(3),4), ...
                             round(adv0,4), round(adv1,4), round(100*adv1/max(adv0,eps),0)}; %#ok<AGROW>
        end
    end
end
R = cell2table(rows, 'VariableNames', {'Asset','Regime','Model','MAE_sensor','MAE_twin_exact','MAE_twin_mismatch', ...
                                       'Advantage_exact','Advantage_mismatch','Pct_advantage_kept'});
fprintf('\n=== Dataset %s: Twin trained on exact data, scored on mismatched Twin ===\n', tag);
disp(R);
writetable(R, ['Stage11_Eval_' tag '.csv']);
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

function yhat = fit_predict(m, Xtr, ytr, Xte)
yhat = apply_model(m, fit_model(m, Xtr, ytr), Xte);
end

function mdl = fit_model(m, X, y)
if m == "trees"
    mdl = fitrensemble(X, y, 'Method','Bag', 'NumLearningCycles',100, 'Learners', templateTree('MinLeafSize',5));
else
    mu = mean(X);  sd = std(X) + 1e-12;  Z = (X - mu) ./ sd;
    beta = (Z'*Z + eye(size(Z,2))) \ (Z' * (y - mean(y)));
    mdl = struct('mu',mu,'sd',sd,'beta',beta,'ybar',mean(y));
end
end

function yhat = apply_model(m, mdl, X)
if m == "trees", yhat = predict(mdl, X);
else, yhat = mdl.ybar + ((X - mdl.mu) ./ mdl.sd) * mdl.beta; end
yhat = min(max(yhat, 0), 1);
end