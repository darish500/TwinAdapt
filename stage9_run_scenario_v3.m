function [T, out] = stage9_run_scenario_v3(cfg)
% Second output `out` is the raw Simulink output (native sample times,
% no resampling) -- added so callers that need to check an invariant
% BETWEEN two signals (e.g. "does the flag match a threshold on the
% irradiance") can do it at native sample alignment instead of through
% two independently-resampled reconstructions, which is what caused
% Closure Pass A's false FAIL at G=49/50/51 (see stage9_closure_passA_test12.m).
% stage9_run_scenario_v3  Same as stage9_run_scenario_v2, plus two new
% OPTIONAL cfg fields needed for the Stage 9 closure pass (isolated
% degradation scenarios B and C):
%
%   cfg.Freeze_PV_Aging       (logical, default false)
%       When true, sets k_Rs = k_Rsh = k_Iph = 0 for this run only, so
%       Rs_aged/Rsh_aged/Iph_aged stay pinned at their t=0 (reference)
%       value for the whole run -- i.e. "PV degradation held healthy."
%
%   cfg.Freeze_Battery_Aging  (logical, default false)
%       Same idea: sets k_R0 = k_R1 = k_Q = 0 for this run only, so
%       R0_aged/R1_aged/Q stay pinned at reference -- "Battery
%       degradation held healthy."
%
% Both flags only affect the CURRENT run (reformable_AI re-asserts the
% normal nonzero values on the next call, since it re-runs from a clean
% `clear` every time via evalin('base', ...) below) -- no permanent change
% to reformable_AI.m or the model.
%
% Everything else is identical to stage9_run_scenario_v2 -- see that file
% for the full field list and the explanation of the evalin/assignin
% workaround for reformable_AI.m's bare `clear`.

evalin('base', 'reformable_AI;');

% FIX (Closure Pass B investigation): PV_Degradation_Model's own code
% (Rs_aged = Rs_ref*(1+k_Rs*D_index), D_index = min(1,t/T_life)) is a
% pure function of t and the workspace constants -- confirmed clean, no
% persistent state. Yet Freeze_PV_Aging (k_Rs=0, confirmed present in the
% workspace via the diagnostic print below) had no visible effect on the
% SECOND sim() call in a session, while the equivalent Battery freeze
% worked fine on the FIRST call. That pattern -- correct workspace value,
% ignored by a later sim() call in the same session -- means Simulink is
% reusing a compiled copy of the model instead of re-reading the
% workspace. Forcing both of the two settings that can cause this (Fast
% Restart, and "Inline Parameters" baking values in at first compile)
% off removes the ambiguity rather than requiring us to diagnose which
% one it actually was.
set_param('Reformable_AI_2025','FastRestart','off');
set_param('Reformable_AI_2025','DefaultParameterBehavior','Tunable');

PV_Twin_Rs = evalin('base','PV_Twin_Rs');
Battery_Twin_R0 = evalin('base','Battery_Twin_R0');
Stage9_Feature_SampleTime = evalin('base','Stage9_Feature_SampleTime');

% ---- Defaults: healthy everything ----
if ~isfield(cfg,'PV_FaultType'),        cfg.PV_FaultType = 0; end
if ~isfield(cfg,'PV_FaultSeverity'),     cfg.PV_FaultSeverity = 0; end
if ~isfield(cfg,'Batt_FaultType'),       cfg.Batt_FaultType = 0; end
if ~isfield(cfg,'Batt_FaultSeverity'),   cfg.Batt_FaultSeverity = 0; end
if ~isfield(cfg,'PV_SensorTarget'),      cfg.PV_SensorTarget = 0; end
if ~isfield(cfg,'PV_SensorFaultType'),   cfg.PV_SensorFaultType = 0; end
if ~isfield(cfg,'PV_SensorFaultSeverity'), cfg.PV_SensorFaultSeverity = 0; end
if ~isfield(cfg,'Batt_SensorTarget'),    cfg.Batt_SensorTarget = 0; end
if ~isfield(cfg,'Batt_SensorFaultType'), cfg.Batt_SensorFaultType = 0; end
if ~isfield(cfg,'Batt_SensorFaultSeverity'), cfg.Batt_SensorFaultSeverity = 0; end
if ~isfield(cfg,'G_test'),               cfg.G_test = 1000; end
if ~isfield(cfg,'PV_Twin_Rs_Mult'),      cfg.PV_Twin_Rs_Mult = 1.0; end
if ~isfield(cfg,'Battery_Twin_R0_Mult'), cfg.Battery_Twin_R0_Mult = 1.0; end
if ~isfield(cfg,'Freeze_PV_Aging'),      cfg.Freeze_PV_Aging = false; end
if ~isfield(cfg,'Freeze_Battery_Aging'), cfg.Freeze_Battery_Aging = false; end
if ~isfield(cfg,'Scenario_Name'),        cfg.Scenario_Name = 'Unnamed'; end
if ~isfield(cfg,'Asset_State'),          cfg.Asset_State = 'Healthy'; end
if ~isfield(cfg,'Sensor_State'),         cfg.Sensor_State = 'Healthy'; end
if ~isfield(cfg,'Environment_State'),    cfg.Environment_State = 'Nominal'; end
if ~isfield(cfg,'Twin_State'),           cfg.Twin_State = 'Reference'; end

% ---- Apply config to the model / workspace ----
set_param('Reformable_AI_2025/Constant3','Value',num2str(cfg.PV_FaultType));
set_param('Reformable_AI_2025/Constant4','Value',num2str(cfg.PV_FaultSeverity));
set_param('Reformable_AI_2025/Constant5','Value',num2str(cfg.Batt_FaultType));
set_param('Reformable_AI_2025/Constant6','Value',num2str(cfg.Batt_FaultSeverity));
set_param('Reformable_AI_2025/Constant7','Value',num2str(cfg.PV_SensorTarget));
set_param('Reformable_AI_2025/Constant8','Value',num2str(cfg.PV_SensorFaultType));
set_param('Reformable_AI_2025/Constant9','Value',num2str(cfg.PV_SensorFaultSeverity));
set_param('Reformable_AI_2025/Constant10','Value',num2str(cfg.Batt_SensorTarget));
set_param('Reformable_AI_2025/Constant11','Value',num2str(cfg.Batt_SensorFaultType));
set_param('Reformable_AI_2025/Constant12','Value',num2str(cfg.Batt_SensorFaultSeverity));
set_param('Reformable_AI_2025/G_test','Value',num2str(cfg.G_test));

PV_Twin_Rs = PV_Twin_Rs * cfg.PV_Twin_Rs_Mult;
Battery_Twin_R0 = Battery_Twin_R0 * cfg.Battery_Twin_R0_Mult;
assignin('base','PV_Twin_Rs', PV_Twin_Rs);
assignin('base','Battery_Twin_R0', Battery_Twin_R0);

% ---- Aging-freeze overrides for isolated degradation scenarios ----
% FIX (Closure Pass B, final): assignin('base','k_Rs',0) was confirmed
% present in the base workspace immediately before every sim() call --
% correct value, correct Constant block ("k_Rs" by name), correct port
% wiring into the MATLAB Function (checked directly, port-by-port) -- and
% yet the simulated Rs_aged behaved as if k_Rs were still 0.5 the entire
% run, and the workspace variable k_Rs itself was found reset back to
% 0.5 immediately after sim() returned, with no model callback (PreLoad/
% PostLoad/Init/Start/Stop/Pause/Continue/Close -- all checked, all
% empty), no Fast Restart, no Accelerator-mode caching, and no "To
% Workspace" block logging anything named k_Rs (checked -- full list of
% every To Workspace block in the model) able to account for it. Rather
% than keep chasing whatever is silently rewriting that one workspace
% variable, this bypasses the workspace variable entirely: it writes the
% literal number straight into the Constant block's own Value field
% (the same way PV_FaultType/PV_FaultSeverity etc. are already set a few
% lines up), which nothing else in the model has any occasion to touch.
% Restores the block to its normal symbolic reference afterward so every
% other (non-frozen) scenario still ages normally.
pvAgingConsts   = {'PV_Degradation_Model/Constant4', 'PV_Degradation_Model/Constant5', 'PV_Degradation_Model/Constant6'};
pvAgingSymbols  = {'k_Rs', 'k_Rsh', 'k_Iph'};
battAgingConsts  = {'Battery_Degradation_Model/k_R0', 'Battery_Degradation_Model/k_R1', 'Battery_Degradation_Model/k_Q'};
battAgingSymbols = {'k_R0', 'k_R1', 'k_Q'};

