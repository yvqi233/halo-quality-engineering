import type { APIRequestContext } from '@playwright/test';

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
  metadata: { name: string };
  spec?: { title: string; slug: string; publish: boolean };
  status?: { phase?: string; permalink?: string };
}

interface ListedPost {
  post?: PostResource;
  metadata?: PostResource['metadata'];
  spec?: PostResource['spec'];
  status?: PostResource['status'];
}

export class HaloApi {
  private readonly posts: PostRef[] = [];

  constructor(
    private readonly request: APIRequestContext,
    private readonly prefix: string
  ) {}

  unique(scenarioId: string, suffix = 'post'): string {
    return `${this.prefix}-${slug(scenarioId)}-${suffix}`;
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
    for (const post of [...this.posts].reverse()) {
      try {
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
    return failures;
  }
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
