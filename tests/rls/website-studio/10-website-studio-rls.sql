\set QUIET on
create temp table r(test text, result text);
grant all on r to anon, authenticated;

-- 1. Visitante anónimo: todo es borrador → no ve servicios ni landings; sí ve ajustes
set role anon;
insert into r select 'anon_sees_no_draft_services', case when (select count(*) from site_services)=0 then 'PASS' else 'FAIL' end;
insert into r select 'anon_sees_no_draft_landings', case when (select count(*) from site_landing_pages)=0 then 'PASS' else 'FAIL' end;
insert into r select 'anon_reads_settings', case when (select count(*) from site_settings)=1 then 'PASS' else 'FAIL' end;
reset role;

-- 2. Anónimo no puede escribir
set role anon;
do $$ begin
  begin insert into site_services(slug,title) values ('hack','{"en":"x"}'); insert into r values ('anon_cannot_insert','FAIL');
  exception when others then insert into r values ('anon_cannot_insert','PASS'); end;
end $$;
reset role;

-- 3. Usuario autenticado NO admin (dueño de compañía): no ve borradores, no escribe, no publica
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000b1"}';
insert into r select 'company_owner_sees_no_drafts', case when (select count(*) from site_services)=0 then 'PASS' else 'FAIL' end;
do $$ begin
  begin insert into site_services(slug,title) values ('hack2','{"en":"x"}'); insert into r values ('company_owner_cannot_insert','FAIL');
  exception when others then insert into r values ('company_owner_cannot_insert','PASS'); end;
end $$;
update site_services set published = true where slug='marine-electrical';
reset role; reset request.jwt.claims;
insert into r select 'company_owner_cannot_publish', case when (select published from site_services where slug='marine-electrical')=false then 'PASS' else 'FAIL' end;
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000b1"}';
update site_settings set company_name='HACKED';
reset role; reset request.jwt.claims;
insert into r select 'company_owner_cannot_edit_settings', case when (select company_name from site_settings)<>'HACKED' then 'PASS' else 'FAIL' end;

-- 4. KCC Admin: ve borradores, publica, edita
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000a1"}';
insert into r select 'admin_sees_drafts', case when (select count(*) from site_services)=5 then 'PASS' else 'FAIL' end;
update site_services set published = true where slug in ('marine-electrical','preventive-maintenance');
update site_landing_pages set published = true where path='offers/marine-electrical';
update site_settings set phone = '+1 305 000 0000';
insert into r select 'admin_settings_update', case when (select phone from site_settings)='+1 305 000 0000' then 'PASS' else 'FAIL' end;
-- testimonio sin permiso NO se puede publicar
insert into site_testimonials(author_name, quote) values ('Test Owner','{"en":"Great work"}');
do $$ begin
  begin update site_testimonials set published = true where author_name='Test Owner'; insert into r values ('testimonial_needs_consent','FAIL');
  exception when check_violation then insert into r values ('testimonial_needs_consent','PASS'); end;
end $$;
update site_testimonials set consent_confirmed = true, published = true where author_name='Test Owner';
insert into r select 'testimonial_publishes_with_consent', case when (select published from site_testimonials where author_name='Test Owner') then 'PASS' else 'FAIL' end;
-- slug duplicado rechazado
do $$ begin
  begin insert into site_services(slug,title) values ('marine-electrical','{"en":"dup"}'); insert into r values ('duplicate_slug_rejected','FAIL');
  exception when unique_violation then insert into r values ('duplicate_slug_rejected','PASS'); end;
end $$;
-- ruta de landing inválida rechazada
do $$ begin
  begin insert into site_landing_pages(path,internal_name,headline) values ('Bad Path!','x','{"en":"h"}'); insert into r values ('bad_landing_path_rejected','FAIL');
  exception when check_violation then insert into r values ('bad_landing_path_rejected','PASS'); end;
end $$;
reset role; reset request.jwt.claims;

-- 5. Anónimo ahora ve SOLO lo publicado
set role anon;
insert into r select 'anon_sees_only_published_services', case when (select count(*) from site_services)=2 then 'PASS' else 'FAIL' end;
insert into r select 'anon_sees_published_landing', case when (select count(*) from site_landing_pages where path='offers/marine-electrical')=1 and (select count(*) from site_landing_pages)=1 then 'PASS' else 'FAIL' end;
insert into r select 'anon_sees_consented_testimonial', case when (select count(*) from site_testimonials)=1 then 'PASS' else 'FAIL' end;
-- landing apunta a un servicio que sigue publicado; el de mantenimiento-landing sigue en borrador
reset role;

-- 6. Storage: solo admin sube a site-media; bucket público
insert into r select 'site_media_bucket_public', case when (select public from storage.buckets where id='site-media') then 'PASS' else 'FAIL' end;
grant insert on storage.objects to authenticated;
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000b1"}';
do $$ begin
  begin insert into storage.objects(bucket_id,name) values ('site-media','services/x.jpg'); insert into r values ('non_admin_cannot_upload','FAIL');
  exception when others then insert into r values ('non_admin_cannot_upload','PASS'); end;
end $$;
set request.jwt.claims = '{"sub":"00000000-0000-4000-8000-0000000000a1"}';
do $$ begin
  begin insert into storage.objects(bucket_id,name) values ('site-media','services/x.jpg'); insert into r values ('admin_can_upload','PASS');
  exception when others then insert into r values ('admin_can_upload','FAIL'); end;
end $$;
do $$ begin
  begin insert into storage.objects(bucket_id,name) values ('vessel-media','x.jpg'); insert into r values ('admin_policy_scoped_to_site_media','FAIL');
  exception when others then insert into r values ('admin_policy_scoped_to_site_media','PASS'); end;
end $$;
reset role; reset request.jwt.claims;

\set QUIET off
select test, result from r order by result desc, test;
select count(*) filter (where result='PASS') as pass, count(*) filter (where result='FAIL') as fail from r;
