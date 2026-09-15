import { NextResponse } from 'next/server';

/**
 * Passwordless public sign-in is intentionally disabled. Organization
 * invitations still use a one-time secure email activation link, after which
 * every role (company, technician, customer) signs in with email + password.
 */
export async function POST() {
  return NextResponse.json(
    { error: 'Passwordless sign-in is disabled. Use your email and password, or reset your password.' },
    { status: 410 },
  );
}
