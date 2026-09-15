'use client';

import {ActionForm} from '@/components/ui/ActionForm';
import { changeMemberRole } from '@/lib/team/actions';

const ROLE_LABEL: Record<string, string> = {
  company_admin: 'Admin',
  manager: 'Manager',
  technician: 'Technician',
};

export function RoleSelect({ membershipId, currentRole, options }: { membershipId: string; currentRole: string; options: string[] }) {
  return (
    <ActionForm action={changeMemberRole}>
      <input type="hidden" name="membershipId" value={membershipId} />
      <select
        name="newRole"
        defaultValue={currentRole}
        className="text-[11px] bg-white/[0.04] border border-white/10 px-2 py-1 rounded-sm"
        onChange={(e) => e.currentTarget.form?.requestSubmit()}
      >
        {options.map((r) => (
          <option key={r} value={r} className="bg-navy">
            {ROLE_LABEL[r] ?? r}
          </option>
        ))}
      </select>
    </ActionForm>
  );
}