if cfg.Freeze_PV_Aging
    for i = 1:numel(pvAgingConsts)
        set_param(['Reformable_AI_2025/' pvAgingConsts{i}], 'Value', '0');
    end
else
    for i = 1:numel(pvAgingConsts)
        set_param(['Reformable_AI_2025/' pvAgingConsts{i}], 'Value', pvAgingSymbols{i});
    end
end

if cfg.Freeze_Battery_Aging
    for i = 1:numel(battAgingConsts)
        set_param(['Reformable_AI_2025/' battAgingConsts{i}], 'Value', '0');
    end
else
    for i = 1:numel(battAgingConsts)
        set_param(['Reformable_AI_2025/' battAgingConsts{i}], 'Value', battAgingSymbols{i});
    end
end

% Diagnostic print -- now reads the block's actual Value field (what the
% model will really use), not the workspace variable that turned out to
% be unreliable.
fprintf('[%s] PV Constants  k_Rs=%s k_Rsh=%s k_Iph=%s | Battery Constants  k_R0=%s k_R1=%s k_Q=%s\n', ...
    cfg.Scenario_Name, ...
    get_param(['Reformable_AI_2025/' pvAgingConsts{1}],'Value'), ...
    get_param(['Reformable_AI_2025/' pvAgingConsts{2}],'Value'), ...
    get_param(['Reformable_AI_2025/' pvAgingConsts{3}],'Value'), ...
    get_param(['Reformable_AI_2025/' battAgingConsts{1}],'Value'), ...
    get_param(['Reformable_AI_2025/' battAgingConsts{2}],'Value'), ...
    get_param(['Reformable_AI_2025/' battAgingConsts{3}],'Value'));

