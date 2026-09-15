import { z } from 'zod';

// Mismo principio que lib/shared/schemas.ts del sitio web (kccorp-web):
// nombres canónicos, mantenidos en sync manualmente hasta que ambos
// proyectos se extraigan a un monorepo (ver docs/monorepo-plan.md del
// sitio) — no reinventar nombres nuevos para los mismos conceptos.

export const MembershipRoleSchema = z.enum(['kcc_admin', 'company_owner', 'company_admin', 'manager', 'technician', 'customer']);
export type MembershipRole = z.infer<typeof MembershipRoleSchema>;

export const OrganizationSchema = z.object({
  id: z.string().uuid(),
  name: z.string().min(1),
  legalName: z.string().nullable(),
  slug: z.string().min(1),
  brandingJson: z.record(z.unknown()),
  status: z.enum(['active', 'suspended', 'archived']),
});
export type Organization = z.infer<typeof OrganizationSchema>;

export const ProfileSchema = z.object({
  id: z.string().uuid(),
  fullName: z.string().nullable(),
  phone: z.string().nullable(),
  email: z.string().email().nullable(),
});
export type Profile = z.infer<typeof ProfileSchema>;

export const MembershipSchema = z.object({
  profileId: z.string().uuid(),
  organizationId: z.string().uuid(),
  role: MembershipRoleSchema,
  status: z.enum(['active', 'invited', 'suspended']),
});
export type MembershipInput = z.infer<typeof MembershipSchema>;

// Reusa exactamente los mismos contratos del sitio web para el punto
// de integración futuro (Phase 10) — CustomerInput/VesselInput deben
// ser IDÉNTICOS a los del sitio, copiados aquí a propósito (no
// importados directo, por la misma razón documentada en
// docs/monorepo-plan.md del sitio: sin monorepo todavía, se
// mantienen en sync manualmente).
export const CustomerInputSchema = z.object({
  name: z.string().min(1).max(120),
  phone: z.string().min(5).max(30),
  email: z.string().email().optional().or(z.literal('')),
  preferredContactMethod: z.enum(['phone', 'email', 'whatsapp']).default('phone'),
});
export type CustomerInput = z.infer<typeof CustomerInputSchema>;

export const VesselInputSchema = z.object({
  make: z.string().min(1).max(80),
  model: z.string().min(1).max(80),
  year: z.coerce.number().int().min(1900).max(2100).optional(),
  name: z.string().max(80).optional(),
  hin: z.string().max(40).optional(),
});
export type VesselInput = z.infer<typeof VesselInputSchema>;
