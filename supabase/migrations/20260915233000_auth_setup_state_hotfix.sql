begin;

-- V9.1 hotfix: credential setup is explicit Auth metadata for new invites.
-- Existing/legacy users must not be classified as first-time accounts merely
-- because password_set_at was introduced after their account already existed.
--
-- Keep password_set_at as an optional durable marker. We intentionally do not
-- backfill or use it as a global route gate.
comment on column profiles.password_set_at is
  'Best-effort timestamp indicating Marine Cloud observed a successful password setup/sign-in. Never infer first-time onboarding solely from NULL.';

commit;
