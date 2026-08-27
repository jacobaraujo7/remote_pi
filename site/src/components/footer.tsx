import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";

const GITHUB_URL = "https://github.com/jacobaraujo7/remote_pi";

export function SiteFooter() {
  const t = useTranslations("SiteFooter");

  return (
    <footer className="footer">
      <div className="wrap footer-inner">
        <div className="copy">
          {t.rich("copyright", {
            year: new Date().getFullYear(),
            b: (chunks) => <b>{chunks}</b>,
          })}
        </div>
        <nav className="footer-links">
          <Link href="/cockpit">{t("cockpit")}</Link>
          <Link href="/download">{t("download")}</Link>
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