out = sim('Reformable_AI_2025');

% ---- Common time grid: the Stage 9 feature blocks' own fixed rate ----
t_grid = (0:Stage9_Feature_SampleTime:out.tout(end))';
rs  = @(sig) resample_signal(sig, t_grid);
rsb = @(sig) resample_signal_bool(sig, t_grid);

% ================= PV deployment features =================
PV_Irradiance_Final  = rs(out.PV_Irradiance_Final);
PV_Temperature_Final = rs(out.PV_Temperature_Final);
PV_Voltage_Final     = rs(out.PV_Voltage_Final);
PV_Current_Final     = rs(out.PV_Current_Final);
PV_Twin_Current       = rs(out.PV_Twin_Current);
PV_Twin_Power          = rs(out.PV_Twin_Power);
PV_Residual_Current    = rs(out.PV_Residual_Current);
PV_Residual_Power      = rs(out.PV_Residual_Power);
PV_AbsResidual_Current = rs(out.PV_AbsResidual_Current);
PV_AbsResidual_Power   = rs(out.PV_AbsResidual_Power);
PV_Normalized_Current_Residual = rs(out.PV_Normalized_Current_Residual);
PV_Normalized_Power_Residual   = rs(out.PV_Normalized_Power_Residual);
PV_Residual_Current_Mean   = rs(out.PV_Residual_Current_Mean);
PV_Residual_Current_Std    = rs(out.PV_Residual_Current_Std);
PV_Residual_Current_MaxAbs = rs(out.PV_Residual_Current_MaxAbs);
PV_Residual_Power_Mean     = rs(out.PV_Residual_Power_Mean);
PV_Residual_Power_Std      = rs(out.PV_Residual_Power_Std);
PV_Residual_Power_MaxAbs   = rs(out.PV_Residual_Power_MaxAbs);
PV_Residual_Current_Trend  = rs(out.PV_Residual_Current_Trend);
PV_Residual_Power_Trend    = rs(out.PV_Residual_Power_Trend);
PV_Valid_Operating_Condition = rsb(out.PV_Valid_Operating_Condition);
PV_Feature_Window_Valid      = rsb(out.PV_Feature_Window_Valid);
PV_Trend_Window_Valid        = rsb(out.PV_Trend_Window_Valid);
PV_Twin_Valid_Operating_Point = rsb(out.PV_Twin_Valid_Operating_Point);

