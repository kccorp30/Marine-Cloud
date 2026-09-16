'use client';

import { useState } from 'react';

export function CompanyDetailTabs({ tabs }: { tabs: { id: string; label: string; badge?: number; content: React.ReactNode }[] }) {
  const [active, setActive] = useState(tabs[0]?.id);

  return (
    <div>
      <div className="flex gap-1 overflow-x-auto border-b border-white/[0.06] mb-6 -mx-1 px-1">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            type="button"
            onClick={() => setActive(tab.id)}
            className={`relative shrink-0 px-4 py-3 text-xs font-mono uppercase tracking-[0.06em] transition-colors duration-150 ${
              active === tab.id ? 'text-gold' : 'text-cool-gray hover:text-marine-white'
            }`}
          >
            {tab.label}
            {tab.badge !== undefined && tab.badge > 0 && (
              <span className="ml-1.5 text-[9px] bg-gold/15 text-gold px-1.5 py-0.5 rounded-full">{tab.badge}</span>
            )}
            {active === tab.id && <span className="absolute bottom-0 left-0 right-0 h-[2px] bg-gold-sheen shadow-glow-gold" />}
          </button>
        ))}
      </div>

      <div className="animate-fade-up">{tabs.find((t) => t.id === active)?.content}</div>
    </div>
  );
}
