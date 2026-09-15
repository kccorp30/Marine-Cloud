"use client";
import { InstallApp } from "@/components/ui/InstallApp";

import { useCommandCopy } from "@/components/ui/LocaleProvider";
import Link from "next/link";
import { BILLING_PAUSED } from "@/lib/launch/config";
import { useEffect, useRef } from "react";
import { usePathname } from "next/navigation";
import { KccLogo } from "@/components/ui/KccLogo";

export const NAV_BY_ROLE: Record<
  string,
  { href: string; label: string; icon: string; group?: string }[]
> = {
  kcc_admin: [
    { href: "/dashboard", label: "Dashboard", icon: "⌂", group: "CONTROL" },
    { href: "/companies", label: "Companies", icon: "◫" },
    { href: "/work-orders", label: "Work Orders", icon: "▤" },
    { href: "/customers", label: "Customers", icon: "◎" },
    { href: "/vessels", label: "Vessels", icon: "⌁" },
    { href: "/kcc-assistance", label: "Assistance", icon: "◇" },
    { href: "/communications", label: "Luz AI", icon: "✦" },
    { href: "/website-leads", label: "Website Leads", icon: "✉" },
    { href: "/warranty", label: "Warranty", icon: "♢", group: "COMMERCIAL" },
    { href: "/commercial-dashboard", label: "Commercial", icon: "▥" },
    { href: "/subscription-plans", label: "Subscription Plans", icon: "≡" },
    { href: "/service-requests", label: "Service Requests", icon: "⊙" },
  ],
  company_owner: [
    { href: "/company", label: "Dashboard", icon: "⌂", group: "OPERATIONS" },
    { href: "/work-orders", label: "Work Orders", icon: "▤" },
    { href: "/vessels", label: "Vessels", icon: "⌁" },
    { href: "/team", label: "Technicians", icon: "♙" },
    { href: "/customers", label: "Customers", icon: "◎" },
    { href: "/schedule", label: "Schedule", icon: "◷" },
    { href: "/service-requests", label: "Service Requests", icon: "⊙" },
    { href: "/estimates", label: "Estimates", icon: "▥", group: "BUSINESS" },
    { href: "/invoices", label: "Invoices", icon: "▧" },
    { href: "/communications", label: "Luz / Communications", icon: "✦" },
    { href: "/services", label: "Services", icon: "⚙" },
    { href: "/billing", label: "Billing", icon: "$" },
    {
      href: "/company-settings",
      label: "Settings",
      icon: "⚙",
      group: "SYSTEM",
    },
  ],
  company_admin: [],
  manager: [],
  technician: [
    { href: "/today", label: "Dashboard", icon: "⌂", group: "FIELD" },
    { href: "/work-orders", label: "My Jobs", icon: "▤" },
    { href: "/kcc-assistance", label: "Luz / Technical Support", icon: "✦" },
  ],
  customer: [
    { href: "/customer", label: "Dashboard", icon: "⌂", group: "MY KCC" },
    { href: "/vessels", label: "My Vessels", icon: "⌁" },
    { href: "/work-orders", label: "My Services", icon: "⚙" },
    { href: "/invoices", label: "Invoices & Payments", icon: "▧" },
    { href: "/estimates", label: "Estimates", icon: "▥" },
    { href: "/warranty", label: "Warranty", icon: "♢" },
    { href: "/messages", label: "Luz / Support Chat", icon: "✦" },
    {
      href: "/request-service",
      label: "Request Service",
      icon: "+",
      group: "SERVICE",
    },
  ],
};
NAV_BY_ROLE.company_admin = NAV_BY_ROLE.company_owner;
NAV_BY_ROLE.manager = NAV_BY_ROLE.company_owner.filter(
  (x) => x.href !== "/billing",
);

