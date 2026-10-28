"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, Users, MessagesSquare, type LucideIcon } from "lucide-react";

const ICON_MAP: Record<string, LucideIcon> = {
  dashboard: LayoutDashboard,
  community: MessagesSquare,
  accounts: Users,
};

interface NavLinkProps {
  href: string;
  iconKey: string;
  label: string;
}

export default function NavLink({ href, iconKey, label }: NavLinkProps) {
  const pathname = usePathname();
  // 상세 페이지(/accounts/<id>)에서도 부모 메뉴가 활성 상태를 유지해야 한다.
  const active = pathname === href || (href !== "/" && pathname.startsWith(`${href}/`));
  const Icon = ICON_MAP[iconKey] ?? LayoutDashboard;

  return (
    <Link
      href={href}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: "10px 14px",
        borderRadius: 12,
        textDecoration: "none",
        fontSize: 14,
        fontWeight: active ? 700 : 500,
        color: active ? "#fff" : "rgba(255,255,255,0.70)",
        background: active ? "rgba(255,255,255,0.18)" : "transparent",
        transition: "all 0.15s",
      }}
      onMouseOver={(e) => {
        if (!active) (e.currentTarget as HTMLElement).style.background = "rgba(255,255,255,0.10)";
      }}
      onMouseOut={(e) => {
        if (!active) (e.currentTarget as HTMLElement).style.background = "transparent";
      }}
    >
      <Icon size={18} strokeWidth={active ? 2.5 : 2} />
      {label}
    </Link>
  );
}
