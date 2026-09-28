"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { LogoMark, IconDownload } from "@/components/landing/icons";

/* The site carries two products. Cockpit owns the root, Remote Pi lives under
   /remote-pi, and the nav swaps wholesale so a visitor always sees the links of
   the product they are reading about, plus a way back to the other one. */
type NavLink = { href: string; label: string };

const COCKPIT_LINKS: NavLink[] = [
  { href: "/docs", label: "Docs" },
  { href: "/tutorials", label: "Tutorials" },
  { href: "/download", label: "Download" },
  { href: "/remote-pi", label: "Remote Pi" },
];

const REMOTE_PI_LINKS: NavLink[] = [
  { href: "/remote-pi/docs", label: "Docs" },
  { href: "/remote-pi/tutorials", label: "Tutorials" },
  { href: "/remote-pi/download", label: "Download" },
  { href: "/remote-pi/why", label: "Why Pi" },
];

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

function HamburgerIcon({ open }: { open: boolean }) {
  return (
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      aria-hidden="true"
    >
      <line
        x1="4"
        y1="6"
        x2="20"
        y2="6"
        style={{
          transform: open ? "rotate(45deg) translate(0, 6px)" : "none",
          transformOrigin: "center",
          transition: "transform 0.25s ease",
        }}
      />
      <line
        x1="4"
        y1="12"
        x2="20"
        y2="12"
        style={{
          opacity: open ? 0 : 1,
          transition: "opacity 0.2s ease",
        }}
      />
      <line
        x1="4"
        y1="18"
        x2="20"
        y2="18"
        style={{
          transform: open ? "rotate(-45deg) translate(0, -6px)" : "none",
          transformOrigin: "center",
          transition: "transform 0.25s ease",
        }}
      />
    </svg>
  );
}

export function SiteHeader() {
  const [menuOpen, setMenuOpen] = useState(false);
  const pathname = usePathname() ?? "/";
  const onRemotePi = pathname === "/remote-pi" || pathname.startsWith("/remote-pi/");

  const links = onRemotePi ? REMOTE_PI_LINKS : COCKPIT_LINKS;
  const home = onRemotePi ? "/remote-pi" : "/";
  const brand = onRemotePi ? "Remote Pi" : "Cockpit";
  const cta = onRemotePi
    ? { href: "/remote-pi#install", label: "Install" }
    : { href: "/download", label: "Download" };

  return (
    <header className="nav">
      {onRemotePi ? (
        <div className="sibling-bar">
          <div className="wrap sibling-bar-inner">
            <span>
              You are reading about <strong>Remote Pi</strong>, the sibling
              project: agents on your phone, 24/7 daemons and the mesh.
            </span>
            <Link href="/">Back to Cockpit</Link>
          </div>
        </div>
      ) : null}
      <div className="wrap nav-inner">
        <Link className="brand" href={home} aria-label={`${brand} home`}>
          <span className="mark">
            <LogoMark />
          </span>
          {brand}
        </Link>

        {/* Desktop links */}
        <nav className="nav-links" aria-label="Primary">
          {links.map((l) => (
            <Link className="lnk" href={l.href} key={l.href}>
              {l.label}
            </Link>
          ))}
          <a
            className="lnk"
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub
          </a>
          <Link className="nav-cta" href={cta.href}>
            <IconDownload /> {cta.label}
          </Link>
        </nav>

        {/* Mobile menu toggle */}
        <button
          className="nav-toggle"
          onClick={() => setMenuOpen((s) => !s)}
          aria-expanded={menuOpen}
          aria-controls="mobile-menu"
          aria-label={menuOpen ? "Fechar menu" : "Abrir menu"}
          type="button"
        >
          <HamburgerIcon open={menuOpen} />
        </button>
      </div>

      {/* Mobile drawer */}
      {menuOpen && (
        <div
          id="mobile-menu"
          className="mobile-nav open"
          aria-hidden={false}
        >
          <div className="wrap mobile-nav-inner">
            {links.map((l) => (
              <Link
                className="m-lnk"
                href={l.href}
                key={l.href}
                onClick={() => setMenuOpen(false)}
              >
                {l.label}
              </Link>
            ))}
            <a
              className="m-lnk"
              href={GITHUB_URL}
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => setMenuOpen(false)}
            >
              GitHub
            </a>
            <Link
              className="nav-cta m-cta"
              href={cta.href}
              onClick={() => setMenuOpen(false)}
            >
              <IconDownload /> {cta.label}
            </Link>
          </div>
        </div>
      )}
    </header>
  );
}
