function Stage11_eval_mismatch_aware(tag)
% Train AND test on the mismatched Twin (train runs -> test runs), instead of training on the exact Twin.
rng(1);
fe = {['Stage11_Features_' tag '_PV.csv'], ['Stage11_Features_' tag '_Battery.csv']};
assets = {'PV','Battery'};  regCol = {'splitA','splitB'};  regName = {'A: unseen levels','B: unseen profile'};
rows = {};
for a = 1:2
    F = readtable(fe{a});  F = [F engineer(F, assets{a})];
    vn = F.Properties.VariableNames;
    Sc = vn(startsWith(vn,'S_'));  Ec = vn(startsWith(vn,'E_'));  Tc = vn(startsWith(vn,'T_'));
    for r = 1:2
        sp = string(F.(regCol{r}));  tr = sp == "train";  te = sp == "test";
        for m = ["ridge","trees"]
            cS = [Sc Ec];       cT = [Sc Ec Tc];
            eS = mean(abs(apply_model(m, fit_model(m, F{tr,cS}, F.D(tr)), F{te,cS}) - F.D(te)));
            eT = mean(abs(apply_model(m, fit_model(m, F{tr,cT}, F.D(tr)), F{te,cT}) - F.D(te)));
            rows(end+1,:) = {assets{a}, regName{r}, char(m), round(eS,4), round(eT,4), round(eS-eT,4)}; %#ok<AGROW>
        end
    end
end
R = cell2table(rows, 'VariableNames', {'Asset','Regime','Model','MAE_sensor','MAE_twin_trained_on_mismatch','Advantage'});
fprintf('\n=== Dataset %s: trained AND tested on the mismatched Twin ===\n', tag);
disp(R);
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