% ================= Battery deployment features =================
Battery_Voltage_Final     = rs(out.Battery_Voltage_Final);
Battery_Current_Final     = rs(out.Battery_Current_Final);
Battery_Temperature_Final = rs(out.Battery_Temperature_Final);
Battery_Twin_Voltage      = rs(out.Battery_Twin_Voltage);
Battery_Twin_SOC_Estimate = rs(out.Battery_Twin_SOC_Estimate);
Battery_Residual_Voltage             = rs(out.Battery_Residual_Voltage);
Battery_AbsResidual_Voltage          = rs(out.Battery_AbsResidual_Voltage);
Battery_Normalized_Voltage_Residual  = rs(out.Battery_Normalized_Voltage_Residual);
Battery_Residual_Voltage_Mean   = rs(out.Battery_Residual_Voltage_Mean);
Battery_Residual_Voltage_Std    = rs(out.Battery_Residual_Voltage_Std);
Battery_Residual_Voltage_MaxAbs = rs(out.Battery_Residual_Voltage_MaxAbs);
Battery_Residual_Voltage_Trend  = rs(out.Battery_Residual_Voltage_Trend);
Battery_Feature_Window_Valid = rsb(out.Battery_Feature_Window_Valid);
Battery_Trend_Window_Valid   = rsb(out.Battery_Trend_Window_Valid);

% ================= Evaluation metadata =================
True_PV_Irradiance  = rs(out.True_PV_Irradiance);
True_PV_Temperature = rs(out.True_PV_Temperature);
True_PV_Voltage     = rs(out.True_PV_Voltage);
True_PV_Current     = rs(out.True_PV_Current);
Rs_aged  = rs(out.Rs_aged);
Fault_Type     = rs(out.Fault_Type);
Fault_Severity = rs(out.Fault_Severity);
Fault_Active   = rsb(out.Fault_Active);
PV_SensorFault_Type     = rs(out.PV_SensorFault_Type);
PV_SensorFault_Severity = rs(out.PV_SensorFault_Severity);
PV_SensorFault_Active   = rsb(out.PV_SensorFault_Active);

True_Battery_Voltage     = rs(out.True_Battery_Voltage);
True_Battery_Current     = rs(out.True_Battery_Current);
True_Battery_Temperature = rs(out.True_Battery_Temperature);
R0_aged = rs(out.R0_aged);
Battery_Fault_Type     = rs(out.Battery_Fault_Type);
Battery_Fault_Severity = rs(out.Battery_Fault_Severity);
Battery_Fault_Active   = rsb(out.Battery_Fault_Active);
Battery_SensorFault_Type     = rs(out.Battery_SensorFault_Type);
Battery_SensorFault_Severity = rs(out.Battery_SensorFault_Severity);
Battery_SensorFault_Active   = rsb(out.Battery_SensorFault_Active);

N = numel(t_grid);
Scenario_Name     = repmat({cfg.Scenario_Name}, N, 1);
Asset_State       = repmat({cfg.Asset_State}, N, 1);
Sensor_State      = repmat({cfg.Sensor_State}, N, 1);
Environment_State = repmat({cfg.Environment_State}, N, 1);
Twin_State        = repmat({cfg.Twin_State}, N, 1);

