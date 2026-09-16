import { ActionForm } from '@/components/ui/ActionForm';
import { inputClass } from '@/components/ui/primitives';
import { dispatchWorkOrderAction } from '@/lib/work-orders/actions';
import { MissionRail } from './MissionRail';

type Tech={profile_id:string; profile?:{full_name?:string|null;avatar_url?:string|null}|null};
type Assignment={technician_profile_id:string;technician?:{full_name?:string|null;avatar_url?:string|null;phone?:string|null}|null};
type Appointment={id:string;scheduled_start:string;status:string;purpose?:string|null};

function localInput(iso?:string|null){
  const d=iso?new Date(iso):new Date(Date.now()+60*60*1000);
  const local=new Date(d.getTime()-d.getTimezoneOffset()*60000);
  return local.toISOString().slice(0,16);
}

export function DispatchMissionCard({workOrderId,status,technicians,assignment,appointment,locale='en'}:{
  workOrderId:string;status:string;technicians:Tech[];assignment?:Assignment|null;appointment?:Appointment|null;locale?:string;
}){
  const es=locale==='es';
  const canDispatch=['scheduled','technician_assigned'].includes(status);
  const missionStarted=['technician_assigned','en_route','checked_in','diagnosis','work_in_progress','waiting_parts','waiting_customer_approval','quality_control','invoice','payment','completed','warranty'].includes(status);
  return <section className="dispatch-mission-card">
    <div className="dispatch-glow" />
    <div className="relative">
      <div className="flex flex-col md:flex-row md:items-start justify-between gap-4">
        <div>
          <p className="command-kicker">✦ LUZ · {es?'DESPACHO GUIADO':'GUIDED DISPATCH'}</p>
          <h2 className="text-2xl font-semibold mt-1">{es?'Misión de servicio':'Service mission'}</h2>
          <p className="text-sm text-cool-gray mt-2 max-w-2xl">{es?'Programa, asigna y entrega el trabajo al técnico desde un solo lugar. Luz mantendrá el siguiente paso visible.':'Schedule, assign and hand the job to a technician from one place. Luz keeps the next action visible.'}</p>
        </div>
        {assignment?.technician && <div className="assigned-tech-pill">
          <span className="assigned-tech-avatar">{assignment.technician.avatar_url?<img src={assignment.technician.avatar_url} alt=""/>:(assignment.technician.full_name?.[0]||'T')}</span>
          <span><small>{es?'Técnico asignado':'Assigned technician'}</small><b>{assignment.technician.full_name||'Technician'}</b></span>
        </div>}
      </div>
      <MissionRail status={status}/>
      {canDispatch ? <ActionForm action={dispatchWorkOrderAction} className="dispatch-form">
        <input type="hidden" name="workOrderId" value={workOrderId}/>
        <label><span>{es?'TÉCNICO':'TECHNICIAN'}</span><select name="technicianProfileId" required defaultValue={assignment?.technician_profile_id||''} className={inputClass}>
          <option value="">{es?'Seleccionar técnico…':'Select technician…'}</option>
          {technicians.map(t=><option key={t.profile_id} value={t.profile_id} className="bg-navy">{t.profile?.full_name||t.profile_id}</option>)}
        </select></label>
        <label><span>{es?'FECHA Y HORA':'DATE & TIME'}</span><input className={inputClass} name="scheduledStart" type="datetime-local" defaultValue={localInput(appointment?.scheduled_start)} required/></label>
        <label className="md:col-span-2"><span>{es?'INSTRUCCIONES DE MISIÓN':'MISSION BRIEF'}</span><input className={inputClass} name="purpose" defaultValue={appointment?.purpose||''} placeholder={es?'Ej. revisar sistema eléctrico de estribor…':'e.g. inspect starboard electrical system…'}/></label>
        <button className="command-button md:col-span-2 justify-center" type="submit">{assignment? (es?'ACTUALIZAR DESPACHO':'UPDATE DISPATCH'):(es?'ASIGNAR Y PROGRAMAR':'ASSIGN & SCHEDULE')} →</button>
      </ActionForm> : missionStarted ? <div className="dispatch-live-state"><span className="live-dot"/><div><b>{es?'Misión activa':'Mission active'}</b><p>{es?'El técnico ya tiene este trabajo en su panel. Los siguientes cambios se registran en tiempo real.':'The technician now has this job in their workspace. Next status changes are tracked live.'}</p></div></div> : <div className="dispatch-live-state is-waiting"><span className="waiting-dot"/><div><b>{es?'Aún no está listo para despacho':'Not ready for dispatch yet'}</b><p>{es?'Completa el flujo comercial hasta Scheduled. Si viene de un estimado aprobado, usa “Activar trabajo” desde el estimado.':'Complete the commercial workflow through Scheduled. If this came from an approved estimate, use “Activate job” from the estimate.'}</p></div></div>}
    </div>
  </section>
}
