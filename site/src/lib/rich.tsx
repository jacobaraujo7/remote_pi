import type { ReactNode } from "react";

/* Inline tags shared by every message that carries `<code>`, `<strong>` or
   `<em>`. Pass as `t.rich(key, { ...rich, link: (c) => <a>{c}</a> })`. */
export const rich = {
  code: (chunks: ReactNode) => <code>{chunks}</code>,
  strong: (chunks: ReactNode) => <strong>{chunks}</strong>,
  em: (chunks: ReactNode) => <em>{chunks}</em>,
  b: (chunks: ReactNode) => <b>{chunks}</b>,
};
