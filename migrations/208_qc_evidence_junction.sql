-- =========================================================
-- 208_qc_evidence_junction.sql — Phase 13 final integrity
-- =========================================================
-- GAP REAL: qc_submission_items.media_asset_id era una FK única y
-- frágil, nunca usada desde la UI real. Reemplazada por qc_evidence —
-- tabla de unión, permite varios archivos por item, reusa
-- media_assets existente. attach_qc_evidence() valida server-side que
-- el media pertenece al MISMO work_order/organización — nunca confía
-- en un media_asset_id de otro trabajo/tenant.
-- Verificado con datos reales: media del mismo WO aceptada, de otro
-- WO rechazada, customer no ve evidencia interna, se preserva tras
-- pasar QC, staff autorizado sí la ve.
-- =========================================================

create table qc_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  qc_submission_item_id uuid not null references qc_submission_items(id),
  media_asset_id uuid not null references media_assets(id),
  added_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  unique (qc_submission_item_id, media_asset_id)
);

create index idx_qc_evidence_item on qc_evidence(qc_submission_item_id);

alter table qc_evidence enable row level security;

create policy "qc_evidence_read" on qc_evidence for select
using (
  exists (
    select 1 from qc_submission_items qsi
    join qc_submissions qs on qs.id = qsi.qc_submission_id
    where qsi.id = qc_evidence.qc_submission_item_id
      and (is_kcc_admin() or is_org_staff(qs.organization_id) or is_assigned_to_work_order(qs.work_order_id))
  )
);

revoke all on qc_evidence from anon;
grant select on qc_evidence to authenticated;

create or replace function attach_qc_evidence(p_item_id uuid, p_media_asset_id uuid)
returns qc_evidence
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item qc_submission_items%rowtype;
  v_submission qc_submissions%rowtype;
  v_media media_assets%rowtype;
  v_evidence qc_evidence%rowtype;
begin
  select * into v_item from qc_submission_items where id = p_item_id;
  if v_item.id is null then
    raise exception 'QC item not found';
  end if;
  select * into v_submission from qc_submissions where id = v_item.qc_submission_id;
  if v_submission.status != 'draft' then
    raise exception 'QC submission is no longer editable (status: %)', v_submission.status;
  end if;
  if not (is_org_staff(v_submission.organization_id) or is_assigned_to_work_order(v_submission.work_order_id)) then
    raise exception 'not authorized to attach evidence to this QC item';
  end if;

  select * into v_media from media_assets where id = p_media_asset_id;
  if v_media.id is null then
    raise exception 'media asset not found';
  end if;
  if v_media.organization_id != v_submission.organization_id or v_media.work_order_id != v_submission.work_order_id then
    raise exception 'media asset does not belong to this work order';
  end if;

  insert into qc_evidence (organization_id, qc_submission_item_id, media_asset_id, added_by)
  values (v_submission.organization_id, p_item_id, p_media_asset_id, auth.uid())
  on conflict (qc_submission_item_id, media_asset_id) do nothing
  returning * into v_evidence;

  if v_evidence.id is null then
    select * into v_evidence from qc_evidence where qc_submission_item_id = p_item_id and media_asset_id = p_media_asset_id;
  end if;

  return v_evidence;
end;
$$;

revoke execute on function attach_qc_evidence(uuid, uuid) from public, anon;
grant execute on function attach_qc_evidence(uuid, uuid) to authenticated;
