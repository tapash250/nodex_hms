// deno-lint-ignore-file no-unused-vars
// Unit tests for the mutation-handler's ledger invariants.
//
// These cover the two fields whose correctness is invisible at runtime:
// payload_digest, which attests the contents and must therefore be
// deterministic and order-independent, and device_id, which records provenance
// and must therefore never be inferred when the caller did not supply one.
//
// The digest's value depends on canonicalJson sorting object keys recursively;
// without that, a client that reorders its payload fields would produce a
// different digest for the same mutation, and the ledger's tamper-evidence
// would be noise.
//
// Run with:  deno test --allow-none supabase/functions/mutation-handler/

import { assert, assertEquals, assertNotEquals, assertStringIncludes } from 'jsr:@std/assert@^1'
import { canonicalJson, resolveDeviceId, sha256Hex } from './index.ts'

const UUID_A = '11111111-1111-1111-1111-111111111111'
const UUID_B = '22222222-2222-2222-2222-222222222222'

Deno.test('sha256Hex produces a lowercase 64-char hex digest', async () => {
  const digest = await sha256Hex('abc')
  assertEquals(digest, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
  assertEquals(digest.length, 64)
  assert(/^[0-9a-f]{64}$/.test(digest))
})

Deno.test('canonicalJson sorts object keys recursively', () => {
  assertEquals(
    canonicalJson({ b: 1, a: { d: 2, c: 3 } }),
    '{"a":{"c":3,"d":2},"b":1}',
  )
})

Deno.test('the digest does not depend on payload key order', async () => {
  const reordered = canonicalJson({
    table: 't',
    operation: 'upsert',
    id: 'x',
    data: { y: 2, z: 1 },
  })
  const original = canonicalJson({
    id: 'x',
    operation: 'upsert',
    table: 't',
    data: { z: 1, y: 2 },
  })
  assertEquals(await sha256Hex(reordered), await sha256Hex(original))
})

Deno.test('any change to the payload changes the digest', async () => {
  const before = canonicalJson({ id: 'x', data: { status: 'ordered' } })
  const after = canonicalJson({ id: 'x', data: { status: 'verified' } })
  assertNotEquals(await sha256Hex(before), await sha256Hex(after))
})

Deno.test('arrays keep their order; only object keys sort', () => {
  assertEquals(canonicalJson([3, 1, 2]), '[3,1,2]')
})

Deno.test('null and nested empties survive canonicalization', () => {
  assertEquals(canonicalJson({ a: null }), '{"a":null}')
  assertEquals(canonicalJson({ a: {} }), '{"a":{}}')
})

Deno.test('the digest distinguishes the idempotency key from the payload', async () => {
  // A regression to echoing the key as the digest would make these equal.
  const key = '7-1'
  const payload = canonicalJson({ id: 'x', idempotency_key: key, data: { z: 1 } })
  assertNotEquals(await sha256Hex(payload), key)
})

// --- resolveDeviceId -------------------------------------------------------

function requestWith(headers: Record<string, string> = {}, method = 'POST'): Request {
  return new Request('https://x.test/', { method, headers })
}

Deno.test('the body device id wins over the header', () => {
  const req = requestWith({ 'x-device-id': UUID_B })
  assertEquals(resolveDeviceId(req, { device_id: UUID_A }), UUID_A)
})

Deno.test('the header is the fallback when the body omits it', () => {
  const req = requestWith({ 'x-device-id': UUID_B })
  assertEquals(resolveDeviceId(req, {}), UUID_B)
})

Deno.test('a non-uuid body value is ignored rather than trusted', () => {
  const req = requestWith({ 'x-device-id': UUID_B })
  // Not a uuid, so the header is used instead.
  assertEquals(resolveDeviceId(req, { device_id: 'not-a-uuid' }), UUID_B)
})

Deno.test('a blank header falls back to null, never a guess', () => {
  const req = requestWith()
  assertEquals(resolveDeviceId(req, {}), null)
})

Deno.test('a malformed header is not trusted', () => {
  const req = requestWith({ 'x-device-id': 'dev-1' })
  assertEquals(resolveDeviceId(req, {}), null)
})

Deno.test('an unenrolled device yields null rather than a placeholder', () => {
  // This is the Phase-2 behaviour: identity rests on
  // (tenant_id, idempotency_key) plus actor, not on a fabricated device.
  const req = requestWith()
  assertEquals(resolveDeviceId(req, {}), null)
  assertEquals(resolveDeviceId(req, { device_id: null }), null)
})
