import Link from "next/link";
import type { ReactNode } from "react";

import { IconBuilding, IconHome } from "@/components/icons";

interface NavItem {
  href: string;
  label: string;
  icon: ReactNode;
}

const COMPANY_NAV: NavItem[] = [
  { href: "/dashboard", label: "Home", icon: <IconHome className="h-5 w-5" /> },
  { href: "/properties", label: "Properties", icon: <IconBuilding className="h-5 w-5" /> },
];

const OWNER_NAV: NavItem[] = [
  { href: "/owner", label: "Dashboard", icon: <IconHome className="h-5 w-5" /> },
];

export function AppShell({
  title,
  variant,
  activeHref,
  children,
}: {
  title: string;
  variant: "company" | "owner";
  activeHref: string;
  children: ReactNode;
}) {
  const nav = variant === "company" ? COMPANY_NAV : OWNER_NAV;

  return (
    <div className="min-h-screen bg-surface text-navy">
      <header className="fixed top-0 z-50 w-full border-b border-border bg-white shadow-sm">
        <div className="flex h-16 items-center justify-between px-6">
          <h1 className="text-base font-bold uppercase tracking-tight">{title}</h1>
        </div>
      </header>
      <main className="space-y-6 px-6 pb-28 pt-20">{children}</main>
      <nav
        aria-label="Primary"
        className="fixed bottom-0 z-50 h-20 w-full border-t border-border bg-white px-2"
      >
        <div className="flex h-full items-center justify-around">
          {nav.map((item) => {
            const isActive = activeHref === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={isActive ? "page" : undefined}
                className={`flex flex-col items-center justify-center rounded-xl px-4 py-2 ${
                  isActive ? "bg-navy/10 text-navy" : "text-navy/50"
                }`}
              >
                {item.icon}
                <span className="mt-1 text-[10px] font-bold uppercase tracking-tighter">
                  {item.label}
                </span>
              </Link>
            );
          })}
        </div>
      </nav>
    </div>
  );
}
