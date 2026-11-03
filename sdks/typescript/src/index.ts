/**
 * Nomad Browser TypeScript SDK
 * High-speed native macOS agentic browser driver and CDP bridge.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

export interface NomadOptions {
  port?: number;
  host?: string;
  token?: string;
}

export class Nomad {
  readonly port: number;
  readonly host: string;
  readonly baseUrl: string;
  readonly cdpUrl: string;
  readonly token: string;

  constructor(options: NomadOptions = {}) {
    this.port = options.port ?? 9222;
    this.host = options.host ?? '127.0.0.1';
    this.baseUrl = `http://${this.host}:${this.port}`;
    this.cdpUrl = this.baseUrl;
    this.token = options.token ?? Nomad.loadToken();
  }

  static loadToken(): string {
    if (process.env.NOMAD_TOKEN) return process.env.NOMAD_TOKEN.trim();
    const tokenFile = path.join(os.homedir(), '.nomad', 'agent-token');
    try {
      if (fs.existsSync(tokenFile)) {
        return fs.readFileSync(tokenFile, 'utf8').trim();
      }
    } catch {
      // fallback
    }
    return '';
  }

  private async request<T = any>(method: string, endpoint: string, body?: any): Promise<T> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const res = await fetch(`${this.baseUrl}${endpoint}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Nomad HTTP ${res.status}: ${errText}`);
    }

    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
      return (await res.json()) as T;
    }
    return (await res.text()) as any;
  }

  async status() {
    return this.request('GET', '/status');
  }

  async cdpVersion() {
    return this.request('GET', '/json/version');
  }

  async tabs() {
    const res = await this.request('GET', '/tabs');
    return res.tabs || [];
  }

  async newTab(url?: string) {
    return this.request('POST', '/tabs/new', url ? { url } : {});
  }

  async navigate(url: string) {
    return this.request('POST', '/navigate', { url });
  }

  async snapshot(mode: 'text' | 'json' = 'text', limit: number = 50) {
    return this.request('GET', `/snapshot?mode=${mode}&limit=${limit}`);
  }

  async click(target: string, native: boolean = true) {
    return this.request('POST', '/action', { action: 'click', target, native });
  }

  async type(target: string, text: string, submit: boolean = false, native: boolean = true) {
    return this.request('POST', '/action', { action: 'type', target, text, submit, native });
  }

  async evaluate(expression: string) {
    const res = await this.request('POST', '/evaluate', { expression });
    return res.result;
  }
}