export function Sidebar({
  companyLogo,
  role,
  isKccAdmin,
  orgName,
  fullName,
  mobileOpen,
  onClose,
}: {
  companyLogo?: string | null;
  role: string;
  isKccAdmin: boolean;
  orgName: string | null;
  fullName: string | null;
  mobileOpen: boolean;
  onClose: () => void;
}) {
  const asideRef = useRef<HTMLElement>(null);
  useEffect(() => {
    if (!mobileOpen) return;
    const previous = document.activeElement as HTMLElement;
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const aside = asideRef.current;
    const first = aside?.querySelector<HTMLElement>("a,button");
    first?.focus();
    function handle(event: KeyboardEvent) {
      if (event.key === "Escape") {
        onClose();
        return;
      }
      if (event.key !== "Tab" || !aside) return;
      const nodes = Array.from(aside.querySelectorAll<HTMLElement>("a,button"));
      const last = nodes[nodes.length - 1];
      if (event.shiftKey && document.activeElement === nodes[0]) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        nodes[0]?.focus();
      }
    }
    document.addEventListener("keydown", handle);
    return () => {
      document.body.style.overflow = oldOverflow;
      document.removeEventListener("keydown", handle);
      previous?.focus();
    };
  }, [mobileOpen, onClose]);
  const { t } = useCommandCopy();
  const navLabels: Record<string, string> = {
    "/dashboard": t.overview,
    "/companies": t.network,
    "/company": t.overview,
    "/today": t.today,
    "/customer": t.overview,
    "/work-orders": t.workOrders,
    "/vessels": t.vessels,
    "/customers": t.customers,
    "/team": t.team,
    "/schedule": t.schedule,
    "/invoices": t.invoices,
    "/estimates": t.estimated,
    "/warranty": t.warranty,
    "/company-settings": t.settings,
    "/kcc-assistance": t.assistance,
    "/website-leads": t.leads,
    "/service-requests": t.requests,
    "/request-service": t.requests,
    "/messages": t.messages,
    "/commercial-dashboard": t.commercial,
    "/finances":t.finance,
  };
  const pathname = usePathname();
  const navItems = (NAV_BY_ROLE[isKccAdmin ? "kcc_admin" : role] ?? []).filter(
    (item) =>
      !BILLING_PAUSED ||
      item.href !== "/subscription-plans",
  );
  if (isKccAdmin || ['company_owner','company_admin'].includes(role)) navItems.push({href:'/luz',label:'Luz',icon:'✦'},{href:'/finances',label:'Finances',icon:'$'});
  let lastGroup = "";

  return (
    <>
      {mobileOpen && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm z-40 lg:hidden"
          onClick={onClose}
        />
      )}
      <aside
        ref={asideRef}
        aria-label={t.navigation}
        className={`fixed lg:sticky top-0 h-screen w-[270px] shrink-0 z-50 lg:z-10 flex flex-col bg-[#061321]/95 border-r border-gold-dim/20 shadow-[18px_0_70px_-45px_rgba(0,0,0,.95)] transition-transform duration-300 marine-waves ${mobileOpen ? "translate-x-0" : "-translate-x-full lg:translate-x-0"}`}
      >
        <div className="px-5 pt-5 pb-4">
          <Link
            href={
              isKccAdmin
                ? "/dashboard"
                : role === "technician"
                  ? "/today"
                  : role === "customer"
                    ? "/customer"
                    : "/company"
            }
            className="flex justify-center"
          >
            <KccLogo
              size="md"
              className="w-[152px] h-[92px] drop-shadow-[0_8px_30px_rgba(201,162,75,.14)]"
            />
          </Link>
          <div className="gold-line mt-1" />
        </div>

        <div className="px-4 pb-3">
          <div className="rounded-xl border border-gold-dim/25 bg-gradient-to-br from-white/[.055] to-white/[.018] p-3.5 shadow-premium">
            <>
              {!isKccAdmin && companyLogo && (
                <img
                  src={companyLogo}
                  alt=""
                  className="h-12 max-w-full object-contain mb-3"
                />
              )}
            </>
            <div className="text-sm font-semibold truncate">
              {isKccAdmin
                ? "KCC Control Center"
                : (orgName ?? "KCC Marine Cloud")}
            </div>
            <div className="flex items-center gap-2 mt-1.5 text-[10px] text-cool-gray">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 status-dot" />
              <span className="truncate">
                {fullName || role.replace(/_/g, " ")}
              </span>
            </div>
          </div>
        </div>

        <nav className="flex-1 overflow-y-auto scrollbar-none px-3.5 py-1">
          {navItems.map((item) => {
            const active =
              pathname === item.href || pathname.startsWith(item.href + "/");
            const groupHeader =
              item.group && item.group !== lastGroup ? item.group : null;
            if (item.group) lastGroup = item.group;
            return (
              <div key={item.href}>
                {groupHeader && (
                  <div className="eyebrow px-3 pt-4 pb-2 opacity-70">
                    {t.navigation}
                  </div>
                )}
                <Link
                  href={item.href}
                  onClick={onClose}
                  className={`group flex items-center gap-3 px-3.5 py-2.5 rounded-lg text-[13px] mb-1 border transition-all duration-200 ${active ? "bg-gradient-to-r from-gold/[.14] to-white/[.025] border-gold-dim/45 text-gold-bright shadow-[0_0_25px_-14px_rgba(228,199,122,.85)]" : "text-[#b8c8db] border-transparent hover:text-white hover:bg-white/[.035] hover:border-white/[.06]"}`}
                >
                  <span
                    className={`w-6 h-6 rounded-md flex items-center justify-center text-sm ${active ? "text-gold-bright" : "text-[#8ea8c7] group-hover:text-white"}`}
                  >
                    {item.icon}
                  </span>
                  <span className="flex-1">
                    {navLabels[item.href] || item.label}
                  </span>
                  {active && (
                    <span className="h-1.5 w-1.5 rounded-full bg-gold-bright shadow-[0_0_12px_rgba(228,199,122,.9)]" />
                  )}
                </Link>
              </div>
            );
          })}
        </nav>

        <div className="p-5 border-t border-white/[0.055] bg-[#06111d]/65">
          <InstallApp />
          <div className="gold-line my-3 opacity-35" />
          <p className="font-mono text-[8px] uppercase tracking-[0.28em] text-cool-gray/45 text-center leading-relaxed">
            Navigating
            <br />a stronger future
          </p>
        </div>
      </aside>
    </>
  );
}
