import { NextResponse } from 'next/server'

export async function GET() {
  return NextResponse.json({
    terminalEnabled: process.env.AGENTOS_TERMINAL_ENABLED === 'true',
  })
}
