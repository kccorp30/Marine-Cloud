'use client';

import { useState, useTransition } from 'react';
import { changeMemberRoleAction } from '@/lib/kcc-control/actions';

const ROLES = ['company_owner', 'company_admin', 'manager', 'technician', 'customer'];

export function MemberRoleSelect({ membershipId, organizationId, currentRole }: { membershipId: string; organizationId: string; currentRole: string }) {
  const [pending, startTransition] = useTransition();
  const [role, setRole] = useState(currentRole);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="flex items-center gap-2">
      <select
        value={role}
        disabled={pending}
        onChange={(e) => {
          const newRole = e.target.value;
          setRole(newRole);
          setError(null);
          const formData = new FormData();
          formData.set('membershipId', membershipId);
          formData.set('organizationId', organizationId);
          formData.set('newRole', newRole);
          startTransition(async () => {
            const res = await changeMemberRoleAction(formData);
            if (res?.error) {
              setError(res.error);
              setRole(currentRole);
            }
          });
        }}
        className="font-mono text-[9px] uppercase bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1"
      >
        {ROLES.map((r) => (
          <option key={r} value={r} className="bg-navy">
            {r}
          </option>
        ))}
      </select>
      {error && <span className="text-[9px] text-red-400">{error}</span>}
    </div>
  );
}
