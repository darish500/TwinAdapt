function stage9_closure_passA_test12()
% stage9_closure_passA_test12  Stage 9 Closure Pass A -- the missing
% Validation Test 12 (low-irradiance / near-zero normalization edge case).
%
% Runs the Healthy scenario at a sweep of irradiance levels straddling
% Stage9_Min_Irradiance (including values BELOW zero-generation, right at
% the threshold, and comfortably above it), then checks for every claim
% Khalid's reviewer asked us to actually demonstrate rather than assume:
%
%   - no NaN/Inf anywhere in the PV deployment feature columns
%   - PV_Normalized_Current_Residual / PV_Normalized_Power_Residual stay
%     finite and bounded (division is by a FIXED nameplate constant, so
%     this should hold at every G, including G=0)
%   - PV_Valid_Operating_Condition correctly flips to false below
%     Stage9_Min_Irradiance and true at/above it
%   - PV_Twin_Valid_Operating_Point behaves sanely across the sweep
%   - PV_Twin_Current / PV_Twin_Power (the Newton-Raphson solve) do not
%     blow up or go complex at low G
%
% No architecture change. This only exercises the existing blocks at an
% input condition the dataset build never actually tried.

evalin('base','reformable_AI;');
Stage9_Min_Irradiance = evalin('base','Stage9_Min_Irradiance');
fprintf('Stage9_Min_Irradiance = %.1f W/m^2 (the documented threshold)\n\n', Stage9_Min_Irradiance);

G_sweep = [0, 1, 10, Stage9_Min_Irradiance-1, Stage9_Min_Irradiance, Stage9_Min_Irradiance+1, 100, 1000];

allRows = {};
results = table();

for i = 1:numel(G_sweep)
    g = G_sweep(i);
    cfg = struct('G_test', g, ...
        'Scenario_Name', sprintf('Test12_G%g', g), ...
        'Asset_State','Healthy', 'Sensor_State','Healthy', ...
        'Environment_State', sprintf('G%g', g), 'Twin_State','Reference');
    [T, out] = stage9_run_scenario_v3(cfg);
    allRows{end+1} = T; %#ok<AGROW>

    pvCols = {'PV_Irradiance_Final','PV_Current_Final','PV_Twin_Current','PV_Twin_Power', ...
        'PV_Residual_Current','PV_Residual_Power','PV_AbsResidual_Current','PV_AbsResidual_Power', ...
        'PV_Normalized_Current_Residual','PV_Normalized_Power_Residual', ...
        'PV_Residual_Current_Mean','PV_Residual_Current_Std','PV_Residual_Current_MaxAbs', ...
        'PV_Residual_Current_Trend'};

    nanInfCount = 0;
    worstCol = '';
    for c = 1:numel(pvCols)
        v = T.(pvCols{c});
        bad = ~isfinite(v);
        n = sum(bad);
        if n > 0 && nanInfCount == 0
            worstCol = pvCols{c};
        end
        nanInfCount = nanInfCount + n;
    end

    % IMPORTANT (fixed twice now -- see comments below for the full
    % history): compare the flag against the ACTUAL measured irradiance
    % (PV_Irradiance_Final), not the nominal commanded G_test, and do it
    % at NATIVE Simulink sample times, not through two independently
    % resampled reconstructions.
    %
    % History: (1) originally compared the flag against nominal G_test
    % instead of the real noisy measured irradiance -- wrong invariant,
    % fixed. (2) After that fix still showed FAIL at G=49/50/51: both
    % signals were being resampled onto a common t_grid via
    % stage9_run_scenario_v3's `rs`/`rsb` helpers, one with linear
    % interpolation (irradiance) and one with zero-order hold (the
    % flag) -- two different reconstructions of time, so their crossing
    % points don't exactly coincide near a threshold crossing even
    % though neither reconstruction is "wrong" on its own. A prior
    % diagnostic (comparing raw out.PV_Irradiance_Final.Data against
    % raw out.PV_Valid_Operating_Condition.Data at Simulink's own native
    % sample times, no resampling at all) already proved 0/1501
    % mismatches -- the model itself is correct. So this check now uses
    % that same native data directly, via the `out` struct
    % stage9_run_scenario_v3 returns as its second output, instead of
    % the resampled table T.
    nativeIrradiance = double(out.PV_Irradiance_Final.Data);
    nativeFlag       = double(out.PV_Valid_Operating_Condition.Data) >= 0.5;
    expectValidNative = nativeIrradiance >= Stage9_Min_Irradiance;
    validFlagOK = all(nativeFlag == expectValidNative);

    twinCurrentIsReal = isreal(T.PV_Twin_Current) && all(isfinite(T.PV_Twin_Current));
    normResidualBounded = all(abs(T.PV_Normalized_Current_Residual) < 10) && ...
                           all(abs(T.PV_Normalized_Power_Residual) < 10);

    verdict = "PASS";
    if nanInfCount > 0 || ~validFlagOK || ~twinCurrentIsReal || ~normResidualBounded
        verdict = "FAIL";
    end

    row = table(g, nanInfCount, string(worstCol), validFlagOK, twinCurrentIsReal, ...
        normResidualBounded, verdict, ...
        'VariableNames', {'G_test','NaNInfCount','FirstBadColumn','ValidFlagCorrect', ...
                           'TwinCurrentFiniteReal','NormResidualBounded','Verdict'});
    results = [results; row]; %#ok<AGROW>
end

disp(results);

FullDataset_Test12 = vertcat(allRows{:});
save('Stage9_Test12_LowIrradiance.mat','FullDataset_Test12','results');
writetable(results, 'Stage9_Test12_Summary.csv');
writetable(FullDataset_Test12, 'Stage9_Test12_LowIrradiance.csv');

fprintf('\nSaved Stage9_Test12_Summary.csv (%d rows, one per G level) and\n', height(results));
fprintf('Stage9_Test12_LowIrradiance.csv (%d full rows across the sweep).\n', height(FullDataset_Test12));

if all(results.Verdict == "PASS")
    fprintf('\n>>> TEST 12: PASS across the full G sweep (%s).\n', mat2str(G_sweep));
else
    fprintf('\n>>> TEST 12: FAIL -- see rows marked FAIL above for which G level and which check broke.\n');
end

end