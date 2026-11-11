import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { mkdir, open, readFile, rename, lstat, unlink } from 'node:fs/promises';
import { dirname } from 'node:path';

export const hash = value => createHash('sha256').update(value).digest('hex');
const AAD = Buffer.from('whoop-local-bridge:sessions:v1');
const MAX_SESSIONS = 10;

// One process per store. Cross-process exclusion is acquired by server.mjs.
// Every mutation is serialized, encrypted, fsynced, then atomically renamed.
export class EncryptedStore {
  #records = new Map();
  #queue = Promise.resolve();
  constructor(path, key, now = Date.now) { this.path = path; this.key = key; this.now = now; }
  async init() {
    await mkdir(dirname(this.path), { recursive: true, mode: 0o700 });
    const parent = await lstat(dirname(this.path));
    if (!parent.isDirectory() || (parent.mode & 0o077)) throw new Error('Unsafe token store directory');
    try {
      const info = await lstat(this.path);
      if (!info.isFile() || (info.mode & 0o077) || info.size > 1024 * 1024) throw new Error('Unsafe token store');
      const envelope = JSON.parse(await readFile(this.path, 'utf8'));
      if (envelope.version !== 1) throw new Error('Unknown token store version');
      const decipher = createDecipheriv('aes-256-gcm', this.key, Buffer.from(envelope.iv, 'base64'));
      decipher.setAAD(AAD);
      decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
      const records = JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.data, 'base64')), decipher.final()]));
      if (!Array.isArray(records) || records.length > MAX_SESSIONS) throw new Error('Invalid token store');
      for (const [id, value] of records) {
        if (!/^[a-f0-9]{64}$/.test(id) || !Number.isFinite(value.expiresAt) || typeof value.provider?.access_token !== 'string') throw new Error('Invalid token store');
        if (value.expiresAt > this.now()) this.#records.set(id, value);
      }
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    return this;
  }
  get(id) { const value = this.#records.get(id); return value?.expiresAt > this.now() ? structuredClone(value) : undefined; }
  async #change(change) {
    const operation = this.#queue.then(async () => {
      const next = new Map(this.#records);
      for (const [id, value] of next) if (value.expiresAt <= this.now()) next.delete(id);
      const result = change(next);
      const iv = randomBytes(12);
      const cipher = createCipheriv('aes-256-gcm', this.key, iv);
      cipher.setAAD(AAD);
      const data = Buffer.concat([cipher.update(JSON.stringify([...next])), cipher.final()]);
      const envelope = JSON.stringify({ version: 1, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: data.toString('base64') });
      const temp = `${this.path}.${randomBytes(12).toString('hex')}.tmp`;
      try {
        const file = await open(temp, 'wx', 0o600);
        try { await file.writeFile(envelope); await file.sync(); } finally { await file.close(); }
        await rename(temp, this.path);
        const directory = await open(dirname(this.path), 'r');
        try { await directory.sync(); } finally { await directory.close(); }
        this.#records = next;
      } finally { await unlink(temp).catch(() => {}); }
      return result;
    });
    this.#queue = operation.catch(() => {});
    return operation;
  }
  create(id, value) { return this.#change(next => {
    if (next.size >= MAX_SESSIONS) throw new Error('Session limit reached');
    next.set(id, structuredClone(value));
  }); }
  update(id, provider) { return this.#change(next => {
    const existing = next.get(id);
    if (!existing) return false;
    next.set(id, { ...existing, provider: structuredClone(provider) });
    return true;
  }); }
  delete(id) { return this.#change(next => next.delete(id)); }
}

export async function lockStore(path) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const lock = `${path}.lock`;
  const file = await open(lock, 'wx', 0o600);
  await file.writeFile(`${process.pid}\n`);
  return async () => { await file.close(); await unlink(lock).catch(() => {}); };
}
