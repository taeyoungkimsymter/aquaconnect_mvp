// AI 모델 연결(서버 전용) — symterAI src/lib/model.ts 의 OpenAI 호환 경로 이식.
// 기본값은 Google Gemini 의 OpenAI 호환 엔드포인트. 키는 환경변수 MODEL_API_KEY 에서만
// 읽고, 상태·오류·응답에 절대 싣지 않는다.

const DEFAULT_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/openai';

// 앱에서 고를 수 있는 모델. dailyLimit 은 Gemini 무료 등급의 하루 요청 한도(RPD) —
// 결제를 연결하면 MODEL_DAILY_LIMITS 로 덮어쓴다(예: {"gemini-3.5-flash":10000}).
export const MODEL_CATALOG = [
  { id: 'gemini-3.5-flash', label: 'Gemini 3.5 Flash', description: '기본 · 품질과 속도의 균형', dailyLimit: 20 },
  { id: 'gemini-3.8-flash', label: 'Gemini 3.8 Flash', description: '최신 Flash · 가장 정교한 정리', dailyLimit: 20 },
  { id: 'gemini-3.6-flash', label: 'Gemini 3.6 Flash', description: 'Flash 이전 버전', dailyLimit: 20 },
  { id: 'gemini-3.5-flash-lite', label: 'Gemini 3.5 Flash Lite', description: '한도 넉넉 · 사실 오류가 더 잦아 꼼꼼한 검토 필요', dailyLimit: 500 },
];

export class AiError extends Error {
  constructor(message, status = 502) {
    super(message);
    this.status = status;
  }
}

function baseUrl() {
  return (process.env.MODEL_BASE_URL?.trim() || DEFAULT_BASE_URL).replace(/\/+$/, '');
}

function limitOverrides() {
  try {
    return JSON.parse(process.env.MODEL_DAILY_LIMITS || '{}');
  } catch {
    return {};
  }
}

export function modelOptions() {
  const overrides = limitOverrides();
  return MODEL_CATALOG.map((m) => ({ ...m, dailyLimit: Number(overrides[m.id]) || m.dailyLimit }));
}

export function defaultModel() {
  const wanted = process.env.MODEL_NAME?.trim();
  return MODEL_CATALOG.some((m) => m.id === wanted) ? wanted : MODEL_CATALOG[0].id;
}

export function modelStatus() {
  const configured = Boolean(process.env.MODEL_API_KEY?.trim());
  return {
    configured,
    model: defaultModel(),
    note: configured ? '연결 설정이 있습니다(실제 호출 성공은 사용 시 확인).' : '미연결 — 서버에 MODEL_API_KEY 가 없습니다.',
  };
}

/** 느린 응답 대비 대기 시간(ms). 기본 180초. */
const timeoutMs = () => Number(process.env.MODEL_TIMEOUT_MS) || 180_000;

/**
 * system + user 한 번 호출. json=true 면 JSON 객체만 받도록 요청한다.
 * 생각(추론) 토큰이 출력 한도를 함께 쓰는 Gemini 는 reasoning_effort 로 줄인다(기본 low).
 * onResult({ model, outcome: 'ok'|'quota'|'error', usage }) 는 Google 에 요청이 닿을 때마다
 * 불린다 — 하루 사용량 집계용.
 */
export async function chat(system, user, { model, maxTokens = 8000, json = false, onResult } = {}) {
  if (!process.env.MODEL_API_KEY?.trim()) throw new AiError('AI가 연결되지 않았습니다. 서버에 MODEL_API_KEY 를 설정해 주세요.', 503);
  const chosen = model ?? defaultModel();
  if (!MODEL_CATALOG.some((m) => m.id === chosen)) throw new AiError('고를 수 없는 AI 모델입니다.', 400);
  const report = async (outcome, usage = null) => {
    try {
      await onResult?.({ model: chosen, outcome, usage });
    } catch (err) {
      console.error('ai usage record failed', err);
    }
  };
  const effort = process.env.MODEL_REASONING_EFFORT?.trim() || 'low';
  let res;
  try {
    res = await fetch(`${baseUrl()}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${process.env.MODEL_API_KEY.trim()}` },
      body: JSON.stringify({
        model: chosen,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
        max_tokens: maxTokens,
        temperature: 0.2,
        ...(effort && effort !== 'none' ? { reasoning_effort: effort } : {}),
        ...(json ? { response_format: { type: 'json_object' } } : {}),
      }),
      signal: AbortSignal.timeout(timeoutMs()),
    });
  } catch {
    throw new AiError('AI 서버에 연결하지 못했거나 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.');
  }
  if (res.status === 429) {
    await report('quota');
    throw new AiError('이 모델의 사용 한도를 다 썼습니다. 다른 모델을 고르거나 잠시 후 다시 시도해 주세요.', 429);
  }
  if (!res.ok) {
    await report('error');
    throw new AiError(`AI 서버 응답 오류(${res.status}). 서버 설정을 확인해 주세요.`);
  }
  const payload = await res.json();
  await report('ok', payload?.usage ?? null);
  const choice = payload?.choices?.[0];
  // 출력 한도에서 잘린 답변은 실제 AI 결과로 저장하지 않는다.
  if (choice?.finish_reason === 'length') {
    throw new AiError('AI 답변이 출력 한도에서 잘렸습니다. 선택한 메모를 줄여 다시 시도해 주세요.');
  }
  const content = choice?.message?.content;
  if (typeof content !== 'string' || !content.trim()) throw new AiError('AI 서버에서 표시할 답변을 받지 못했습니다.');
  return { text: content.trim(), model: chosen };
}
