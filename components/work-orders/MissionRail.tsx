const STEPS = [
  ['request_received','Request'],
  ['triage','Triage'],
  ['estimate','Estimate'],
  ['awaiting_approval','Approval'],
  ['scheduled','Scheduled'],
  ['technician_assigned','Assigned'],
  ['en_route','En route'],
  ['checked_in','On board'],
  ['diagnosis','Diagnostic'],
  ['work_in_progress','Work'],
  ['waiting_parts','Parts'],
  ['quality_control','QC'],
  ['invoice','Invoice'],
  ['payment','Payment'],
  ['completed','Completed'],
] as const;

export function MissionRail({status}:{status:string}) {
  const found = STEPS.findIndex(([key])=>key===status);
  const current = found >= 0 ? found : 0;
  return <div className="mission-rail" aria-label="Work order progress">
    {STEPS.map(([key,label],i)=>{
      const done=i<current; const active=i===current;
      return <div className={`mission-step ${done?'is-done':''} ${active?'is-active':''}`} key={key}>
        <span className="mission-node">{done?'✓':i+1}</span>
        <span>{label}</span>
      </div>
    })}
  </div>
}
