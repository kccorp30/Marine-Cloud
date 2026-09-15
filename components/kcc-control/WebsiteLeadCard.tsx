'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import { manuallyRouteLeadAction, retryLeadConversionAction } from '@/lib/kcc-control/website-leads-actions';
import type { WebsiteLeadRow } from '@/lib/kcc-control/website-leads-data';

const STATUS_COLOR: Record<string, string> = {
  not_converted: 'text-cool-gray',
  needs_routing: 'text-red-400',
  in_progress: 'text-gold',
  converted: 'text-emerald-400',
  failed: 'text-red-400',
};

export function WebsiteLeadCard({ lead, organizations }: { lead: WebsiteLeadRow; organizations: { id: string; name: string }[] }) {
  const [pending, startTransition] = useTransition();
  const [routing, setRouting] = useState(false);
  const [selectedOrg, setSelectedOrg] = useState('');
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="bg-white/[0.03] border border-white/10 rounded-sm p-4 space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold">{lead.customerName ?? 'Unknown'}</span>
        <span className={`font-mono text-[9px] uppercase ${STATUS_COLOR[lead.conversionStatus ?? 'not_converted']}`}>
          {(lead.conversionStatus ?? 'not_converted').replace(/_/g, ' ')}
        </span>
      </div>
      <div className="text-xs text-cool-gray">
        {lead.phone && <>{lead.phone} · </>}
        {lead.email && <>{lead.email} · </>}
        {lead.city && <>{lead.city}, </>}
        {lead.region ?? lead.country}
      </div>
      {lead.serviceType && (
        <div className="text-xs">
          {lead.serviceType} — {lead.vesselMake} {lead.vesselModel}
        </div>
      )}
      {lead.mediaCount > 0 && <div className="text-[10px] text-cool-gray">{lead.mediaCount} media file(s)</div>}
      {(lead.utmSource || lead.utmCampaign) && (
        <div className="text-[10px] text-cool-gray">
          {lead.utmSource && <>src: {lead.utmSource} </>}
          {lead.utmCampaign && <>· campaign: {lead.utmCampaign}</>}
        </div>
      )}

      {lead.assignedOrganizationName ? (
        <div className="text-xs">
          Routed to: <span className="text-gold">{lead.assignedOrganizationName}</span>
        </div>
      ) : lead.conversionStatus === 'needs_routing' ? (
        <div className="text-xs text-red-400">Not routed — needs manual assignment</div>
      ) : null}

      {lead.conversionError && <p className="text-xs text-red-400">{lead.conversionError}</p>}
      {lead.attemptCount > 0 && <p className="text-[10px] text-cool-gray">Attempts: {lead.attemptCount}</p>}

      {lead.marineCloudServiceRequestId && (
        <Link href={`/service-requests`} className="text-[10px] font-mono uppercase text-gold">
          View resulting service request →
        </Link>
      )}

      {error && <p className="text-xs text-red-400">{error}</p>}

      <div className="flex gap-2 pt-1">
        {lead.conversionStatus === 'needs_routing' && !routing && (
          <button type="button" onClick={() => setRouting(true)} className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
            Route Manually
          </button>
        )}
        {lead.conversionStatus === 'failed' && (
          <button
            type="button"
            disabled={pending}
            onClick={() => {
              setError(null);
              startTransition(async () => {
                const res = await retryLeadConversionAction(lead.id);
                if (res?.error) setError(res.error);
              });
            }}
            className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm"
          >
            {pending ? 'Retrying…' : 'Retry Conversion'}
          </button>
        )}
      </div>

      {routing && (
        <div className="flex gap-2 pt-1">
          <select value={selectedOrg} onChange={(e) => setSelectedOrg(e.target.value)} className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5">
            <option value="" className="bg-navy">
              Select company…
            </option>
            {organizations.map((o) => (
              <option key={o.id} value={o.id} className="bg-navy">
                {o.name}
              </option>
            ))}
          </select>
          <button
            type="button"
            disabled={pending || !selectedOrg}
            onClick={() => {
              setError(null);
              const formData = new FormData();
              formData.set('leadId', lead.id);
              formData.set('organizationId', selectedOrg);
              startTransition(async () => {
                const res = await manuallyRouteLeadAction(formData);
                if (res?.error) {
                  setError(res.error);
                  return;
                }
                setRouting(false);
              });
            }}
            className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm"
          >
            Assign
          </button>
          <button type="button" onClick={() => setRouting(false)} className="text-[10px] font-mono uppercase text-cool-gray px-3 py-1.5">
            Cancel
          </button>
        </div>
      )}
    </div>
  );
}
