"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { ChevronLeft, ChevronRight, Eye, EyeOff, ExternalLink, Pencil, Play, Search } from "lucide-react";
import { adminFetch, formatDateTime } from "@/lib/api";
import { Badge, Button, COLORS, Empty, ErrorBox, inputStyle, Loading, PageHeader, RefreshButton } from "@/components/ui";

const PAGE_SIZE = 30;

const CATEGORIES = [
  { key: "disease", label: "질병·방역" },
  { key: "environment", label: "해양환경" },
  { key: "support", label: "지원사업" },
  { key: "policy", label: "양식·정책" },
];
const categoryLabel = (key: string) => CATEGORIES.find((c) => c.key === key)?.label ?? key;

interface NewsRow {
  id: string;
  source: string;
  sourceName: string;
  title: string;
  url: string;
  publishedAt: string | null;
  fetchedAt: string;
  category: string;
  summary: string | null;
  regions: string[];
  species: string[];
  isPublished: boolean;
  editedByAdmin: boolean;
}
interface NewsPage {
  items: NewsRow[];
  hasMore: boolean;
}
interface SourceStatus {
  source: string;
  name: string;
  lastAttemptAt: string | null;
  lastSuccessAt: string | null;
  lastError: string | null;
  lastFetchedCount: number | null;
  lastSavedCount: number | null;
}
interface CollectOutcome {
  skipped?: string;
  results: { source: string; ok: boolean; fetched?: number; saved?: number; error?: string }[];
}

