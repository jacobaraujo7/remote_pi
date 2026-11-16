import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { rich } from "@/lib/rich";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

export function SiteFooter() {
  const t = useTranslations("Footer");
  return (
    <footer className="footer">
      <div className="wrap footer-inner">
        <div className="copy">
          {t.rich("copy", { ...rich, year: new Date().getFullYear() })}
        </div>
        <nav className="footer-links">
          <Link href="/docs">{t("docs")}</Link>
          <Link href="/download">{t("download")}</Link>
          <Link href="/remote-pi">{t("remotePi")}</Link>
          <Link href="/terms">{t("terms")}</Link>
          <Link href="/privacy">{t("privacy")}</Link>
          <a
            href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
            target="_blank"
            rel="noopener noreferrer"
          >
            {t("protocol")}
          </a>
          <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            {t("github")}
          </a>
        </nav>
      </div>
    </footer>
  );
}
