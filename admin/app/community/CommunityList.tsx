"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ChevronLeft, ChevronRight, Download, Image as ImageIcon, MessageCircle, Search, Trash2, X } from "lucide-react";
import { adminFetch, formatDateTime, type MemoPage, type Organization } from "@/lib/api";
import { Badge, Button, COLORS, Empty, ErrorBox, inputStyle, Loading, PageHeader, RefreshButton } from "@/components/ui";
import ExportPanel from "./ExportPanel";

const PAGE_SIZE = 20;

export default function CommunityList({ authorId, authorName }: { authorId: string | null; authorName: string | null }) {
  const router = useRouter();
  const [orgs, setOrgs] = useState<Organization[]>([]);
  const [orgId, setOrgId] = useState("");
  const [queryInput, setQueryInput] = useState("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<MemoPage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [deleting, setDeleting] = useState<string | null>(null);
  const [exporting, setExporting] = useState(false);

  useEffect(() => {
    adminFetch<Organization[]>("organizations").then(setOrgs).catch(() => {});
  }, []);

  const fetchMemos = useCallback(async () => {
    setLoading(true);
    setError("");
    const params = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE) });
    if (q) params.set("q", q);
    if (orgId) params.set("orgId", orgId);
    if (authorId) params.set("authorId", authorId);
    try {
      setData(await adminFetch<MemoPage>(`memos?${params}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : "메모를 불러올 수 없습니다.");
    } finally {
      setLoading(false);
    }
  }, [page, q, orgId, authorId]);

  useEffect(() => { fetchMemos(); }, [fetchMemos]);

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    setPage(1);
    setQ(queryInput.trim());
  }

  async function handleDelete(id: string) {
    if (!confirm("이 메모를 삭제할까요?\n사진·댓글·수정 이력도 함께 삭제되며 되돌릴 수 없습니다.")) return;
    setDeleting(id);
    try {
      await adminFetch(`memos/${id}`, { method: "DELETE" });
      await fetchMemos();
    } catch (e) {
      alert(e instanceof Error ? e.message : "삭제에 실패했습니다.");
    } finally {
      setDeleting(null);
    }
  }

  const totalPages = data ? Math.max(1, Math.ceil(data.total / PAGE_SIZE)) : 1;

  return (
    <div>
      <PageHeader
        title="커뮤니티 관리"
        subtitle="모든 관리원의 현장 메모와 댓글을 검토하고, 부적절한 글을 삭제합니다."
      />

      {/* 검색 + 필터 */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        <form onSubmit={handleSearch} style={{ display: "flex", gap: 8, flex: "1 1 320px" }}>
          <div style={{ position: "relative", flex: 1 }}>
            <Search size={16} color="#999" style={{ position: "absolute", left: 14, top: "50%", transform: "translateY(-50%)" }} />
            <input
              value={queryInput}
              onChange={(e) => setQueryInput(e.target.value)}
              placeholder="내용 · 댓글 · 작성자 · 양식장 · 관리원 검색"
              style={{ ...inputStyle, paddingLeft: 38, background: "#fff" }}
            />
          </div>
          <Button type="submit">검색</Button>
        </form>
        <select
          value={orgId}
          onChange={(e) => { setOrgId(e.target.value); setPage(1); }}
          style={{ ...inputStyle, width: "auto", minWidth: 180, background: "#fff", cursor: "pointer" }}
        >
          <option value="">전체 관리원</option>
          {orgs.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
        </select>
        <RefreshButton onClick={fetchMemos} />
        <Button variant="outline" onClick={() => setExporting((v) => !v)}>
          <Download size={14} /> CSV 내보내기
        </Button>
      </div>

      {exporting && (
        <ExportPanel
          orgId={orgId}
          orgName={orgs.find((o) => o.id === orgId)?.name ?? null}
          authorId={authorId}
          authorName={authorName}
          q={q}
          onClose={() => setExporting(false)}
        />
      )}

      {/* 적용 중인 필터 */}
      {(authorId || q) && (
        <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
          {authorId && (
            <FilterTag onClear={() => router.push("/community")}>작성자: {authorName ?? "선택한 계정"}</FilterTag>
          )}
          {q && (
            <FilterTag onClear={() => { setQ(""); setQueryInput(""); setPage(1); }}>검색어: {q}</FilterTag>
          )}
        </div>
      )}

      {data && !loading && (
        <p style={{ fontSize: 12, color: "#999", marginBottom: 12 }}>총 {data.total.toLocaleString()}건</p>
      )}

      {loading && <Loading />}
      {error && <ErrorBox>{error}</ErrorBox>}
      {!loading && !error && data?.items.length === 0 && <Empty>해당 조건의 메모가 없습니다.</Empty>}

      {!loading && data && data.items.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {data.items.map((m) => (
            <div
              key={m.id}
              style={{
                background: "#fff",
                borderRadius: 18,
                padding: "18px 24px",
                boxShadow: "0 2px 8px rgba(0,0,0,0.06)",
                display: "flex",
                gap: 16,
                alignItems: "flex-start",
              }}
            >
              <Link href={`/community/${m.id}`} style={{ flex: 1, minWidth: 0, textDecoration: "none", color: "inherit" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap", marginBottom: 8 }}>
                  <Badge color={COLORS.primaryDark} bg={COLORS.primarySoft}>{m.orgName}</Badge>
                  <span style={{ fontSize: 12, fontWeight: 700, color: "#1a1a1a" }}>{m.farmName ?? "양식장 미지정"}</span>
                  <span style={{ fontSize: 12, color: "#999" }}>· {m.authorName}</span>
                  <span style={{ fontSize: 12, color: "#aaa" }}>· {formatDateTime(m.createdAt)}</span>
                </div>
                <p style={{
                  fontSize: 14, color: "#333", lineHeight: 1.6, whiteSpace: "pre-wrap",
                  display: "-webkit-box", WebkitLineClamp: 3, WebkitBoxOrient: "vertical", overflow: "hidden",
                }}>
                  {m.content}
                </p>
                <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 10, flexWrap: "wrap" }}>
                  {m.tags.map((t) => <Badge key={t} color="#555" bg={COLORS.neutralSoft}>#{t}</Badge>)}
                  {m.commentCount > 0 && (
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 4, fontSize: 12, color: "#666" }}>
                      <MessageCircle size={13} /> {m.commentCount}
                    </span>
                  )}
                  {m.photoCount > 0 && (
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 4, fontSize: 12, color: "#666" }}>
                      <ImageIcon size={13} /> {m.photoCount}
                    </span>
                  )}
                  {m.editCount > 0 && <span style={{ fontSize: 12, color: "#aaa" }}>수정됨</span>}
                </div>
              </Link>
              <Button variant="outline" disabled={deleting === m.id} onClick={() => handleDelete(m.id)}>
                <Trash2 size={14} />
                {deleting === m.id ? "삭제 중..." : "삭제"}
              </Button>
            </div>
          ))}
        </div>
      )}

      {/* 페이지 */}
      {data && totalPages > 1 && (
        <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 12, marginTop: 24 }}>
          <Button variant="outline" disabled={page <= 1 || loading} onClick={() => setPage(page - 1)}>
            <ChevronLeft size={14} /> 이전
          </Button>
          <span style={{ fontSize: 13, color: "#666", fontWeight: 600 }}>{page} / {totalPages}</span>
          <Button variant="outline" disabled={page >= totalPages || loading} onClick={() => setPage(page + 1)}>
            다음 <ChevronRight size={14} />
          </Button>
        </div>
      )}
    </div>
  );
}

function FilterTag({ children, onClear }: { children: React.ReactNode; onClear: () => void }) {
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 6,
      padding: "6px 8px 6px 14px", borderRadius: 99,
      background: COLORS.primarySoft, color: COLORS.primaryDark, fontSize: 12, fontWeight: 700,
    }}>
      {children}
      <button
        onClick={onClear}
        aria-label="필터 해제"
        style={{ display: "flex", border: "none", background: "transparent", cursor: "pointer", color: COLORS.primaryDark, padding: 2 }}
      >
        <X size={14} />
      </button>
    </span>
  );
}
