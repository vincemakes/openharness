/**
 * Snapshot command — accessibility tree with ref-based element selection
 */

import type { Page, Locator } from 'playwright';
import type { BrowserManager, RefEntry } from './browser-manager';
import * as Diff from 'diff';
import { TEMP_DIR, isPathWithin } from './platform';

const INTERACTIVE_ROLES = new Set([
  'button', 'link', 'textbox', 'checkbox', 'radio', 'combobox',
  'listbox', 'menuitem', 'menuitemcheckbox', 'menuitemradio',
  'option', 'searchbox', 'slider', 'spinbutton', 'switch', 'tab',
  'treeitem',
]);

interface SnapshotOptions {
  interactive?: boolean;
  compact?: boolean;
  depth?: number;
  selector?: string;
  diff?: boolean;
  annotate?: boolean;
  outputPath?: string;
  cursorInteractive?: boolean;
}

export const SNAPSHOT_FLAGS: Array<{
  short: string;
  long: string;
  description: string;
  takesValue?: boolean;
  valueHint?: string;
  optionKey: keyof SnapshotOptions;
}> = [
  { short: '-i', long: '--interactive', description: 'Interactive elements only (buttons, links, inputs) with @e refs', optionKey: 'interactive' },
  { short: '-c', long: '--compact', description: 'Compact (no empty structural nodes)', optionKey: 'compact' },
  { short: '-d', long: '--depth', description: 'Limit tree depth (0 = root only, default: unlimited)', takesValue: true, valueHint: '<N>', optionKey: 'depth' },
  { short: '-s', long: '--selector', description: 'Scope to CSS selector', takesValue: true, valueHint: '<sel>', optionKey: 'selector' },
  { short: '-D', long: '--diff', description: 'Unified diff against previous snapshot (first call stores baseline)', optionKey: 'diff' },
  { short: '-a', long: '--annotate', description: 'Annotated screenshot with red overlay boxes and ref labels', optionKey: 'annotate' },
  { short: '-o', long: '--output', description: 'Output path for annotated screenshot (default: <temp>/browse-annotated.png)', takesValue: true, valueHint: '<path>', optionKey: 'outputPath' },
  { short: '-C', long: '--cursor-interactive', description: 'Cursor-interactive elements (@c refs — divs with pointer, onclick)', optionKey: 'cursorInteractive' },
];

interface ParsedNode {
  indent: number;
  role: string;
  name: string | null;
  props: string;
  children: string;
  rawLine: string;
}

export function parseSnapshotArgs(args: string[]): SnapshotOptions {
  const opts: SnapshotOptions = {};
  for (let i = 0; i < args.length; i++) {
    const flag = SNAPSHOT_FLAGS.find(f => f.short === args[i] || f.long === args[i]);
    if (!flag) throw new Error(`Unknown snapshot flag: ${args[i]}`);
    if (flag.takesValue) {
      const value = args[++i];
      if (!value) throw new Error(`Usage: snapshot ${flag.short} <value>`);
      if (flag.optionKey === 'depth') {
        (opts as any)[flag.optionKey] = parseInt(value, 10);
        if (isNaN(opts.depth!)) throw new Error('Usage: snapshot -d <number>');
      } else {
        (opts as any)[flag.optionKey] = value;
      }
    } else {
      (opts as any)[flag.optionKey] = true;
    }
  }
  return opts;
}

function parseLine(line: string): ParsedNode | null {
  const match = line.match(/^(\s*)-\s+(\w+)(?:\s+"([^"]*)")?(?:\s+(\[.*?\]))?\s*(?::\s*(.*))?$/);
  if (!match) {
    return null;
  }
  return {
    indent: match[1].length,
    role: match[2],
    name: match[3] ?? null,
    props: match[4] || '',
    children: match[5]?.trim() || '',
    rawLine: line,
  };
}

