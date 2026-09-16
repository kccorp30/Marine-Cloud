-- V9.4 hotfix: estimate/customer portal invitations must allow intended_role='customer'.
-- Safe to run even when the earlier V9 credentials migration was missed.

do $$
begin
  if to_regclass('public.organization_invitations') is not null then
    alter table public.organization_invitations
      drop constraint if exists organization_invitations_intended_role_check;

    alter table public.organization_invitations
      add constraint organization_invitations_intended_role_check
      check (intended_role in ('company_owner', 'company_admin', 'manager', 'technician', 'customer'));
  end if;
end $$;
