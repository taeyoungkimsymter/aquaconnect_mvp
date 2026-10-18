import type { Metadata } from "next";
import { Geist } from "next/font/google";
import { cookies } from "next/headers";
import NavLink from "@/components/NavLink";
import LogoutButton from "@/components/LogoutButton";
import { COOKIE_NAME, verifySessionToken } from "@/lib/auth";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "AquaConnect Admin",
  description: "AquaConnect 통합관리 대시보드",
};

const navItems = [
  { href: "/",          iconKey: "dashboard", label: "대시보드" },
  { href: "/community", iconKey: "community", label: "커뮤니티 관리" },
  { href: "/news",      iconKey: "news",      label: "수산 뉴스 관리" },
  { href: "/accounts",  iconKey: "accounts",  label: "계정 관리" },
];

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const cookieStore = await cookies();
  const token = cookieStore.get(COOKIE_NAME)?.value;
  const isLoggedIn = token ? await verifySessionToken(token) : false;

  return (
    <html lang="ko" className={geistSans.variable} style={{ height: "100%" }}>
      <body className="admin-body" style={{ minHeight: "100%", display: "flex" }}>

        {isLoggedIn ? (
          <>
            {/* ── 사이드바 ── */}
            <nav className="admin-sidebar" style={{
              width: 240,
              minWidth: 240,
              display: "flex",
              flexDirection: "column",
              background: "linear-gradient(180deg, #185FA5 0%, #0C447C 100%)",
              minHeight: "100vh",
              boxShadow: "2px 0 16px rgba(12,68,124,0.20)",
            }}>

              {/* 로고 */}
              <div className="admin-logo" style={{ padding: "28px 20px 20px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <div style={{
                    width: 40, height: 40,
                    borderRadius: 12,
                    background: "rgba(255,255,255,0.18)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: 22,
                  }}>🐟</div>
                  <div>
                    <p style={{ fontWeight: 800, fontSize: 15, color: "#fff", lineHeight: 1.2 }}>AquaConnect</p>
                    <p style={{ fontSize: 11, color: "rgba(255,255,255,0.55)", marginTop: 1 }}>관리자 대시보드</p>
                  </div>
                </div>
              </div>

              {/* 구분선 */}
              <div className="admin-divider" style={{ height: 1, background: "rgba(255,255,255,0.12)", margin: "0 20px 12px" }} />

              {/* 네비게이션 */}
              <ul className="admin-nav" style={{ display: "flex", flexDirection: "column", gap: 2, padding: "0 10px", flex: 1, listStyle: "none" }}>
                {navItems.map(({ href, iconKey, label }) => (
                  <li key={href}>
                    <NavLink href={href} iconKey={iconKey} label={label} />
                  </li>
                ))}
              </ul>

              {/* 하단: 로그아웃 */}
              <div className="admin-logout" style={{ padding: "0 10px 24px" }}>
                <div className="admin-divider" style={{ height: 1, background: "rgba(255,255,255,0.12)", margin: "0 4px 10px" }} />
                <LogoutButton />
              </div>
            </nav>

            {/* ── 메인 콘텐츠 ── */}
            <main className="admin-main" style={{ flex: 1, minWidth: 0, padding: "36px 40px", background: "#F0F2F5", overflowX: "hidden" }}>
              {children}
            </main>
          </>
        ) : (
          <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", background: "#F0F2F5" }}>
            {children}
          </div>
        )}

      </body>
    </html>
  );
}
