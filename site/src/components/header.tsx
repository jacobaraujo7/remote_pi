"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { Link, usePathname } from "@/i18n/navigation";
import { LanguageSwitcher } from "@/components/language-switcher";

import { LogoMark, IconDownload } from "@/components/landing/icons";

/* The site carries two products. Cockpit owns the root, Remote Pi lives under
   /remote-pi, and the nav swaps wholesale so a visitor always sees the links of
   the product they are reading about, plus a way back to the other one. */
type NavLink = { href: string; label: string };

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
  const t = useTranslations("Header");
  const [menuOpen, setMenuOpen] = useState(false);
  /* next-intl's usePathname() returns the path without the locale prefix. */
  const pathname = usePathname() ?? "/";
  const onRemotePi = pathname === "/remote-pi" || pathname.startsWith("/remote-pi/");

  const cockpitLinks: NavLink[] = [
    { href: "/docs", label: t("docs") },
    { href: "/tutorials", label: t("tutorials") },
    { href: "/download", label: t("download") },
    { href: "/remote-pi", label: t("remotePi") },
  ];
  const remotePiLinks: NavLink[] = [
    { href: "/remote-pi/docs", label: t("docs") },
    { href: "/remote-pi/tutorials", label: t("tutorials") },
    { href: "/remote-pi/download", label: t("download") },
    { href: "/remote-pi/why", label: t("whyPi") },
  ];

  const links = onRemotePi ? remotePiLinks : cockpitLinks;
  const home = onRemotePi ? "/remote-pi" : "/";
  const brand = onRemotePi ? t("brandRemotePi") : t("brandCockpit");
  const cta = onRemotePi
    ? { href: "/remote-pi#install", label: t("install") }
    : { href: "/download", label: t("download") };

  return (
    <header className="nav">
      {onRemotePi ? (
        <div className="sibling-bar">
          <div className="wrap sibling-bar-inner">
            <span>
              {t.rich("siblingBar", { strong: (c) => <strong>{c}</strong> })}
            </span>
            <Link href="/">{t("backToCockpit")}</Link>
          </div>
        </div>
      ) : null}
      <div className="wrap nav-inner">
        <Link className="brand" href={home} aria-label={t("homeAria", { brand })}>
          <span className="mark">
            <LogoMark />
          </span>
          {brand}
        </Link>

        {/* Desktop links */}
        <nav className="nav-links" aria-label={t("primaryNav")}>
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
            {t("github")}
          </a>
          <LanguageSwitcher />
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
          aria-label={menuOpen ? t("closeMenu") : t("openMenu")}
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
              {t("github")}
            </a>
            <LanguageSwitcher mobile />
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