T = table(t_grid, ...
    PV_Irradiance_Final, PV_Temperature_Final, PV_Voltage_Final, PV_Current_Final, ...
    PV_Twin_Current, PV_Twin_Power, PV_Residual_Current, PV_Residual_Power, ...
    PV_AbsResidual_Current, PV_AbsResidual_Power, ...
    PV_Normalized_Current_Residual, PV_Normalized_Power_Residual, ...
    PV_Residual_Current_Mean, PV_Residual_Current_Std, PV_Residual_Current_MaxAbs, ...
    PV_Residual_Power_Mean, PV_Residual_Power_Std, PV_Residual_Power_MaxAbs, ...
    PV_Residual_Current_Trend, PV_Residual_Power_Trend, ...
    PV_Valid_Operating_Condition, PV_Feature_Window_Valid, PV_Trend_Window_Valid, PV_Twin_Valid_Operating_Point, ...
    Battery_Voltage_Final, Battery_Current_Final, Battery_Temperature_Final, ...
    Battery_Twin_Voltage, Battery_Twin_SOC_Estimate, ...
    Battery_Residual_Voltage, Battery_AbsResidual_Voltage, Battery_Normalized_Voltage_Residual, ...
    Battery_Residual_Voltage_Mean, Battery_Residual_Voltage_Std, Battery_Residual_Voltage_MaxAbs, Battery_Residual_Voltage_Trend, ...
    Battery_Feature_Window_Valid, Battery_Trend_Window_Valid, ...
    True_PV_Irradiance, True_PV_Temperature, True_PV_Voltage, True_PV_Current, Rs_aged, ...
    Fault_Type, Fault_Severity, Fault_Active, ...
    PV_SensorFault_Type, PV_SensorFault_Severity, PV_SensorFault_Active, ...
    True_Battery_Voltage, True_Battery_Current, True_Battery_Temperature, R0_aged, ...
    Battery_Fault_Type, Battery_Fault_Severity, Battery_Fault_Active, ...
    Battery_SensorFault_Type, Battery_SensorFault_Severity, Battery_SensorFault_Active, ...
    Scenario_Name, Asset_State, Sensor_State, Environment_State, Twin_State);

end

function y = resample_signal(sig, t_grid)
if numel(sig.Time) < 2
    y = repmat(double(sig.Data(1)), numel(t_grid), 1);
else
    y = interp1(sig.Time, double(sig.Data), t_grid, 'linear', 'extrap');
end
end

function y = resample_signal_bool(sig, t_grid)
% resample_signal_bool  Zero-order-hold resampling for discrete/boolean
% flag signals (Valid_Operating_Condition, Window_Valid, Fault_Active,
% etc). FIX (Closure Pass A): these flags were previously resampled with
% the same LINEAR interpolation used for continuous signals like
% irradiance. Linearly interpolating a 0/1 step produces a ramp between
% native samples, so its reconstructed threshold-crossing time doesn't
% line up with a continuous signal's (e.g. irradiance crossing
% Stage9_Min_Irradiance) reconstructed crossing time -- that mismatch is
% exactly what caused Test 12's false FAIL at G=49/50/51, even though
% the native-sample diagnostic proved the model itself is correct
% (0/1501 mismatches at Simulink's own sample times). A flag only ever
% changes at a native sample and holds its value until the next one, so
% 'previous' (zero-order hold) is the correct reconstruction -- not
% linear -- and needs no >=0.5 threshold afterward since it only ever
% returns exactly 0 or 1.
if numel(sig.Time) < 2
    y = repmat(double(sig.Data(1)), numel(t_grid), 1);
else
    y = interp1(sig.Time, double(sig.Data), t_grid, 'previous', 'extrap');
    y(isnan(y)) = double(sig.Data(1));  % extrap before the first native sample
end
y = logical(y >= 0.5);
end