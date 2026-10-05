function stage9_closure_passB_diagnostic2()
% stage9_closure_passB_diagnostic2  Decisive, compile-free check for why
% k_Rs=0 has no effect on Rs_aged while k_R0=0 correctly freezes R0_aged.
%
% No sim(), no compile, no RuntimeObject. This just asks Simulink what is
% literally typed into the 'Value' field of every Constant block inside
% PV_Degradation_Model and the Battery aging subsystem. If a Constant's
% Value field contains the TEXT "k_Rs" (a workspace variable reference),
% assignin('base','k_Rs',...) should reach it. If it contains a literal
% number instead, it never will, however many times we override the
% workspace -- and that is the whole mystery explained in one line of
% output.

mdl = 'Reformable_AI_2025';
load_system(mdl);  % make sure it's actually loaded before we query it

fprintf('=== Constant blocks inside PV_Degradation_Model ===\n');
pvConsts = find_system([mdl '/PV_Degradation_Model'], 'BlockType', 'Constant');
for i = 1:numel(pvConsts)
    bp = pvConsts{i};
    val = get_param(bp, 'Value');
    fprintf('%-70s  Value = %s\n', bp, val);
end

fprintf('\n=== Constant blocks inside Battery_Degradation_Model (or wherever R0 aging lives) ===\n');
% Try the obvious name first; if it doesn't exist, search the whole model
% for any subsystem with "Battery" and "Degrad" in the name so we don't
% guess wrong the way we did with Battery_Fault_Model earlier.
battDegPath = [mdl '/Battery_Degradation_Model'];
if isempty(find_system(mdl, 'Name', 'Battery_Degradation_Model'))
    cand = find_system(mdl, 'BlockType', 'SubSystem');
    hit = cand(contains(cand, 'Battery') & (contains(cand,'Degrad') | contains(cand,'Aging')));
    if ~isempty(hit)
        battDegPath = hit{1};
    end
    fprintf('(Battery_Degradation_Model not found by exact name -- using: %s)\n', battDegPath);
end
battConsts = find_system(battDegPath, 'BlockType', 'Constant');
for i = 1:numel(battConsts)
    bp = battConsts{i};
    val = get_param(bp, 'Value');
    fprintf('%-70s  Value = %s\n', bp, val);
end

fprintf('\n=== Interpretation ===\n');
fprintf('For each row above: if Value is a WORD like "k_Rs" or "k_R0", that\n');
fprintf('block reads the base workspace variable of that name -- assignin\n');
fprintf('should reach it. If Value is a NUMBER (e.g. "0.5"), the block has\n');
fprintf('a value typed in directly and will NEVER respond to assignin,\n');
fprintf('regardless of what the workspace holds at sim time.\n');

end