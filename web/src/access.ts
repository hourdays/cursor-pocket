/** Production builds can set VITE_ALLOWED_EMAIL to lock this deploy to one Cursor account. */
const allowedEmail = import.meta.env.VITE_ALLOWED_EMAIL?.trim().toLowerCase();

export class AccessDeniedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AccessDeniedError";
  }
}

export function isAccessControlEnabled(): boolean {
  return Boolean(allowedEmail);
}

export function allowedEmailHint(): string | null {
  return import.meta.env.VITE_ALLOWED_EMAIL?.trim() ?? null;
}

export function assertEmailAllowed(email: string | undefined): void {
  if (!allowedEmail) {
    return;
  }
  if (!email || email.trim().toLowerCase() !== allowedEmail) {
    throw new AccessDeniedError(
      `This Pocket site is private. Use the Cursor API key for ${import.meta.env.VITE_ALLOWED_EMAIL}.`
    );
  }
}

export function isAccessDeniedError(error: unknown): error is AccessDeniedError {
  return error instanceof AccessDeniedError;
}