export default function NewsAdminPage() {
  const [sources, setSources] = useState<SourceStatus[]>([]);
  const [category, setCategory] = useState("");
  const [published, setPublished] = useState("");
  const [queryInput, setQueryInput] = useState("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<NewsPage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [collecting, setCollecting] = useState(false);
  const [outcome, setOutcome] = useState<CollectOutcome | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [draftCategory, setDraftCategory] = useState("");
  const [draftSummary, setDraftSummary] = useState("");
  const [busy, setBusy] = useState<string | null>(null);

  const fetchSources = useCallback(async () => {
    try {
      setSources(await adminFetch<SourceStatus[]>("news/sources"));
    } catch {
      /* 상태 카드는 보조 정보 — 실패해도 목록은 계속 보인다 */
    }
  }, []);

  const fetchNews = useCallback(async () => {
    setLoading(true);
    setError("");
    const params = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE) });
    if (category) params.set("category", category);
    if (published) params.set("published", published);
    if (q) params.set("q", q);
    try {
      setData(await adminFetch<NewsPage>(`news?${params}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : "뉴스를 불러올 수 없습니다.");
    } finally {
      setLoading(false);
    }
  }, [page, category, published, q]);

  useEffect(() => { fetchNews(); }, [fetchNews]);
  useEffect(() => { fetchSources(); }, [fetchSources]);

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    setPage(1);
    setQ(queryInput.trim());
  }

  async function collect(backfill: boolean) {
    setCollecting(true);
    setOutcome(null);
    try {
      setOutcome(await adminFetch<CollectOutcome>("news/collect", { method: "POST", body: JSON.stringify({ backfill }) }));
      await Promise.all([fetchNews(), fetchSources()]);
    } catch (e) {
      alert(e instanceof Error ? e.message : "수집을 실행하지 못했습니다.");
    } finally {
      setCollecting(false);
    }
  }

  async function patch(id: string, body: Record<string, unknown>) {
    setBusy(id);
    try {
      await adminFetch(`news/${id}`, { method: "PATCH", body: JSON.stringify(body) });
      setEditing(null);
      await fetchNews();
    } catch (e) {
      alert(e instanceof Error ? e.message : "저장하지 못했습니다.");
    } finally {
      setBusy(null);
    }
  }

  function startEdit(n: NewsRow) {
    setEditing(n.id);
    setDraftCategory(n.category);
    setDraftSummary(n.summary ?? "");
  }

  return (
    <div>
      <PageHeader
        title="수산 뉴스 관리"
        subtitle="해양수산부·국립수산과학원 공식 소식을 하루 세 번(08:00·14:00·20:00) 자동 수집합니다. 분류·소개를 고치거나 숨길 수 있고, 숨긴 소식은 재수집해도 다시 공개되지 않습니다."
      />

      {/* 출처별 마지막 수집 결과 */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))", gap: 12, marginBottom: 16 }}>
        {sources.length === 0 && <Empty>아직 수집 기록이 없습니다. 아래 &quot;지금 수집&quot;으로 실행해 보세요.</Empty>}
        {sources.map((s) => (
          <div key={s.source} style={{ background: "#fff", borderRadius: 18, padding: "16px 20px", boxShadow: "0 2px 8px rgba(0,0,0,0.06)" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
              <span style={{ fontWeight: 800, fontSize: 14 }}>{s.name}</span>
              {s.lastError
                ? <Badge color={COLORS.dangerText} bg={COLORS.dangerSoft}>마지막 수집 실패</Badge>
                : <Badge color={COLORS.successText} bg={COLORS.successSoft}>정상</Badge>}
            </div>
            <p style={{ fontSize: 12, color: "#666", lineHeight: 1.7 }}>
              마지막 성공: {s.lastSuccessAt ? formatDateTime(s.lastSuccessAt) : "없음"}<br />
              마지막 시도: {s.lastAttemptAt ? formatDateTime(s.lastAttemptAt) : "없음"}<br />
              {s.lastFetchedCount !== null && <>성공 시 확인 {s.lastFetchedCount}건 · 저장·갱신 {s.lastSavedCount}건</>}
            </p>
            {s.lastError && (
              <p style={{ fontSize: 12, color: COLORS.dangerText, background: COLORS.dangerSoft, borderRadius: 8, padding: "8px 10px", marginTop: 8, wordBreak: "break-all" }}>
                {s.lastError} <br />(기존 뉴스는 그대로 보이고 있습니다)
              </p>
            )}
          </div>
        ))}
      </div>

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap", alignItems: "center" }}>
        <Button disabled={collecting} onClick={() => collect(false)}>
          <Play size={14} /> {collecting ? "수집 중..." : "지금 수집"}
        </Button>
        <Button variant="outline" disabled={collecting} onClick={() => collect(true)}>최근 30일 다시 보충</Button>
        {outcome && (
          <span style={{ fontSize: 12, color: "#555" }}>
            {outcome.skipped
              ? outcome.skipped
              : outcome.results.map((r) => `${r.source}: ${r.ok ? `확인 ${r.fetched}건 · 저장 ${r.saved}건` : `실패(${r.error})`}`).join("  /  ")}
          </span>
        )}
      </div>

      {/* 검색 + 필터 */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        <form onSubmit={handleSearch} style={{ display: "flex", gap: 8, flex: "1 1 280px" }}>
          <div style={{ position: "relative", flex: 1 }}>
            <Search size={16} color="#999" style={{ position: "absolute", left: 14, top: "50%", transform: "translateY(-50%)" }} />
            <input value={queryInput} onChange={(e) => setQueryInput(e.target.value)} placeholder="제목 검색" style={{ ...inputStyle, paddingLeft: 38, background: "#fff" }} />
          </div>
          <Button type="submit">검색</Button>
        </form>
        <select value={category} onChange={(e) => { setCategory(e.target.value); setPage(1); }} style={{ ...inputStyle, width: "auto", background: "#fff", cursor: "pointer" }}>
          <option value="">전체 분류</option>
          {CATEGORIES.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
        </select>
        <select value={published} onChange={(e) => { setPublished(e.target.value); setPage(1); }} style={{ ...inputStyle, width: "auto", background: "#fff", cursor: "pointer" }}>
          <option value="">게시·숨김 모두</option>
          <option value="true">게시 중</option>
          <option value="false">숨김</option>
        </select>
        <RefreshButton onClick={() => { fetchNews(); fetchSources(); }} />
      </div>

      {loading && <Loading />}
      {error && <ErrorBox>{error}</ErrorBox>}
      {!loading && !error && data?.items.length === 0 && <Empty>조건에 맞는 소식이 없습니다.</Empty>}

      {!loading && data && data.items.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {data.items.map((n) => (
            <div key={n.id} style={{ background: "#fff", borderRadius: 18, padding: "18px 24px", boxShadow: "0 2px 8px rgba(0,0,0,0.06)", opacity: n.isPublished ? 1 : 0.65 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap", marginBottom: 8 }}>
                <Badge color={COLORS.primaryDark} bg={COLORS.primarySoft}>{categoryLabel(n.category)}</Badge>
                <span style={{ fontSize: 12, color: "#666" }}>{n.sourceName}</span>
                <span style={{ fontSize: 12, color: "#999" }}>· 원문 게시 {n.publishedAt ? formatDateTime(n.publishedAt) : "확인 불가"}</span>
                <span style={{ fontSize: 12, color: "#aaa" }}>· 수집 {formatDateTime(n.fetchedAt)}</span>
                {!n.isPublished && <Badge color={COLORS.warnText} bg={COLORS.warnSoft}>숨김</Badge>}
                {n.editedByAdmin && <Badge color="#555" bg={COLORS.neutralSoft}>관리자 수정</Badge>}
              </div>
              <a href={n.url} target="_blank" rel="noopener noreferrer" style={{ fontSize: 15, fontWeight: 700, color: "#1a1a1a", textDecoration: "none", display: "inline-flex", gap: 6, alignItems: "center" }}>
                {n.title} <ExternalLink size={13} color="#999" />
              </a>
              {editing === n.id ? (
                <div style={{ marginTop: 12, display: "flex", flexDirection: "column", gap: 8 }}>
                  <select value={draftCategory} onChange={(e) => setDraftCategory(e.target.value)} style={{ ...inputStyle, width: "auto", background: "#fff" }}>
                    {CATEGORIES.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
                  </select>
                  <textarea
                    value={draftSummary}
                    onChange={(e) => setDraftSummary(e.target.value)}
                    maxLength={300}
                    rows={3}
                    placeholder="짧은 소개 (비우면 표시하지 않음, 300자 이내)"
                    style={{ ...inputStyle, resize: "vertical" }}
                  />
                  <div style={{ display: "flex", gap: 8 }}>
                    <Button disabled={busy === n.id} onClick={() => patch(n.id, { category: draftCategory, summary: draftSummary })}>저장</Button>
                    <Button variant="outline" onClick={() => setEditing(null)}>취소</Button>
                  </div>
                </div>
              ) : (
                <>
                  {n.summary && <p style={{ fontSize: 13, color: "#555", lineHeight: 1.6, marginTop: 8 }}>{n.summary}</p>}
                  {(n.regions.length > 0 || n.species.length > 0) && (
                    <p style={{ fontSize: 12, color: "#888", marginTop: 6 }}>
                      {n.regions.length > 0 && <>지역 {n.regions.join(", ")} </>}
                      {n.species.length > 0 && <>어종 {n.species.join(", ")}</>}
                    </p>
                  )}
                  <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
                    <Button variant="outline" onClick={() => startEdit(n)}><Pencil size={14} /> 분류·소개 수정</Button>
                    <Button variant="outline" disabled={busy === n.id} onClick={() => patch(n.id, { isPublished: !n.isPublished })}>
                      {n.isPublished ? <><EyeOff size={14} /> 숨기기</> : <><Eye size={14} /> 다시 게시</>}
                    </Button>
                  </div>
                </>
              )}
            </div>
          ))}
        </div>
      )}

      {data && (page > 1 || data.hasMore) && (
        <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 12, marginTop: 24 }}>
          <Button variant="outline" disabled={page <= 1 || loading} onClick={() => setPage(page - 1)}><ChevronLeft size={14} /> 이전</Button>
          <span style={{ fontSize: 13, color: "#666", fontWeight: 600 }}>{page}쪽</span>
          <Button variant="outline" disabled={!data.hasMore || loading} onClick={() => setPage(page + 1)}>다음 <ChevronRight size={14} /></Button>
        </div>
      )}
    </div>
  );
}
