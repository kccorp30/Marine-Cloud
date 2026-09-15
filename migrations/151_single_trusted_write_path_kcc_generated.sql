-- =========================================================
-- 151_single_trusted_write_path_kcc_generated.sql — Phase 10 final closure
-- =========================================================
-- BUG REAL: guard_kcc_generated_field_before() dejaba pasar CUALQUIER
-- escritura de un actor de plataforma de confianza — incluido un
-- UPDATE/INSERT directo de kcc_admin que nunca pasa por
-- set_work_order_kcc_generated(), rompiendo el invariante
-- "kcc_generated=true siempre tiene atribución".
--
-- Fix: flag LOCAL de transacción (set_config is_local=true, nunca
-- persiste más allá de la transacción, solo set_work_order_kcc_
-- generated() lo activa) — el trigger SOLO deja pasar si ese flag
-- está activo. Ni siquiera kcc_admin puede saltearlo con un
-- UPDATE/INSERT crudo.
--
-- Verificado con datos reales: staff normal rechazado (regresión),
-- kcc_admin con UPDATE directo AHORA TAMBIÉN rechazado, kcc_admin con
-- INSERT directo true rechazado, sin acuerdo toda la operación via
-- RPC revierte (flag queda false), con acuerdo el RPC crea flag +
-- atribución juntos, reintento idempotente.
-- =========================================================

create or replace function guard_kcc_generated_field_before()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_via_trusted_rpc boolean;
begin
  v_via_trusted_rpc := coalesce(current_setting('app.kcc_generated_via_trusted_rpc', true), '') = 'true';

  if TG_OP = 'INSERT' then
    if NEW.kcc_generated and not v_via_trusted_rpc then
      raise exception 'kcc_generated can only be set to true via set_work_order_kcc_generated() — direct writes are never allowed, even for KCC admin';
    end if;
  elsif TG_OP = 'UPDATE' then
    if NEW.kcc_generated is distinct from OLD.kcc_generated and not v_via_trusted_rpc then
      raise exception 'kcc_generated can only be changed via set_work_order_kcc_generated() — direct writes are never allowed, even for KCC admin';
    end if;
  end if;
  return NEW;
end;
$$;

create or replace function set_work_order_kcc_generated(p_work_order_id uuid, p_kcc_generated boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can change kcc_generated';
  end if;

  perform set_config('app.kcc_generated_via_trusted_rpc', 'true', true);

  update work_orders set kcc_generated = p_kcc_generated, updated_at = now() where id = p_work_order_id;
  if not found then
    raise exception 'work order not found';
  end if;

  if p_kcc_generated then
    perform attribute_kcc_work(p_work_order_id);
  end if;

  perform set_config('app.kcc_generated_via_trusted_rpc', 'false', true);
end;
$$;
