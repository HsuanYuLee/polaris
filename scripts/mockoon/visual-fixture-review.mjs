#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'fs'

function usage() {
  console.error('Usage: visual-fixture-review.mjs --manifest PATH [--set-reviewed true|false] [--assert-reviewed true|false]')
}

let manifestPath = ''
let setReviewed = null
let assertReviewed = null

for (let index = 2; index < process.argv.length; index += 1) {
  const arg = process.argv[index]
  if (arg === '--manifest') {
    manifestPath = process.argv[index + 1] || ''
    index += 1
  } else if (arg === '--set-reviewed') {
    setReviewed = process.argv[index + 1]
    index += 1
  } else if (arg === '--assert-reviewed') {
    assertReviewed = process.argv[index + 1]
    index += 1
  } else if (arg === '-h' || arg === '--help') {
    usage()
    process.exit(0)
  } else {
    console.error(`visual-fixture-review: unknown arg: ${arg}`)
    usage()
    process.exit(2)
  }
}

if (!manifestPath) {
  usage()
  process.exit(2)
}

function parseBool(value, label) {
  if (value === null) return null
  if (value === 'true') return true
  if (value === 'false') return false
  throw new Error(`${label} must be true or false`)
}

const nextReviewed = parseBool(setReviewed, '--set-reviewed')
const expectedReviewed = parseBool(assertReviewed, '--assert-reviewed')
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))

if (manifest.fixture_kind !== 'polaris-visual-page-fixture') {
  throw new Error(`unsupported fixture_kind: ${manifest.fixture_kind || '<missing>'}`)
}
if (!Array.isArray(manifest.pages) || manifest.pages.length === 0) {
  throw new Error('manifest.pages must be a non-empty array')
}

if (nextReviewed !== null) {
  manifest.reviewed = nextReviewed
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
}

if (expectedReviewed !== null && manifest.reviewed !== expectedReviewed) {
  throw new Error(`expected reviewed=${expectedReviewed}, got ${manifest.reviewed}`)
}

console.log(`PASS: visual fixture manifest reviewed=${manifest.reviewed === true}`)
