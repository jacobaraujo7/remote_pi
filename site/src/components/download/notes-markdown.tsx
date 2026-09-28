import { Fragment, type ReactNode } from "react";

/* ===========================================================
   Release notes renderer
   `manifest.notes` is the version's CHANGELOG section in markdown, produced
   by the release CI and served in latest.json. The publisher clips it to the
   first 20 non-empty lines, so the input is routinely TRUNCATED: a list can
   end mid-item and an emphasis span can never be closed. Everything here is
   written to degrade into plain text instead of throwing, and no raw HTML is
   ever interpreted (the notes are external input).

   Deliberately dependency-free: the subset below is all the CI emits
   (headings, bullet lists, bold, inline code, links, paragraphs), and the
   site ships no markdown library.
   =========================================================== */

/** Inline spans: `code`, **bold**, *italic*, [text](url). */
function renderInline(text: string, keyPrefix: string): ReactNode[] {
  const pattern =
    /(`[^`]+`)|(\*\*[^*]+\*\*)|(\*[^*\n]+\*)|(\[[^\]]+\]\((https?:\/\/[^\s)]+)\))/g;
  const out: ReactNode[] = [];
  let last = 0;
  let match: RegExpExecArray | null;
  let i = 0;

  while ((match = pattern.exec(text)) !== null) {
    if (match.index > last) out.push(text.slice(last, match.index));
    const token = match[0];
    const key = `${keyPrefix}-i${i++}`;

    if (token.startsWith("`")) {
      out.push(<code key={key}>{token.slice(1, -1)}</code>);
    } else if (token.startsWith("**")) {
      out.push(<strong key={key}>{token.slice(2, -2)}</strong>);
    } else if (token.startsWith("[")) {
      const label = token.slice(1, token.indexOf("]"));
      out.push(
        <a key={key} href={match[5]} target="_blank" rel="noopener noreferrer">
          {label}
        </a>,
      );
    } else {
      out.push(<em key={key}>{token.slice(1, -1)}</em>);
    }
    last = match.index + token.length;
  }

  /* Anything after the last complete token, including a dangling `**` from a
     clipped line, goes through as literal text. */
  if (last < text.length) out.push(text.slice(last));
  return out.map((node, n) =>
    typeof node === "string" ? <Fragment key={`${keyPrefix}-t${n}`}>{node}</Fragment> : node,
  );
}

type Block =
  | { kind: "heading"; level: 3 | 4; text: string }
  | { kind: "list"; items: string[] }
  | { kind: "para"; text: string };

/** Group lines into blocks. Continuation lines of a bullet join their item. */
function parseBlocks(source: string): Block[] {
  const lines = source.replace(/\r\n/g, "\n").split("\n");
  const blocks: Block[] = [];
  let list: string[] | null = null;
  let para: string[] | null = null;

  const flushPara = () => {
    if (para && para.length > 0) blocks.push({ kind: "para", text: para.join(" ") });
    para = null;
  };
  const flushList = () => {
    if (list && list.length > 0) blocks.push({ kind: "list", items: list });
    list = null;
  };

  for (const raw of lines) {
    const line = raw.trimEnd();

    if (line.trim() === "") {
      flushPara();
      flushList();
      continue;
    }

    const heading = /^(#{1,6})\s+(.*)$/.exec(line);
    if (heading) {
      flushPara();
      flushList();
      blocks.push({
        kind: "heading",
        level: heading[1].length <= 3 ? 3 : 4,
        text: heading[2],
      });
      continue;
    }

    const bullet = /^\s*[-*+]\s+(.*)$/.exec(line);
    if (bullet) {
      flushPara();
      if (!list) list = [];
      list.push(bullet[1]);
      continue;
    }

    /* Indented line right under a bullet: same item, wrapped in the source. */
    if (list && /^\s+\S/.test(raw)) {
      list[list.length - 1] = `${list[list.length - 1]} ${line.trim()}`;
      continue;
    }

    flushList();
    if (!para) para = [];
    para.push(line.trim());
  }

  flushPara();
  flushList();
  return blocks;
}

/**
 * Render a version's release notes. Returns null for empty input so the
 * caller can skip the whole card.
 */
export function NotesMarkdown({ source }: { source: string }) {
  const blocks = parseBlocks(source ?? "");
  if (blocks.length === 0) return null;

  return (
    <div className="rn-md">
      {blocks.map((block, i) => {
        const key = `b${i}`;
        if (block.kind === "heading") {
          return block.level === 3 ? (
            <h4 key={key}>{renderInline(block.text, key)}</h4>
          ) : (
            <h5 key={key}>{renderInline(block.text, key)}</h5>
          );
        }
        if (block.kind === "list") {
          return (
            <ul key={key}>
              {block.items.map((item, n) => (
                <li key={`${key}-${n}`}>{renderInline(item, `${key}-${n}`)}</li>
              ))}
            </ul>
          );
        }
        return <p key={key}>{renderInline(block.text, key)}</p>;
      })}
    </div>
  );
}
