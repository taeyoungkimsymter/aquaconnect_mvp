"use client";

import { useState } from "react";
import { Download, X } from "lucide-react";
import { Button, COLORS, cardStyle, inputStyle } from "@/components/ui";

/** "YYYY-MM-DD" in Korean time, [days] days before today. */
function kstDate(daysAgo = 0): string {
  return new Date(Date.now() + 9 * 3600_000 - daysAgo * 86400_000).toISOString().slice(0, 10);
}

const PRESETS: { label: string; days: number | null }[] = [
  { label: "최근 7일", days: 7 },
  { label: "최근 30일", days: 30 },
  { label: "최근 90일", days: 90 },
  { label: "전체 기간", days: null },
];

/**
 * 글 로그 CSV 내보내기: every 메모 and 댓글 as one row each, oldest first,
 * with the list's current filters (관리원 · 작성자 · 검색어) plus a period.
 */
export default function ExportPanel({
  orgId,
  orgName,
  authorId,
  authorName,
  q,
  onClose,
}: {
  orgId: string;
  orgName: string | null;
  authorId: string | null;
  authorName: string | null;
  q: string;
  onClose: () => void;
}) {
  const [from, setFrom] = useState(kstDate(29));
  const [to, setTo] = useState(kstDate());
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);

  function applyPreset(days: number | null) {
    setFrom(days == null ? "" : kstDate(days - 1));
    setTo(days == null ? "" : kstDate());
  }

  async function download() {
    if (from && to && from > to) {
      setResult({ ok: false, text: "시작일이 종료일보다 늦습니다." });
      return;
    }
    setBusy(true);
    setResult(null);
    const params = new URLSearchParams();
    if (from) params.set("from", from);
    if (to) params.set("to", to);
    if (orgId) params.set("orgId", orgId);
    if (authorId) params.set("authorId", authorId);
    if (q) params.set("q", q);
    try {
      const res = await fetch(`/api/admin/export/posts.csv?${params}`, { cache: "no-store" });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? `HTTP ${res.status}`);
      }
      const blob = await res.blob();
      const name =
        /filename="([^"]+)"/.exec(res.headers.get("Content-Disposition") ?? "")?.[1] ?? "aquaconnect_posts.csv";
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = name;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30_000);
      const rows = Number(res.headers.get("X-Export-Rows") ?? 0);
      const truncated = res.headers.get("X-Export-Truncated") === "1";
      setResult({
        ok: true,
        text: truncated
          ? `${rows.toLocaleString()}건까지만 저장했습니다. 기간을 나눠서 다시 내보내 주세요.`
          : `${rows.toLocaleString()}건을 저장했습니다 (${name}).`,
      });
    } catch (e) {
      setResult({ ok: false, text: e instanceof Error ? e.message : "내보내기에 실패했습니다." });
    } finally {
      setBusy(false);
    }
  }

  const filters = [
    orgName && `관리원: ${orgName}`,
    authorId && `작성자: ${authorName ?? "선택한 계정"}`,
    q && `검색어: ${q}`,
  ].filter(Boolean);

  return (
    <div style={{ ...cardStyle, marginBottom: 16, border: `1.5px solid ${COLORS.primarySoft}` }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 6 }}>
        <p style={{ fontSize: 15, fontWeight: 800, color: "#1a1a1a" }}>글 로그 CSV 내보내기</p>
        <button
          onClick={onClose}
          aria-label="닫기"
          style={{ display: "flex", border: "none", background: "transparent", cursor: "pointer", color: "#999", padding: 4 }}
        >
          <X size={16} />
        </button>
      </div>
      <p style={{ fontSize: 12, color: "#888", marginBottom: 14, lineHeight: 1.6 }}>
        메모와 댓글을 작성 시각 순으로 한 줄씩 저장합니다 — 작성일시 · 유형 · 관리원 · 양식장 · 작성자 · 내용 · 태그 · 호출 ·
        첨부 수 · 완료 여부. 엑셀에서 바로 열 수 있어요. 삭제된 글은 포함되지 않습니다.
      </p>

      <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 10 }}>
        {PRESETS.map((p) => (
          <Button key={p.label} variant="outline" onClick={() => applyPreset(p.days)}>
            {p.label}
          </Button>
        ))}
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
        <input
          type="date"
          value={from}
          max={to || undefined}
          onChange={(e) => setFrom(e.target.value)}
          aria-label="시작일"
          style={{ ...inputStyle, width: "auto", background: "#fff" }}
        />
        <span style={{ color: "#999" }}>~</span>
        <input
          type="date"
          value={to}
          min={from || undefined}
          onChange={(e) => setTo(e.target.value)}
          aria-label="종료일"
          style={{ ...inputStyle, width: "auto", background: "#fff" }}
        />
        <span style={{ fontSize: 12, color: "#999" }}>
          {!from && !to ? "전체 기간" : "한국 시간 기준, 종료일 포함"}
        </span>
      </div>

      <p style={{ fontSize: 12, color: "#666", marginBottom: 12 }}>
        {filters.length ? `목록 필터 적용 — ${filters.join(" · ")}` : "모든 관리원의 글"}
      </p>

      <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <Button disabled={busy} onClick={download}>
          <Download size={14} />
          {busy ? "만드는 중..." : "CSV 다운로드"}
        </Button>
        {result && (
          <span style={{ fontSize: 12, fontWeight: 600, color: result.ok ? COLORS.successText : COLORS.danger }}>
            {result.text}
          </span>
        )}
      </div>
    </div>
  );
}
