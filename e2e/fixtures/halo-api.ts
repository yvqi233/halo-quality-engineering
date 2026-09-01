import { expect, type APIRequestContext } from '@playwright/test';

const CONSOLE_API = '/apis/api.console.halo.run/v1alpha1';
const CONTENT_API = '/apis/content.halo.run/v1alpha1';
const PUBLIC_API = '/apis/api.content.halo.run/v1alpha1';

export interface PostRef {
  name: string;
  title: string;
  slug: string;
}

export interface CleanupFailure {
  resourceName: string;
  message: string;
}

interface PostResource {
  metadata: { name: string; version?: number };
  spec?: { title: string; slug: string; publish: boolean };
  status?: { phase?: string; permalink?: string; observedVersion?: number };
}

interface ListedPost {
  post?: PostResource;
  metadata?: PostResource['metadata'];
  spec?: PostResource['spec'];
  status?: PostResource['status'];
}

export class HaloApi {
  private readonly posts: PostRef[] = [];
  private readonly uiReservations = new Set<string>();

  constructor(
    private readonly request: APIRequestContext,
    private readonly prefix: string
  ) {}

  unique(scenarioId: string, suffix = 'post'): string {
    return `${this.prefix}-${slug(scenarioId)}-${suffix}`;
  }

  reserveUiCreation(title: string): void {
    if (!title.startsWith(this.prefix)) throw new Error('UI creation title must use the fixture scope');
    this.uiReservations.add(title);
  }

  async createDraft(owner: string, scenarioId: string): Promise<PostRef> {
    const name = this.unique(scenarioId);
    const title = `${name}-title`;
    const ref = { name, title, slug: name };
    const response = await this.request.post(`${CONSOLE_API}/posts`, {
      data: draftPayload(ref, owner)
    });
    if (!response.ok()) {
      throw new Error(`create draft returned HTTP ${response.status()}`);
    }
    if (!this.posts.some(tracked => tracked.name === ref.name)) this.posts.push(ref);
    return ref;
  }

  async trackCreatedByTitle(title: string): Promise<PostRef | undefined> {
    const response = await this.request.get(`${CONSOLE_API}/posts`, { params: { size: '100' } });
    if (!response.ok()) {
      throw new Error(`list posts returned HTTP ${response.status()}`);
    }
    const body = (await response.json()) as { items?: ListedPost[] };
    const post = body.items
      ?.map(item => item.post ?? (item as PostResource))
      .find(item => item.spec?.title === title);
    if (!post?.spec) return undefined;
    const ref = { name: post.metadata.name, title: post.spec.title, slug: post.spec.slug };
    if (!this.posts.some(tracked => tracked.name === ref.name)) this.posts.push(ref);
    return ref;
  }

  async publish(ref: PostRef): Promise<void> {
    const response = await this.request.put(`${CONSOLE_API}/posts/${encodeURIComponent(ref.name)}/publish`);
    if (!response.ok()) throw new Error(`publish post returned HTTP ${response.status()}`);
  }

  async consolePost(refOrName: PostRef | string): Promise<{ status: number; post?: PostResource }> {
    const name = typeof refOrName === 'string' ? refOrName : refOrName.name;
    const response = await this.request.get(`${CONTENT_API}/posts/${encodeURIComponent(name)}`);
    return { status: response.status(), post: response.ok() ? ((await response.json()) as PostResource) : undefined };
  }

  async publicPost(refOrName: PostRef | string): Promise<{ status: number; post?: PostResource }> {
    const name = typeof refOrName === 'string' ? refOrName : refOrName.name;
    const response = await this.request.get(`${PUBLIC_API}/posts/${encodeURIComponent(name)}`);
    return { status: response.status(), post: response.ok() ? ((await response.json()) as PostResource) : undefined };
  }

  async cleanup(): Promise<CleanupFailure[]> {
    const failures: CleanupFailure[] = [];
    if (this.uiReservations.size > 0) {
      try {
        const response = await this.request.get(`${CONSOLE_API}/posts`);
        if (!response.ok()) {
          failures.push({ resourceName: this.prefix, message: `UI sweep returned HTTP ${response.status()}` });
        } else {
          const body = (await response.json()) as { items?: ListedPost[] };
          for (const post of listedPosts(body)) {
            if (!post.spec || !post.metadata.name.startsWith(this.prefix)) continue;
            if (!this.uiReservations.has(post.spec.title)) continue;
            const ref = { name: post.metadata.name, title: post.spec.title, slug: post.spec.slug };
            if (!this.posts.some(tracked => tracked.name === ref.name)) this.posts.push(ref);
          }
        }
      } catch (error) {
        failures.push({ resourceName: this.prefix, message: `UI sweep failed: ${errorMessage(error)}` });
      }
    }
    for (const post of [...this.posts].reverse()) {
      try {
        await this.waitForSettledPost(post.name);
        const response = await this.request.delete(
          `/apis/content.halo.run/v1alpha1/posts/${encodeURIComponent(post.name)}`
        );
        if (!response.ok() && response.status() !== 404) {
          failures.push({ resourceName: post.name, message: `HTTP ${response.status()}` });
        }
      } catch (error) {
        failures.push({ resourceName: post.name, message: errorMessage(error) });
      }
    }
    this.posts.length = 0;
    this.uiReservations.clear();
    return failures;
  }

  private async waitForSettledPost(name: string): Promise<void> {
    let lastVersion: number | undefined;
    let stableObservations = 0;
    await expect.poll(async () => {
      const state = await this.consolePost(name);
      if (state.status === 404) return true;
      const version = state.post?.metadata.version;
      const observed = state.post?.status?.observedVersion;
      if (state.status !== 200 || version === undefined || observed === undefined) return false;
      if (version !== observed) {
        stableObservations = 0;
        lastVersion = version;
        return false;
      }
      stableObservations = version === lastVersion ? stableObservations + 1 : 1;
      lastVersion = version;
      return stableObservations >= 3;
    }, { timeout: 15_000, intervals: [100] }).toBe(true);
  }
}

function listedPosts(body: { items?: ListedPost[] }): PostResource[] {
  return body.items?.map(item => item.post ?? (item as PostResource)) ?? [];
}

export function draftPayload(ref: PostRef, owner: string): object {
  const html = `<p>${ref.title}</p>`;
  return {
    post: {
      apiVersion: 'content.halo.run/v1alpha1',
      kind: 'Post',
      metadata: { name: ref.name },
      spec: {
        title: ref.title,
        slug: ref.slug,
        owner,
        deleted: false,
        publish: false,
        pinned: false,
        allowComment: true,
        visible: 'PUBLIC',
        priority: 0,
        excerpt: { autoGenerate: true, raw: '' },
        categories: [],
        tags: [],
        htmlMetas: []
      }
    },
    content: { raw: html, content: html, rawType: 'HTML' }
  };
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
