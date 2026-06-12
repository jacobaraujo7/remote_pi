import Link from "next/link";
import { LogoMark, IconDownload } from "@/components/landing/icons";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

export function SiteHeader() {
  return (
    <header className="nav">
      <div className="wrap nav-inner">
        <Link className="brand" href="/" aria-label="Remote Pi — home">
          <span className="mark">
            <LogoMark />
          </span>
          Remote Pi
        </Link>
        <div className="nav-links">
          <Link className="lnk" href="/cockpit">
            Cockpit
          </Link>
          <Link className="lnk" href="/tutorials">
            Tutorials
          </Link>
          <Link className="lnk" href="/docs">
            Docs
          </Link>
          <Link className="lnk" href="/download">
            Download
          </Link>
          <a
            className="lnk"
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub
          </a>
          <Link className="nav-cta" href="/#install">
            <IconDownload /> Install
          </Link>
        </div>
      </div>
    </header>
  );
}
