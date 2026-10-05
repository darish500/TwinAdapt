function T = stage9_run_scenario_v2(cfg)
% stage9_run_scenario  Run ONE Stage 9 scenario and return a tagged table.
%
% cfg is a struct with fields (all optional; missing = healthy default):
%   .PV_FaultType, .PV_FaultSeverity          (Constant3/4)
%   .Batt_FaultType, .Batt_FaultSeverity      (Constant5/6)
%   .PV_SensorTarget, .PV_SensorFaultType, .PV_SensorFaultSeverity   (Constant7/8/9)
%   .Batt_SensorTarget, .Batt_SensorFaultType, .Batt_SensorFaultSeverity (Constant10/11/12)
%   .G_test                                   (irradiance override, W/m^2)
%   .PV_Twin_Rs_Mult                          (e.g. 1.05 for +5% Twin mismatch)
%   .Battery_Twin_R0_Mult
%   .Scenario_Name, .Asset_State, .Sensor_State, .Environment_State, .Twin_State
%     (human-readable labels for this run -- EVALUATION METADATA ONLY,
%     constructed here from what WE told the model to do, never read back
%     out of the model. These never enter the deployment feature columns.)
%
% Returns a table T with one row per Stage9_Feature_SampleTime step,
% deployment features and evaluation metadata as separate column blocks,
% scenario labels repeated on every row of this run.

% reformable_AI.m opens with a bare `clear`, and creates variables like
% C1, Rs, Q, etc. Running it as a plain script from inside a function
% (as we do here) puts all of those variables into THIS FUNCTION's
% private workspace -- not the shared base workspace Simulink actually
% reads from when it resolves a block's parameters (e.g.
% Battery_Model/C1_block looking up "C1"). That mismatch is what caused
% the "Variable C1 has been deleted from base workspace" error.
%
% Fix: force reformable_AI to run AS IF typed directly in the base
% workspace, via evalin. This also protects cfg automatically -- the
% `clear` inside reformable_AI now only clears the BASE workspace, never
% touching this function's own local variables, so the earlier temp-file
% round-trip for cfg is no longer needed at all.
evalin('base', 'reformable_AI;');

% Pull the few base-workspace variables THIS function needs to read or
% modify directly (Twin mismatch, and the feature sample time for the
% resampling grid below).
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

out = sim('Reformable_AI_2025');

% ---- Common time grid: the Stage 9 feature blocks' own fixed rate ----
t_grid = (0:Stage9_Feature_SampleTime:out.tout(end))';

% ---- Helper: resample any logged timeseries onto t_grid ----
rs = @(sig) resample_signal(sig, t_grid);

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
PV_Valid_Operating_Condition = rs(out.PV_Valid_Operating_Condition) >= 0.5;
PV_Feature_Window_Valid      = rs(out.PV_Feature_Window_Valid) >= 0.5;
PV_Trend_Window_Valid        = rs(out.PV_Trend_Window_Valid) >= 0.5;
PV_Twin_Valid_Operating_Point = rs(out.PV_Twin_Valid_Operating_Point) >= 0.5;

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
Battery_Feature_Window_Valid = rs(out.Battery_Feature_Window_Valid) >= 0.5;
Battery_Trend_Window_Valid   = rs(out.Battery_Trend_Window_Valid) >= 0.5;

% ================= Evaluation metadata (ground truth, NEVER a feature) =================
True_PV_Irradiance  = rs(out.True_PV_Irradiance);
True_PV_Temperature = rs(out.True_PV_Temperature);
True_PV_Voltage     = rs(out.True_PV_Voltage);
True_PV_Current     = rs(out.True_PV_Current);
Rs_aged  = rs(out.Rs_aged);
Fault_Type     = rs(out.Fault_Type);
Fault_Severity = rs(out.Fault_Severity);
Fault_Active   = rs(out.Fault_Active) >= 0.5;
PV_SensorFault_Type     = rs(out.PV_SensorFault_Type);
PV_SensorFault_Severity = rs(out.PV_SensorFault_Severity);
PV_SensorFault_Active   = rs(out.PV_SensorFault_Active) >= 0.5;

True_Battery_Voltage     = rs(out.True_Battery_Voltage);
True_Battery_Current     = rs(out.True_Battery_Current);
True_Battery_Temperature = rs(out.True_Battery_Temperature);
R0_aged = rs(out.R0_aged);
Battery_Fault_Type     = rs(out.Battery_Fault_Type);
Battery_Fault_Severity = rs(out.Battery_Fault_Severity);
Battery_Fault_Active   = rs(out.Battery_Fault_Active) >= 0.5;
Battery_SensorFault_Type     = rs(out.Battery_SensorFault_Type);
Battery_SensorFault_Severity = rs(out.Battery_SensorFault_Severity);
Battery_SensorFault_Active   = rs(out.Battery_SensorFault_Active) >= 0.5;

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
% Resamples a logged timeseries onto t_grid. If the signal only has a
% single logged sample (true for anything fed by a pure Constant block,
% like G_test -- Simulink has no reason to log more than one point for a
% value that never changes), hold that value flat across the whole grid,
% which is the mathematically correct thing to do for a genuine constant,
% not just a workaround for interp1's two-point minimum.
if numel(sig.Time) < 2
    y = repmat(double(sig.Data(1)), numel(t_grid), 1);
else
    y = interp1(sig.Time, double(sig.Data), t_grid, 'linear', 'extrap');
end
end