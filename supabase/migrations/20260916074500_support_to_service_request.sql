create or replace function public.convert_conversation_to_service_request(
  p_conversation_id uuid,
  p_description text default null
) returns uuid
language plpgsql security definer set search_path='' as $$
declare c public.conversations%rowtype; v_request uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into c from public.conversations where id=p_conversation_id for update;
  if c.id is null then raise exception 'Conversation not found'; end if;
  if not (public.is_kcc_admin() or public.is_org_staff(c.organization_id)) then raise exception 'Not authorized'; end if;
  if c.service_request_id is not null then return c.service_request_id; end if;
  if c.vessel_id is null then raise exception 'Choose a vessel before creating a service request'; end if;

  insert into public.service_requests(
    organization_id,customer_id,vessel_id,title,description,urgency,status,source,
    client_generated_id,created_by
  ) values(
    c.organization_id,c.customer_id,c.vessel_id,coalesce(nullif(trim(c.subject),''),'Customer support request'),
    nullif(trim(p_description),''),'normal','submitted','portal_support',gen_random_uuid(),auth.uid()
  ) returning id into v_request;

  update public.conversations set service_request_id=v_request,updated_at=now() where id=c.id;
  perform public.log_audit_event_internal(c.organization_id,'service_request',v_request,'created_from_conversation',null,jsonb_build_object('conversation_id',c.id),auth.uid());
  return v_request;
end;$$;
revoke all on function public.convert_conversation_to_service_request(uuid,text) from public,anon;
grant execute on function public.convert_conversation_to_service_request(uuid,text) to authenticated;