export async function handleSnapshot(
  args: string[],
  bm: BrowserManager
): Promise<string> {
  const opts = parseSnapshotArgs(args);
  const page = bm.getPage();

  let rootLocator: Locator;
  if (opts.selector) {
    rootLocator = page.locator(opts.selector);
    const count = await rootLocator.count();
    if (count === 0) throw new Error(`Selector not found: ${opts.selector}`);
  } else {
    rootLocator = page.locator('body');
  }

  const ariaText = await rootLocator.ariaSnapshot();
  if (!ariaText || ariaText.trim().length === 0) {
    bm.setRefMap(new Map());
    return '(no accessible elements found)';
  }

  const lines = ariaText.split('\n');
  const refMap = new Map<string, RefEntry>();
  const output: string[] = [];
  let refCounter = 1;

  const roleNameCounts = new Map<string, number>();
  const roleNameSeen = new Map<string, number>();

  for (const line of lines) {
    const node = parseLine(line);
    if (!node) continue;
    const key = `${node.role}:${node.name || ''}`;
    roleNameCounts.set(key, (roleNameCounts.get(key) || 0) + 1);
  }

  for (const line of lines) {
    const node = parseLine(line);
    if (!node) continue;

    const depth = Math.floor(node.indent / 2);
    const isInteractive = INTERACTIVE_ROLES.has(node.role);

    if (opts.depth !== undefined && depth > opts.depth) continue;

    if (opts.interactive && !isInteractive) {
      const key = `${node.role}:${node.name || ''}`;
      roleNameSeen.set(key, (roleNameSeen.get(key) || 0) + 1);
      continue;
    }

    if (opts.compact && !isInteractive && !node.name && !node.children) continue;

    const ref = `e${refCounter++}`;
    const indent = '  '.repeat(depth);

    const key = `${node.role}:${node.name || ''}`;
    const seenIndex = roleNameSeen.get(key) || 0;
    roleNameSeen.set(key, seenIndex + 1);
    const totalCount = roleNameCounts.get(key) || 1;

    let locator: Locator;
    if (opts.selector) {
      locator = page.locator(opts.selector).getByRole(node.role as any, {
        name: node.name || undefined,
      });
    } else {
      locator = page.getByRole(node.role as any, {
        name: node.name || undefined,
      });
    }

    if (totalCount > 1) {
      locator = locator.nth(seenIndex);
    }

    refMap.set(ref, { locator, role: node.role, name: node.name || '' });

    let outputLine = `${indent}@${ref} [${node.role}]`;
    if (node.name) outputLine += ` "${node.name}"`;
    if (node.props) outputLine += ` ${node.props}`;
    if (node.children) outputLine += `: ${node.children}`;

    output.push(outputLine);
  }

  // ─── Cursor-interactive scan (-C) ─────────────────────────
  if (opts.cursorInteractive) {
    try {
      const cursorElements = await page.evaluate(() => {
        const STANDARD_INTERACTIVE = new Set([
          'A', 'BUTTON', 'INPUT', 'SELECT', 'TEXTAREA', 'SUMMARY', 'DETAILS',
        ]);

        const results: Array<{ selector: string; text: string; reason: string }> = [];
        const allElements = document.querySelectorAll('*');

        for (const el of allElements) {
          if (STANDARD_INTERACTIVE.has(el.tagName)) continue;
          if (!(el as HTMLElement).offsetParent && el.tagName !== 'BODY') continue;

          const style = getComputedStyle(el);
          const hasCursorPointer = style.cursor === 'pointer';
          const hasOnclick = el.hasAttribute('onclick');
          const hasTabindex = el.hasAttribute('tabindex') && parseInt(el.getAttribute('tabindex')!, 10) >= 0;
          const hasRole = el.hasAttribute('role');

          if (!hasCursorPointer && !hasOnclick && !hasTabindex) continue;
          if (hasRole) continue;

          const parts: string[] = [];
          let current: Element | null = el;
          while (current && current !== document.documentElement) {
            const parent = current.parentElement;
            if (!parent) break;
            const siblings = [...parent.children];
            const index = siblings.indexOf(current) + 1;
            parts.unshift(`${current.tagName.toLowerCase()}:nth-child(${index})`);
            current = parent;
          }
          const selector = parts.join(' > ');

          const text = (el as HTMLElement).innerText?.trim().slice(0, 80) || el.tagName.toLowerCase();
          const reasons: string[] = [];
          if (hasCursorPointer) reasons.push('cursor:pointer');
          if (hasOnclick) reasons.push('onclick');
          if (hasTabindex) reasons.push(`tabindex=${el.getAttribute('tabindex')}`);

          results.push({ selector, text, reason: reasons.join(', ') });
        }
        return results;
      });

      if (cursorElements.length > 0) {
        output.push('');
        output.push('── cursor-interactive (not in ARIA tree) ──');
        let cRefCounter = 1;
        for (const elem of cursorElements) {
          const ref = `c${cRefCounter++}`;
          const locator = page.locator(elem.selector);
          refMap.set(ref, { locator, role: 'cursor-interactive', name: elem.text });
          output.push(`@${ref} [${elem.reason}] "${elem.text}"`);
        }
      }
    } catch {
      output.push('');
      output.push('(cursor scan failed — CSP restriction)');
    }
  }

  bm.setRefMap(refMap);

  if (output.length === 0) {
    return '(no interactive elements found)';
  }

  const snapshotText = output.join('\n');

  // ─── Annotated screenshot (-a) ────────────────────────────
  if (opts.annotate) {
    const screenshotPath = opts.outputPath || `${TEMP_DIR}/browse-annotated.png`;
    const resolvedPath = require('path').resolve(screenshotPath);
    const safeDirs = [TEMP_DIR, process.cwd()];
    if (!safeDirs.some((dir: string) => isPathWithin(resolvedPath, dir))) {
      throw new Error(`Path must be within: ${safeDirs.join(', ')}`);
    }
    try {
      const boxes: Array<{ ref: string; box: { x: number; y: number; width: number; height: number } }> = [];
      for (const [ref, entry] of refMap) {
        try {
          const box = await entry.locator.boundingBox({ timeout: 1000 });
          if (box) {
            boxes.push({ ref: `@${ref}`, box });
          }
        } catch {}
      }

      await page.evaluate((boxes) => {
        for (const { ref, box } of boxes) {
          const overlay = document.createElement('div');
          overlay.className = '__browse_annotation__';
          overlay.style.cssText = `
            position: absolute; top: ${box.y}px; left: ${box.x}px;
            width: ${box.width}px; height: ${box.height}px;
            border: 2px solid red; background: rgba(255,0,0,0.1);
            pointer-events: none; z-index: 99999;
            font-size: 10px; color: red; font-weight: bold;
          `;
          const label = document.createElement('span');
          label.textContent = ref;
          label.style.cssText = 'position: absolute; top: -14px; left: 0; background: red; color: white; padding: 0 3px; font-size: 10px;';
          overlay.appendChild(label);
          document.body.appendChild(overlay);
        }
      }, boxes);

      await page.screenshot({ path: screenshotPath, fullPage: true });

      await page.evaluate(() => {
        document.querySelectorAll('.__browse_annotation__').forEach(el => el.remove());
      });

      output.push('');
      output.push(`[annotated screenshot: ${screenshotPath}]`);
    } catch {
      try {
        await page.evaluate(() => {
          document.querySelectorAll('.__browse_annotation__').forEach(el => el.remove());
        });
      } catch {}
    }
  }

  // ─── Diff mode (-D) ───────────────────────────────────────
  if (opts.diff) {
    const lastSnapshot = bm.getLastSnapshot();
    if (!lastSnapshot) {
      bm.setLastSnapshot(snapshotText);
      return snapshotText + '\n\n(no previous snapshot to diff against — this snapshot stored as baseline)';
    }

    const changes = Diff.diffLines(lastSnapshot, snapshotText);
    const diffOutput: string[] = ['--- previous snapshot', '+++ current snapshot', ''];

    for (const part of changes) {
      const prefix = part.added ? '+' : part.removed ? '-' : ' ';
      const diffLines = part.value.split('\n').filter(l => l.length > 0);
      for (const line of diffLines) {
        diffOutput.push(`${prefix} ${line}`);
      }
    }

    bm.setLastSnapshot(snapshotText);
    return diffOutput.join('\n');
  }

  bm.setLastSnapshot(snapshotText);

  return output.join('\n');
}
