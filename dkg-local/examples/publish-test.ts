/**
 * Minimal DKG publish example — NestJS service style.
 *
 * Run:
 *   npx ts-node examples/publish-test.ts
 *
 * Prerequisites:
 *   npm install dkg.js ts-node typescript
 *   docker compose up   (wait for "DKG local network is ready!")
 */

import DKG from 'dkg.js';

// ─── Config ──────────────────────────────────────────────────────────────────

const DKG_CONFIG = {
  environment: 'development',
  endpoint: 'http://localhost',
  port: 8900,
  blockchain: {
    name:         'hardhat1:31337',
    // Hardhat deterministic account #0 — safe for local use only
    publicKey:    '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    privateKey:   '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
    rpcEndpoints: ['http://localhost:8545'],
  },
} as const;

// Minimal valid JSON-LD content for a Knowledge Asset
const SAMPLE_CONTENT = {
  public: {
    '@context': 'https://schema.org',
    '@id':      'urn:example:paper-prototype-001',
    '@type':    'ScholarlyArticle',
    name:       'Prototype Knowledge Asset',
    description: 'Created by publish-test.ts for local DKG development',
  },
};

// ─── Service ─────────────────────────────────────────────────────────────────

class DkgService {
  private readonly dkg: DKG;

  constructor() {
    this.dkg = new DKG(DKG_CONFIG);
  }

  async checkNode(): Promise<void> {
    console.log('── Node info ────────────────────────────────');
    const info = await this.dkg.node.info();
    console.log(JSON.stringify(info, null, 2));
  }

  async publishAsset(): Promise<string> {
    console.log('── Publishing Knowledge Asset ───────────────');
    const result = await this.dkg.asset.create(
      SAMPLE_CONTENT,
      {
        epochsNum:          2,
        maxNumberOfRetries: 30,
        frequency:          2,
        contentType:        'all',
      },
    );

    const ual: string = result.UAL;
    console.log('UAL:', ual);
    return ual;
  }

  async getAsset(ual: string): Promise<void> {
    console.log('── Fetching Knowledge Asset ─────────────────');
    const asset = await this.dkg.asset.get(ual, { contentType: 'all' });
    console.log(JSON.stringify(asset, null, 2));
  }
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const service = new DkgService();

  await service.checkNode();

  const ual = await service.publishAsset();

  await service.getAsset(ual);

  console.log('');
  console.log('Done. UAL:', ual);
}

main().catch((err) => {
  console.error('Error:', err.message ?? err);
  process.exit(1);
});
