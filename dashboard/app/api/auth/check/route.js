import { NextResponse } from 'next/server'
import { verifySession } from '../../../lib/auth'

export async function GET(request) {
  const authenticated = verifySession(request)
  return NextResponse.json({ authenticated })
}
