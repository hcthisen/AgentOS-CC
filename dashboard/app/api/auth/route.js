import { NextResponse } from 'next/server'
import { createHash } from 'crypto'

export async function POST(request) {
  const { password } = await request.json()
  if (!password) {
    return NextResponse.json({ error: 'Password required' }, { status: 400 })
  }

  const hash = createHash('sha256').update(password).digest('hex')
  const expected = process.env.DASHBOARD_PASSWORD_HASH

  if (hash !== expected) {
    return NextResponse.json({ error: 'Invalid password' }, { status: 401 })
  }

  // Create session token
  const sessionToken = createHash('sha256')
    .update(hash + (process.env.JWT_SECRET || ''))
    .digest('hex')

  const secureCookies = (process.env.AGENTOS_SECURE_COOKIES ?? (process.env.NODE_ENV === 'production' ? 'true' : 'false')) === 'true'
  const response = NextResponse.json({ ok: true })
  response.cookies.set('dashboard_session', sessionToken, {
    httpOnly: true,
    secure: secureCookies,
    sameSite: 'strict',
    maxAge: 7 * 24 * 60 * 60, // 7 days
    path: '/',
  })

  return response
}
