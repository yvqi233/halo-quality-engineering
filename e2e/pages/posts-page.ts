import type { Page } from '@playwright/test';

export class PostsPage {
  constructor(
    private readonly page: Page,
    private readonly surface: 'console' | 'user-center' = 'console'
  ) {}

  async open(): Promise<void> {
    await this.page.goto(this.surface === 'console' ? '/console' : '/uc');
    await this.page.getByRole('listitem').filter({ hasText: /^Posts$/ }).click();
  }

  async createDraft(title: string): Promise<void> {
    await this.page.getByRole('button', { name: this.surface === 'console' ? 'New Post' : 'New' }).click();
    await this.page.getByRole('textbox', { name: 'Please enter the title' }).fill(title);
    await this.page.getByRole('button', { name: 'Save' }).click();
  }

  async publish(title: string): Promise<void> {
    await this.page.getByText(title, { exact: true }).click();
    await this.page.getByRole('button', { name: 'Publish' }).click();
  }

  async unpublish(title: string): Promise<void> {
    await this.page.getByText(title, { exact: true }).click();
    await this.page.getByRole('button', { name: 'Settings' }).click();
    await this.page.getByRole('button', { name: 'Cancel publish' }).click();
  }
}
