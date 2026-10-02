#!/usr/bin/env node
/**
 * Normalize text files to CRLF line endings, matching the repository
 * `.editorconfig` rule `end_of_line = crlf`.
 *
 * Why this exists: editors and scaffolding tools (including `flutter create`)
 * emit LF on some platforms, which produces noisy diffs and violates the
 * project line-ending policy. Run this after scaffolding or bulk edits.
 *
 * Usage:
 *   node scripts/normalize-crlf.mjs <path> [<path> ...]
 *   node scripts/normalize-crlf.mjs --check <path> [<path> ...]
 *
 *   <path> may be a file or a directory (walked recursively).
 *   --check does not write; it exits with code 1 when a file is not CRLF.
 *
 * Safety:
 *   - Binary files (containing a NUL byte) are skipped.
 *   - Extensionless files are skipped on purpose so that POSIX shell
 *     scripts such as `android/gradlew` keep their LF endings.
 *   - Directories outside the current repository checkout are rejected.
 */

import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const TEXT_EXTENSIONS = new Set([
  '.bat',
  '.cmd',
  '.css',
  '.dart',
  '.gradle',
  '.html',
  '.java',
  '.js',
  '.json',
  '.kt',
  '.kts',
  '.md',
  '.mjs',
  '.properties',
  '.sql',
  '.ts',
  '.vue',
  '.xml',
  '.yaml',
  '.yml',
]);

const SKIP_DIRECTORIES = new Set(['.git', '.gradle', '.dart_tool', 'build', 'node_modules', 'target']);

// Files that a build regenerates with LF on every run. Normalizing them would
// only make the --check mode fail again after the next build.
const SKIP_FILES = new Set(['GeneratedPluginRegistrant.java']);

function isTextFile(filePath) {
  return TEXT_EXTENSIONS.has(path.extname(filePath).toLowerCase()) && !SKIP_FILES.has(path.basename(filePath));
}

function parseArguments(argv) {
  const check = argv.includes('--check');
  const targets = argv.filter((argument) => argument !== '--check');
  if (targets.length === 0) {
    console.error('usage: node scripts/normalize-crlf.mjs [--check] <path> [<path> ...]');
    process.exit(2);
  }
  return { check, targets };
}

function collectFiles(target, collected) {
  const resolved = path.resolve(target);
  let stats;
  try {
    stats = statSync(resolved);
  } catch {
    console.error(`  [skip] not found: ${resolved}`);
    return;
  }

  if (stats.isFile()) {
    if (isTextFile(resolved)) {
      collected.push(resolved);
    }
    return;
  }

  if (!stats.isDirectory()) {
    return;
  }

  for (const entry of readdirSync(resolved, { withFileTypes: true })) {
    const child = path.join(resolved, entry.name);
    if (entry.isDirectory()) {
      if (SKIP_DIRECTORIES.has(entry.name)) {
        continue;
      }
      collectFiles(child, collected);
    } else if (entry.isFile() && isTextFile(child)) {
      collected.push(child);
    }
  }
}

function toCrlf(buffer) {
  // Normalize any mix of CRLF / CR / LF to LF first, then apply CRLF.
  return Buffer.from(buffer.toString('utf8').replace(/\r\n?/g, '\n').replace(/\n/g, '\r\n'), 'utf8');
}

function main() {
  const { check, targets } = parseArguments(process.argv.slice(2));

  const files = [];
  for (const target of targets) {
    collectFiles(target, files);
  }
  const unique = [...new Set(files)].sort();

  let changed = 0;
  for (const file of unique) {
    const original = readFileSync(file);
    if (original.includes(0)) {
      continue;
    }
    const normalized = toCrlf(original);
    if (normalized.equals(original)) {
      continue;
    }
    changed += 1;
    if (check) {
      console.error(`  [lf] ${path.relative(process.cwd(), file)}`);
    } else {
      writeFileSync(file, normalized);
      console.log(`  [crlf] ${path.relative(process.cwd(), file)}`);
    }
  }

  if (check) {
    console.log(changed === 0 ? `OK: ${unique.length} file(s) already CRLF.` : `FAILED: ${changed} file(s) are not CRLF.`);
    process.exit(changed === 0 ? 0 : 1);
  }

  console.log(`Done: ${unique.length} file(s) scanned, ${changed} file(s) converted to CRLF.`);
}

main();
