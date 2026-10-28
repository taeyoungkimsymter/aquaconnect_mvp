import { NextRequest, NextResponse } from "next/server";
import { upstream } from "@/lib/api-admin";

/**
 * 브라우저 → AquaConnect 서버 /api/admin/* 프록시.
 * 세션 확인은 proxy.ts 가 먼저 하고, 여기서는 ADMIN_API_KEY 만 붙여 넘긴다.
 */
async function forward(req: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  const { path } = await params;
  const target = path.map(encodeURIComponent).join("/") + req.nextUrl.search;
  const body = req.method === "GET" || req.method === "DELETE" ? undefined : await req.text();

  let res: Response;
  try {
    res = await upstream(target, {
      method: req.method,
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body,
    });
  } catch (e) {
    console.error("[admin-proxy] error:", e);
    return NextResponse.json({ error: "AquaConnect 서버에 연결할 수 없습니다." }, { status: 502 });
  }

  const headers = new Headers();
  // Content-Disposition / X-Export-*: the 글 로그 CSV download.
  for (const h of ["Content-Type", "Cache-Control", "Content-Disposition", "X-Export-Rows", "X-Export-Truncated"]) {
    const v = res.headers.get(h);
    if (v) headers.set(h, v);
  }
  return new NextResponse(res.status === 204 ? null : res.body, { status: res.status, headers });
}

export { forward as GET, forward as POST, forward as PATCH, forward as DELETE };
