// Mapeo determinístico de los 18 estados internos del work order a un
// viaje de servicio de 9 etapas, pensado para el customer. Esto NO es
// un segundo motor de estados — es una capa de PRESENTACIÓN sobre el
// current_status real que ya gobierna transition_work_order(). Nunca
// se usa para decidir qué transición es válida, solo para mostrarla.

export type CustomerStageStatus = 'completed' | 'current' | 'upcoming';

export interface CustomerStage {
  index: number; // 1-9
  label: string;
}

export const CUSTOMER_STAGES: CustomerStage[] = [
  { index: 1, label: 'Request Received' },
  { index: 2, label: 'Review & Diagnosis' },
  { index: 3, label: 'Scheduled' },
  { index: 4, label: 'Technician Assigned' },
  { index: 5, label: 'Technician En Route' },
  { index: 6, label: 'On Site' },
  { index: 7, label: 'Work In Progress' },
  { index: 8, label: 'Quality Check' },
  { index: 9, label: 'Completed' },
];

export interface StageMapping {
  stageIndex: number; // índice en CUSTOMER_STAGES, o -1 si cancelado
  subStatus: string; // explicación corta, orientada al customer
  isPaused: boolean; // esperando algo externo (parts, aprobación) — NO avanza la línea principal
  isCancelled: boolean;
}

// Tabla de lookup — cada uno de los 18 estados reales aparece
// exactamente una vez. Si algún día se agrega un estado nuevo al
// motor y no está acá, mapWorkOrderStatusToCustomerStage() lo
// detecta explícitamente en vez de fallar en silencio (ver abajo).
const STATUS_MAP: Record<string, StageMapping> = {
  request_received: { stageIndex: 1, subStatus: 'Your service request has been received.', isPaused: false, isCancelled: false },
  triage: { stageIndex: 2, subStatus: 'Your request is being reviewed by our team.', isPaused: false, isCancelled: false },
  estimate: { stageIndex: 2, subStatus: 'We are preparing an estimate for your service.', isPaused: false, isCancelled: false },
  awaiting_approval: { stageIndex: 2, subStatus: 'Waiting for your approval on the estimate.', isPaused: true, isCancelled: false },
  scheduled: { stageIndex: 3, subStatus: 'Your service has been scheduled.', isPaused: false, isCancelled: false },
  technician_assigned: {
    stageIndex: 4,
    subStatus: 'Your technician has been assigned and is preparing for the visit.',
    isPaused: false,
    isCancelled: false,
  },
  en_route: { stageIndex: 5, subStatus: 'Your technician is on the way to your vessel.', isPaused: false, isCancelled: false },
  checked_in: { stageIndex: 6, subStatus: 'Your technician has arrived and checked in.', isPaused: false, isCancelled: false },
  diagnosis: { stageIndex: 7, subStatus: 'Your technician is diagnosing the issue.', isPaused: false, isCancelled: false },
  work_in_progress: { stageIndex: 7, subStatus: 'Service is currently being performed on your vessel.', isPaused: false, isCancelled: false },
  waiting_parts: { stageIndex: 7, subStatus: 'Work is paused while we wait on a required part.', isPaused: true, isCancelled: false },
  waiting_customer_approval: {
    stageIndex: 7,
    subStatus: 'Waiting for your approval to continue the work.',
    isPaused: true,
    isCancelled: false,
  },
  quality_control: { stageIndex: 8, subStatus: 'Final quality review is underway.', isPaused: false, isCancelled: false },
  invoice: { stageIndex: 9, subStatus: 'Service completed — finalizing your invoice.', isPaused: false, isCancelled: false },
  payment: { stageIndex: 9, subStatus: 'Service completed — payment is being processed.', isPaused: false, isCancelled: false },
  completed: { stageIndex: 9, subStatus: 'Your service has been completed.', isPaused: false, isCancelled: false },
  warranty: { stageIndex: 9, subStatus: 'Your service is completed and under warranty.', isPaused: false, isCancelled: false },
  cancelled: { stageIndex: -1, subStatus: 'This service request has been cancelled.', isPaused: false, isCancelled: true },
};

export function mapWorkOrderStatusToCustomerStage(currentStatus: string): StageMapping {
  const mapping = STATUS_MAP[currentStatus];
  if (!mapping) {
    // Estado real que esta capa de presentación todavía no conoce —
    // se declara así explícitamente en vez de adivinar una etapa.
    return {
      stageIndex: 0,
      subStatus: `Status: ${currentStatus.replace(/_/g, ' ')}`,
      isPaused: false,
      isCancelled: false,
    };
  }
  return mapping;
}

// Deriva el estado (completed/current/upcoming) de cada una de las 9
// etapas para pintar el tracker — pura función del stageIndex actual,
// nunca vuelve a marcar como completa una etapa futura.
export function buildStageStatuses(currentStageIndex: number): (CustomerStage & { status: CustomerStageStatus })[] {
  return CUSTOMER_STAGES.map((stage) => ({
    ...stage,
    status: stage.index < currentStageIndex ? 'completed' : stage.index === currentStageIndex ? 'current' : 'upcoming',
  }));
}
