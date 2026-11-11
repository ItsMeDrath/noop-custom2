import { z } from 'zod';
import { nutritionPrompts } from './prompts.ts';
const number = (max: number) => z.number().finite().min(0).max(max);
const food = z.object({ name: z.string().trim().min(1).max(120).regex(/^[^\u0000-\u001f]+$/), grams: z.number().finite().positive().max(10_000), kcal: number(20_000), protein: number(2_000), carbs: number(2_000), fat: number(2_000), confidence: number(1) }).strict();
const outputFoods = z.object({ items: z.array(food).min(1).max(30) }).strict();
const textInput = z.object({ text: z.string().trim().min(1).max(2_000) }).strict();
const imageInput = z.object({ image: z.string().min(16).max(1_400_000).regex(/^data:image\/(?:jpeg|png);base64,[A-Za-z0-9+/]+=*$/) }).strict();
const exerciseInput = textInput.extend({ weightKg: z.number().finite().min(20).max(400) }).strict();
const nullable = z.number().finite().min(-1_000_000).max(1_000_000).nullable();
const reviewInput = z.object({ day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v => v >= '1900-01-01' && v <= '2100-12-31' && Number.isFinite(Date.parse(v + 'T00:00:00Z')) && new Date(v + 'T00:00:00Z').toISOString().slice(0, 10) === v), eaten: number(1_000_000), protein: number(100_000), carbs: number(100_000), fat: number(100_000), exercise: number(1_000_000), goal: number(1_000_000).nullable(), estimatedBurned: number(1_000_000).nullable(), balance: nullable, complete: z.boolean() }).strict();
export class NutritionRouteError extends Error {
  public status: number;
  public code: string;
  constructor(status: number, code: string, message: string) { super(message); this.status = status; this.code = code; }
}
export interface NutritionConfig { apiKey?: string; apiURL?: string; model?: string }
type ChatContent = string | ({ type: 'text'; text: string } | { type: 'image_url'; image_url: { url: string; detail: 'low' } })[];
interface ProviderEnvelope { choices: { message: { content: string } }[] }
const providerEnvelope = z.object({ choices: z.array(z.object({ message: z.object({ content: z.string().min(1).max(100_000) }) })).min(1).max(10) });
function settings(config: NutritionConfig): { key: string; url: string; model: string } | null {
  const key = config.apiKey?.trim(), model = config.model?.trim() || 'gpt-4o-mini';
  if (!key || key.length > 8_192 || /[\r\n]/.test(key) || model.length > 100 || /[\r\n]/.test(model)) return null;
  try { const u = new URL(config.apiURL ?? ''); if (u.protocol === 'https:' && !u.username && !u.password && !u.hash) return { key, url: u.toString(), model }; } catch { /* friendly missing configuration below */ }
  return null;
}
function parseJSON(text: string): unknown {
  const stripped = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  return JSON.parse(stripped) as unknown;
}
export function createNutritionAPI(config: NutritionConfig, transport: typeof fetch = globalThis.fetch) {
  const configured = settings(config);
  async function ask<T>(system: string, content: ChatContent, schema: z.ZodType<T>, parent?: AbortSignal): Promise<T> {
    if (!configured) throw new NutritionRouteError(503, 'ai_not_configured', 'Nutrition AI is not configured. Add AI_API_KEY and AI_API_URL on the server. Manual logging still works.');
    for (let attempt = 0; attempt < 2; attempt++) {
      let response: Response;
      try {
        response = await transport(configured.url, { method: 'POST', redirect: 'error', signal: AbortSignal.any([AbortSignal.timeout(20_000), ...(parent ? [parent] : [])]),
          headers: { Authorization: `Bearer ${configured.key}`, 'Content-Type': 'application/json', Accept: 'application/json' },
          body: JSON.stringify({ model: configured.model, temperature: 0.2, max_tokens: 1_500, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: system }, { role: 'user', content }, ...(attempt ? [{ role: 'user', content: 'The previous response was invalid. Return only valid JSON matching the exact required schema.' }] : [])] }) });
      } catch { throw new NutritionRouteError(503, 'ai_unavailable', 'The AI provider could not be reached. Try again or enter values manually.'); }
      if (!response.ok) {
        await response.body?.cancel().catch(() => {});
        if (response.status === 429) throw new NutritionRouteError(429, 'rate_limited', 'Nutrition AI is busy. Wait a moment and try again.');
        throw new NutritionRouteError(503, 'ai_unavailable', 'The AI provider could not complete this request. Check the server configuration or enter values manually.');
      }
      if (Number(response.headers.get('content-length')) > 256 * 1024) { await response.body?.cancel().catch(() => {}); throw new NutritionRouteError(503, 'ai_invalid_response', 'The AI response was too large. Try a smaller meal or enter it manually.'); }
      const chunks: Uint8Array[] = []; let bytes = 0;
      try { for await (const chunk of response.body ?? []) { bytes += chunk.length; if (bytes > 256 * 1024) throw new Error('limit'); chunks.push(chunk); } }
      catch { await response.body?.cancel().catch(() => {}); throw new NutritionRouteError(503, 'ai_unavailable', 'The AI response could not be read. Try again.'); }
      try {
        const envelope: ProviderEnvelope = providerEnvelope.parse(parseJSON(Buffer.concat(chunks).toString('utf8')));
        const item = envelope.choices[0]; if (!item) throw new Error('empty');
        return schema.parse(parseJSON(item.message.content));
      } catch { if (attempt === 1) throw new NutritionRouteError(502, 'ai_invalid_response', 'The AI could not return usable estimates. Try a clearer description or enter values manually.'); }
    }
    throw new NutritionRouteError(502, 'ai_invalid_response', 'The AI response was invalid.');
  }
  return async (path: string, body: unknown, signal?: AbortSignal): Promise<unknown> => {
    try {
      if (path === '/api/nutrition/analyze-meal') {
        const input = imageInput.parse(body), encoded = input.image.split(',')[1] ?? '', bytes = Buffer.from(encoded, 'base64');
        const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
        const png = bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
        if (bytes.length > 1_000_000 || (!jpeg && !png)) throw new NutritionRouteError(400, 'invalid_request', 'Choose a compressed JPEG or PNG meal photo below 1 MB.');
        return ask(nutritionPrompts.analyzeMeal, [{ type: 'text', text: 'Estimate the visible meal for review before saving.' }, { type: 'image_url', image_url: { url: input.image, detail: 'low' } }], outputFoods, signal);
      }
      if (path === '/api/nutrition/parse-food') return ask(nutritionPrompts.parseFood, JSON.stringify(textInput.parse(body)), outputFoods, signal);
      if (path === '/api/nutrition/estimate-exercise') return ask(nutritionPrompts.exercise, JSON.stringify(exerciseInput.parse(body)), z.object({ kcal: number(20_000) }).strict(), signal);
      if (path === '/api/nutrition/day-review') return ask(nutritionPrompts.dayReview, JSON.stringify(reviewInput.parse(body)), z.object({ summary: z.string().trim().min(1).max(420) }).strict(), signal);
      throw new NutritionRouteError(404, 'not_found', 'Nutrition route not found.');
    } catch (error: unknown) {
      if (error instanceof z.ZodError) throw new NutritionRouteError(400, 'invalid_request', 'Check the nutrition input and try again.');
      throw error;
    }
  };
}
