import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'

export async function GET() {
  return NextResponse.json({
    terminalEnabled: process.env.AGENTOS_TERMINAL_ENABLED === 'true',
  })
}
