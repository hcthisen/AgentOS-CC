import { createHash } from 'crypto'

export function verifySession(request) {
  const cookie = request.cookies.get('dashboard_session')
  if (!cookie) return false
  const expected = createHash('sha256')
    .update((process.env.DASHBOARD_PASSWORD_HASH || '') + (process.env.JWT_SECRET || ''))
    .digest('hex')
  return cookie.value === expected
}

export async function supabaseGet(endpoint, useServiceRole = false) {
  const key = useServiceRole ? process.env.SUPABASE_SERVICE_ROLE_KEY : process.env.SUPABASE_ANON_KEY
  const url = `${process.env.SUPABASE_URL}/${endpoint}`
  const res = await fetch(url, {
    headers: {
      'apikey': key,
      'Authorization': `Bearer ${key}`,
    },
    cache: 'no-store',
  })
  if (!res.ok) return null
  return res.json()
}

export async function supabasePost(endpoint, data, useServiceRole = true) {
  const key = useServiceRole ? process.env.SUPABASE_SERVICE_ROLE_KEY : process.env.SUPABASE_ANON_KEY
  const url = `${process.env.SUPABASE_URL}/${endpoint}`
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'apikey': key,
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=representation',
    },
    body: JSON.stringify(data),
  })
  if (!res.ok) return null
  return res.json()
}

export async function supabaseDelete(endpoint, useServiceRole = true) {
  const key = useServiceRole ? process.env.SUPABASE_SERVICE_ROLE_KEY : process.env.SUPABASE_ANON_KEY
  const url = `${process.env.SUPABASE_URL}/${endpoint}`
  const res = await fetch(url, {
    method: 'DELETE',
    headers: {
      'apikey': key,
      'Authorization': `Bearer ${key}`,
    },
  })
  return res.ok
}
