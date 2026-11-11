import { createServer } from 'node:http';
import { loadConfig } from './config.mjs';
import { EncryptedStore, lockStore } from './store.mjs';
import { createBridge } from './bridge.mjs';

const config = loadConfig();
let release;
try {
  let store;
  if (config.configured) {
    release = await lockStore(config.storePath);
    store = await new EncryptedStore(config.storePath, config.key).init();
  }
  const handler = createBridge({ config, store });
  const server = createServer({ requestTimeout: 15_000, headersTimeout: 10_000, maxHeaderSize: 16 * 1024 }, handler);
  server.on('close', handler.close);
  server.maxRequestsPerSocket = 100;
  server.keepAliveTimeout = 5000;
  server.listen(config.port, config.host, () => console.info(`WHOOP bridge listening; configured=${config.configured}`));
  let closing = false;
  const shutdown = () => {
    if (closing) return; closing = true;
    server.close(async () => { await release?.(); process.exit(0); });
    server.closeIdleConnections();
  };
  process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
  server.on('error', async () => { console.error('Bridge listener failed.'); await release?.(); process.exit(1); });
} catch {
  console.error('Bridge startup failed. Check server-only configuration, private storage permissions, encryption key and exclusive store lock.');
  await release?.(); process.exitCode = 1;
}
